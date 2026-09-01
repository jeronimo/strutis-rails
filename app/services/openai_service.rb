require 'net/http'
require 'uri'
require 'json'

class OpenaiService
  def self.configure
    creds = Rails.application.credentials.openai_api
    @host = creds[:host]
    @port = creds[:port]
    @key = creds[:key]
    @open_timeout = creds[:open_timeout] || 5
    @read_timeout = creds[:read_timeout] || 30
  end

  def self.models
    request('GET', '/v1/models', nil)[:data] || []
  end

  def self.completion(messages, model, conversation_id = nil)
    request_body = { model: model, messages: messages, stream: true }
    request_body[:conversation_id] = conversation_id if conversation_id

    timing = {}
    content = +''
    stream_request('/v1/chat/completions', request_body, conversation_id, timing) do |delta|
      content << delta
      yield delta
    end

    { content: content, latency_ms: timing[:latency_ms], inference_ms: timing[:inference_ms] }
  end

  private

  def self.request(method, path, body, conversation_id = nil)
    http, uri, request = build_request(method, path, body, conversation_id)
    log_request(request, uri, body)

    response = http.request(request)

    log_response(response)
    raise "OpenAI API error: #{response.code} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body, symbolize_names: true)
  end

  def self.stream_request(path, body, conversation_id, timing)
    http, uri, request = build_request('POST', path, body, conversation_id)
    log_request(request, uri, body)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_token = nil
    buffer = +''

    http.request(request) do |response|
      raise "OpenAI API error: #{response.code} - #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      response.read_body do |chunk|
        buffer << chunk
        buffer.gsub!("\r\n", "\n")
        while (separator = buffer.index("\n\n"))
          event = buffer[0...separator]
          buffer = buffer[(separator + 2)..]
          parse_sse_event(event) do |delta|
            first_token ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
            yield delta
          end
        end
      end
    end

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_token ||= finish
    timing[:latency_ms] = ms(finish - start)
    timing[:inference_ms] = ms(first_token - start)
  end

  def self.parse_sse_event(event)
    event.each_line do |line|
      next unless line.start_with?('data:')
      data = line[5..].strip
      next if data == '[DONE]'
      json = JSON.parse(data, symbolize_names: true)
      delta = json.dig(:choices, 0, :delta, :content)
      yield delta if delta.present?
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
