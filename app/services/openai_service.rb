require 'net/http'
require 'uri'
require 'json'

class OpenaiService
  STREAM_READ_TIMEOUT = 3600
  MODELS_TTL = 600

  class Error < StandardError; end
  class StoppedError < StandardError; end

  def self.credentials
    Rails.application.credentials.openai_api
  end

  def self.host
    credentials[:host]
  end

  def self.port
    credentials[:port]
  end

  def self.key
    credentials[:key]
  end

  def self.open_timeout
    credentials[:open_timeout] || 5
  end

  def self.read_timeout
    credentials[:read_timeout] || 30
  end

  def self.models
    if @models.nil? || (Time.now - @models_fetched_at) > MODELS_TTL
      @models = new.request('GET', '/v1/models', nil)[:data] || []
      @models_fetched_at = Time.now
    end
    @models
  end

  def self.model(model_id)
    models.find { |model| model[:id] == model_id }
  end

  def self.context_length(model_id)
    model(model_id)&.dig(:context_length)
  end

  def self.chat_template_kwargs(model_id)
    model(model_id)&.dig(:chat_template_kwargs)
  end

  def initialize(conversation_id: nil, user_public_id: nil)
    @conversation_id = conversation_id
    @user_public_id = user_public_id
  end

  def tools
    request('GET', '/v1/tools', nil)[:data] || []
  end

  def completion(messages, model, tools: nil, chat_template_kwargs: nil, should_stop: nil)
    body = { model: model, messages: messages, stream: true, stream_options: { include_usage: true } }
    body[:conversation_id] = @conversation_id if @conversation_id
    body[:tools] = tools.map { |tool| tool.except(:endpoint).tap { |t| t[:function] = t[:function].merge(strict: true) if t[:function].is_a?(Hash) } } if tools.present?
    body[:chat_template_kwargs] = chat_template_kwargs if chat_template_kwargs.present?

    timing = {}
    usage = {}
    content = +''
    reasoning = +''
    tool_calls = {}
    stopped = false
    begin
      stream_request('/v1/chat/completions', body, timing, usage, should_stop) do |delta|
        if delta[:content].present?
          content << delta[:content]
          yield delta[:content] if block_given?
        end
        reasoning << delta[:reasoning] if delta[:reasoning].present?
        accumulate_tool_calls(tool_calls, delta[:tool_calls])
      end
    rescue StoppedError
      stopped = true
    end

    { content: content, reasoning: reasoning.presence, tool_calls: normalize_tool_calls(tool_calls), stopped: stopped, latency_ms: timing[:latency_ms], inference_ms: timing[:inference_ms],
      prompt_tokens: usage[:prompt_tokens], completion_tokens: usage[:completion_tokens],
      reasoning_tokens: usage.dig(:completion_tokens_details, :reasoning_tokens) }
  end

  def execute_tool(tool_call, tools)
    name = tool_call.dig(:function, :name)
    definition = tools.find { |tool| tool.dig(:function, :name) == name }
    return "Unknown tool: #{name}. Allowed tools: #{tools.map { |tool| tool.dig(:function, :name) }.join(', ')}." unless definition

    uri = URI(definition[:endpoint])
    body = JSON.parse(tool_call.dig(:function, :arguments).to_s)
    http, request = build_request('POST', uri, body)
    log_request(request, uri, body)

    response = http.request(request)
    log_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      body = response.body.to_s
      return body if body.strip.present?
      return "Tool error (#{name}): #{response.code} - #{response.message}"
    end

    body = response.body.force_encoding(Encoding::UTF_8)
    return "Tool error (#{name}): response is not valid UTF-8" unless body.valid_encoding?
    body
  rescue JSON::ParserError => e
    Sentry.capture_exception(e)
    "Tool error (#{name}): invalid arguments: #{e.message}"
  rescue Net::OpenTimeout => e
    Sentry.capture_exception(e)
    "Tool error (#{name}): request timed out after #{self.class.open_timeout}s"
  rescue Net::ReadTimeout => e
    Sentry.capture_exception(e)
    "Tool error (#{name}): read timed out after #{self.class.read_timeout}s"
  rescue SocketError => e
    Sentry.capture_exception(e)
    "Tool error (#{name}): #{e.message}"
  end

  def request(method, path, body)
    uri = URI("http://#{self.class.host}:#{self.class.port}#{path}")
    http, request = build_request(method, uri, body)
    log_request(request, uri, body)

    response = http.request(request)

    log_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "OpenAI API error: #{response.code} #{response.message}: #{error_detail(response)}"
    end

    JSON.parse(response.body, symbolize_names: true)
  end

  private

  def stream_request(path, body, timing, usage, should_stop)
    uri = URI("http://#{self.class.host}:#{self.class.port}#{path}")
    http, request = build_request('POST', uri, body)
    http.read_timeout = STREAM_READ_TIMEOUT
    log_request(request, uri, body)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_content = nil
    buffer = +''

    http.request(request) do |response|
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error "[OpenAI] Error response body: #{response.body}"
        raise Error, "OpenAI API error: #{response.code} #{response.message}: #{error_detail(response)}"
      end

      response.read_body do |chunk|
        raise StoppedError if should_stop&.call
        buffer << chunk
        buffer.gsub!("\r\n", "\n")
        while (separator = buffer.index("\n\n"))
          event = buffer[0...separator]
          buffer = buffer[(separator + 2)..]
          parse_sse_event(event, usage) do |delta|
            first_content ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) if delta[:content].present?
            yield delta
          end
        end
      end
    end

    unless buffer.strip.empty?
      parse_sse_event(buffer, usage) do |delta|
        first_content ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) if delta[:content].present?
        yield delta
      end
    end

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_content ||= finish
    timing[:latency_ms] = ms(finish - start)
    timing[:inference_ms] = ms(first_content - start)
  end

  def build_request(method, uri, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = self.class.open_timeout
    http.read_timeout = self.class.read_timeout

    request = case method
    when 'GET'
      Net::HTTP::Get.new(uri)
    when 'POST'
      req = Net::HTTP::Post.new(uri)
      req.body = body.to_json
      req
    end

    request['Authorization'] = "Bearer #{self.class.key}"
    request['Content-Type'] = 'application/json'
    request['X-Conversation-Id'] = @conversation_id if @conversation_id
    request['X-User-Public-Id'] = user_public_id_header if @user_public_id
    [ http, request ]
  end

  def user_public_id_header
    Rails.env.development? ? "#{@user_public_id}-dev" : @user_public_id
  end

  def error_detail(response)
    body = response.body.to_s
    parsed = JSON.parse(body)
    if parsed.is_a?(Hash)
      error = parsed['error']
      detail = error.is_a?(Hash) ? error['message'] : error
      return detail if detail.is_a?(String) && detail.present?
    end
    body
  rescue JSON::ParserError => e
    Sentry.capture_exception(e)
    body
  end

  def accumulate_tool_calls(tool_calls, delta_tool_calls)
    return unless delta_tool_calls
    delta_tool_calls.each do |delta|
      call = tool_calls[delta[:index]] ||= { id: nil, type: 'function', name: nil, arguments: +'' }
      call[:id] = delta[:id] if delta[:id]
      call[:type] = delta[:type] if delta[:type]
      call[:name] = delta.dig(:function, :name) if delta.dig(:function, :name)
      call[:arguments] << delta.dig(:function, :arguments) if delta.dig(:function, :arguments)
    end
  end

  def normalize_tool_calls(tool_calls)
    tool_calls.values.map { |call| { id: call[:id], type: call[:type], function: { name: call[:name], arguments: call[:arguments] } } }
  end

  def parse_sse_event(event, usage)
    event.each_line do |line|
      next unless line.start_with?('data:')
      data = line[5..].strip
      next if data == '[DONE]'
      json = JSON.parse(data, symbolize_names: true)
      usage.merge!(json[:usage]) if json[:usage]
      delta = json.dig(:choices, 0, :delta)
      yield delta if delta
    end
  end

  def log_request(request, uri, body)
    Rails.logger.info "[OpenAI] #{request.method} #{uri.path}"
    Rails.logger.info "[OpenAI] Request headers: #{request.to_hash.except('Authorization').to_json}"
    Rails.logger.info "[OpenAI] Body: #{body&.to_json}"
  end

  def log_response(response)
    Rails.logger.info "[OpenAI] Response status: #{response.code} #{response.message}"
    Rails.logger.info "[OpenAI] Response headers: #{response.to_hash.to_json}"
    Rails.logger.info "[OpenAI] Response body: #{response.body}"
  end

  def ms(seconds)
    (seconds * 1000).round
  end
end
