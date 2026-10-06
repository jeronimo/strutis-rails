require 'net/http'
require 'uri'
require 'json'
require 'securerandom'

class OpenAiClient
  RETRYABLE_EXCEPTIONS = [ Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::ETIMEDOUT, EOFError, IOError, SocketError, Net::OpenTimeout, Net::ReadTimeout ].freeze
  RETRYABLE_STATUSES = [ 429, 502, 503, 504 ].freeze

  OPEN_TIMEOUT = 5.seconds
  READ_TIMEOUT = 30.seconds
  RETRY_WAITS = [ 5, 10, 20, 40, 80 ].freeze
  STREAM_IDLE_TIMEOUT = 120.seconds
  STREAM_MAX_DURATION = 240.seconds
  TOOL_TIMEOUT = 120.seconds
  STOP_WITHIN = 2.seconds

  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  class Stopped < StandardError; end

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

  def initialize(conversation_id: nil, user_public_id: nil)
    @conversation_id = conversation_id
    @user_public_id = user_public_id
  end

  def get(path, retries: nil, on_retry: nil)
    with_retries(retries:, on_retry:) { exchange_json('GET', path, nil) }
  end

  def post(path, body)
    with_retries { exchange_json('POST', path, body) }
  end

  def post_multipart(path, model, audio_file)
    with_retries { exchange_multipart(path, model, audio_file) }
  end

  def post_stream(path, body, should_stop: nil, on_retry: nil, timing: nil)
    yielded = false
    with_retries(should_stop:, retryable: -> { !yielded }, on_retry:) do
      perform_stream(path, body, should_stop, timing) do |chunk|
        yielded = true
        yield chunk
      end
    end
  end

  def post_to(url, body)
    uri = URI(url)
    http, request = build_request('POST', uri, body)
    http.read_timeout = TOOL_TIMEOUT
    log_request(request, uri, body)

    response = http.request(request)
    log_response(response)
    response
  end

  private

  def with_retries(retries: nil, should_stop: nil, retryable: nil, on_retry: nil)
    max = retries || RETRY_WAITS.length
    attempt = 0
    begin
      attempt += 1
      yield
    rescue *RETRYABLE_EXCEPTIONS, Error => e
      raise unless retriable?(e) && attempt <= max && !should_stop&.call && (retryable.nil? || retryable.call)
      wait = RETRY_WAITS[attempt - 1]
      Rails.logger.warn "[OpenAI] Attempt #{attempt} failed (#{e.class}: #{e.message}), retrying in #{wait}s"
      on_retry&.call(attempt, max, wait)
      sleep(wait)
      retry
    end
  end

  def retriable?(error)
    error.is_a?(Error) ? RETRYABLE_STATUSES.include?(error.status) : true
  end

  def exchange_json(method, path, body)
    uri = URI("http://#{self.class.host}:#{self.class.port}#{path}")
    http, request = build_request(method, uri, body)
    log_request(request, uri, body)

    response = http.request(request)
    log_response(response)
    raise_api_error(response) unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body, symbolize_names: true)
  end

  def exchange_multipart(path, model, audio_file)
    uri = URI("http://#{self.class.host}:#{self.class.port}#{path}")
    http, request = build_multipart_request(uri, model, audio_file)
    log_request(request, uri, model)

    response = http.request(request)
    log_response(response)
    raise_api_error(response) unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body, symbolize_names: true)
  end

  def perform_stream(path, body, should_stop, timing)
    uri = URI("http://#{self.class.host}:#{self.class.port}#{path}")
    http, request = build_request('POST', uri, body)
    http.read_timeout = STREAM_IDLE_TIMEOUT
    log_request(request, uri, body)

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timing[:start] = start if timing
    watchdog = should_stop ? watch_stop(http, should_stop) : nil

    begin
      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.error "[OpenAI] Error response body: #{response.body}"
          raise_api_error(response)
        end

        response.read_body do |chunk|
          raise Stopped if should_stop&.call
          raise Error, "OpenAI stream exceeded #{STREAM_MAX_DURATION}s maximum duration" if Process.clock_gettime(Process::CLOCK_MONOTONIC) - start > STREAM_MAX_DURATION
          yield chunk
        end
      end
    rescue IOError, Errno::ECONNRESET, Errno::EPIPE
      raise Stopped if should_stop&.call
      raise
    ensure
      watchdog&.kill
    end
  end

  def watch_stop(http, should_stop)
    Thread.new do
      loop do
        sleep STOP_WITHIN
        http.finish if should_stop.call
      end
    end
  end

  def build_request(method, uri, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

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
    request['X-Conversation-Id'] = @conversation_id
    request['X-User-Public-Id'] = user_public_id_header
    [ http, request ]
  end

  def build_multipart_request(uri, model, audio_file)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    audio_file.tempfile.rewind
    file_content = audio_file.tempfile.read
    boundary = SecureRandom.hex(16)

    body = +"--#{boundary}\r\n".b
    body << "Content-Disposition: form-data; name=\"model\"\r\nContent-Type: text/plain\r\n\r\n#{model}\r\n".b
    body << "--#{boundary}\r\n".b
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{audio_file.original_filename}\"\r\nContent-Type: #{audio_file.content_type}\r\n\r\n".b
    body << file_content.b
    body << "\r\n--#{boundary}--\r\n".b

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{self.class.key}"
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    request['X-Conversation-Id'] = @conversation_id
    request['X-User-Public-Id'] = user_public_id_header
    request.body = body
    [ http, request ]
  end

  def user_public_id_header
    Rails.env.development? ? "#{@user_public_id}-dev" : @user_public_id
  end

  def raise_api_error(response)
    raise Error.new("OpenAI API error: #{response.code} #{response.message}: #{error_detail(response)}", status: response.code.to_i)
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
end
