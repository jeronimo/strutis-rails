require 'net/http'
require 'uri'
require 'json'

class OpenaiService
  STREAM_READ_TIMEOUT = 3600

  class Error < StandardError; end

  MODELS_TTL = 600

  def self.configure
    creds = Rails.application.credentials.openai_api
    @host = creds[:host]
    @port = creds[:port]
    @key = creds[:key]
    @open_timeout = creds[:open_timeout] || 5
    @read_timeout = creds[:read_timeout] || 30
  end

  def self.models
    if @models.nil? || (Time.now - @models_fetched_at) > MODELS_TTL
      @models = request('GET', '/v1/models', nil)[:data] || []
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

  def self.tools
    request('GET', '/v1/tools', nil)[:data] || []
  end

  def self.completion(messages, model, conversation_id = nil, tools: nil, max_tokens: nil, chat_template_kwargs: nil)
    request_body = { model: model, messages: messages, stream: true, stream_options: { include_usage: true } }
    request_body[:conversation_id] = conversation_id if conversation_id
    request_body[:tools] = tools.map { |tool| tool.except(:endpoint) } if tools.present?
    request_body[:max_tokens] = max_tokens if max_tokens
    request_body[:chat_template_kwargs] = chat_template_kwargs if chat_template_kwargs.present?

    timing = {}
    usage = {}
    content = +''
    reasoning = +''
    tool_calls = {}
    stream_request('/v1/chat/completions', request_body, conversation_id, timing, usage) do |delta|
      if delta[:content].present?
        content << delta[:content]
        yield delta[:content] if block_given?
      end
      reasoning << delta[:reasoning] if delta[:reasoning].present?
      accumulate_tool_calls(tool_calls, delta[:tool_calls])
    end

    { content: content, reasoning: reasoning.presence, tool_calls: normalize_tool_calls(tool_calls), latency_ms: timing[:latency_ms], inference_ms: timing[:inference_ms],
      prompt_tokens: usage[:prompt_tokens], completion_tokens: usage[:completion_tokens],
      reasoning_tokens: usage.dig(:completion_tokens_details, :reasoning_tokens) }
  end

  def self.execute_tool(tool_call, tools)
    configure
    name = tool_call.dig(:function, :name)
    definition = tools.find { |tool| tool.dig(:function, :name) == name }
    raise Error, "Unknown tool: #{name}" unless definition

    uri = URI(definition[:endpoint])
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = JSON.parse(tool_call.dig(:function, :arguments).to_s).to_json

    response = http.request(request)
    raise Error, "Tool error: #{response.code} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    body = response.body.force_encoding(Encoding::UTF_8)
    raise Error, 'Tool response is not valid UTF-8' unless body.valid_encoding?
    body
  end

  private

  def self.accumulate_tool_calls(tool_calls, delta_tool_calls)
    return unless delta_tool_calls
    delta_tool_calls.each do |delta|
      call = tool_calls[delta[:index]] ||= { id: nil, type: 'function', name: nil, arguments: +'' }
      call[:id] = delta[:id] if delta[:id]
      call[:type] = delta[:type] if delta[:type]
      call[:name] = delta.dig(:function, :name) if delta.dig(:function, :name)
      call[:arguments] << delta.dig(:function, :arguments) if delta.dig(:function, :arguments)
    end
  end

  def self.normalize_tool_calls(tool_calls)
    tool_calls.values.map { |call| { id: call[:id], type: call[:type], function: { name: call[:name], arguments: call[:arguments] } } }
  end

  def self.request(method, path, body, conversation_id = nil)
    http, uri, request = build_request(method, path, body, conversation_id)
    log_request(request, uri, body)

    response = http.request(request)

    log_response(response)
    raise Error, "OpenAI API error: #{response.code} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body, symbolize_names: true)
  end

  def self.stream_request(path, body, conversation_id, timing, usage)
    http, uri, request = build_request('POST', path, body, conversation_id)
    http.read_timeout = STREAM_READ_TIMEOUT
    log_request(request, uri, body)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_content = nil
    buffer = +''

    http.request(request) do |response|
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error "[OpenAI] Error response body: #{response.body}"
        raise Error, "OpenAI API error: #{response.code} #{response.message}"
      end

      response.read_body do |chunk|
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

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_content ||= finish
    timing[:latency_ms] = ms(finish - start)
    timing[:inference_ms] = ms(first_content - start)
  end

  def self.parse_sse_event(event, usage)
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

  def self.build_request(method, path, body, conversation_id)
    configure
    uri = URI("http://#{@host}:#{@port}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout

    request = case method
    when 'GET'
      Net::HTTP::Get.new(uri)
    when 'POST'
      req = Net::HTTP::Post.new(uri)
      req.body = body.to_json
      req
    end

    request['Authorization'] = "Bearer #{@key}"
    request['Content-Type'] = 'application/json'
    request['X-Conversation-Id'] = conversation_id if conversation_id
    [ http, uri, request ]
  end

  def self.log_request(request, uri, body)
    Rails.logger.info "[OpenAI] #{request.method} #{uri.path}"
    Rails.logger.info "[OpenAI] Request headers: #{request.to_hash.except('Authorization').to_json}"
    Rails.logger.info "[OpenAI] Body: #{body&.to_json}"
  end

  def self.log_response(response)
    Rails.logger.info "[OpenAI] Response status: #{response.code} #{response.message}"
    Rails.logger.info "[OpenAI] Response headers: #{response.to_hash.to_json}"
    Rails.logger.info "[OpenAI] Response body: #{response.body}"
  end

  def self.ms(seconds)
    (seconds * 1000).round
  end
end
