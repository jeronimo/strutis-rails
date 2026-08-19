require 'net/http'
require 'uri'
require 'json'

class OpenaiService
  def self.configure
    creds = Rails.application.credentials.openai_api
    @host = creds[:host]
    @port = creds[:port]
    @key = creds[:key]
  end

  def self.models
    response = request('GET', '/v1/models', nil)
    response[:body][:data] || []
  end

  def self.completion(messages, model, conversation_id = nil)
    request_body = { model: model, messages: messages, stream: false }
    request_body[:conversation_id] = conversation_id if conversation_id

    api_response = request('POST', '/v1/chat/completions', request_body, conversation_id)

    {
      response: api_response[:body][:choices]&.first&.[](:message)&.[](:content) || '',
      conversation_id: (api_response[:headers][:"x-conversation-id"] || [ conversation_id ]).first
    }
  end

  private

  def self.request(method, path, body, conversation_id = nil)
    configure
    uri = URI("http://#{@host}:#{@port}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)

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
    Rails.logger.info "[OpenAI] Request headers: #{request.to_hash.to_json}"
    Rails.logger.info "[OpenAI] Body: #{body&.to_json}"

    response = http.request(request)

    Rails.logger.info "[OpenAI] Response status: #{response.code} #{response.message}"
    Rails.logger.info "[OpenAI] Response headers: #{response.to_hash.to_json}"
    Rails.logger.info "[OpenAI] Response body: #{response.body}"

    unless response.is_a?(Net::HTTPSuccess)
      raise "OpenAI API error: #{response.code} - #{response.message}"
    end

    {
      body: JSON.parse(response.body, symbolize_names: true),
      headers: response.to_hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    }
  end
end
