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
    request_body = { model: model, messages: messages, stream: false }
    request_body[:conversation_id] = conversation_id if conversation_id

    response = request('POST', '/v1/chat/completions', request_body, conversation_id)
    response[:choices]&.first&.[](:message)&.[](:content) || ''
  end

  private

  def self.request(method, path, body, conversation_id = nil)
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

    Rails.logger.info "[OpenAI] #{request.method} #{uri.path}"
    Rails.logger.info "[OpenAI] Request headers: #{request.to_hash.except('Authorization').to_json}"
    Rails.logger.info "[OpenAI] Body: #{body&.to_json}"

    response = http.request(request)

    Rails.logger.info "[OpenAI] Response status: #{response.code} #{response.message}"
    Rails.logger.info "[OpenAI] Response headers: #{response.to_hash.to_json}"
    Rails.logger.info "[OpenAI] Response body: #{response.body}"

    unless response.is_a?(Net::HTTPSuccess)
      raise "OpenAI API error: #{response.code} - #{response.message}"
    end

    JSON.parse(response.body, symbolize_names: true)
  end
end
