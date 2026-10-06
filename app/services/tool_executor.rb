class ToolExecutor
  def initialize(client)
    @client = client
  end

  def execute(tool_call, tools)
    name = tool_call.dig(:function, :name)
    definition = tools.find { |tool| tool.dig(:function, :name) == name }
    return "Unknown tool: #{name}. Allowed tools: #{tools.map { |tool| tool.dig(:function, :name) }.join(', ')}." unless definition

    arguments = JSON.parse(tool_call.dig(:function, :arguments).to_s)
    response = @client.post_to(definition[:endpoint], arguments)
    unless response.is_a?(Net::HTTPSuccess)
      body = response.body.to_s
      return body if body.strip.present?
      return "Tool error (#{name}): #{response.code} - #{response.message}"
    end

    body = response.body.force_encoding(Encoding::UTF_8)
    return "Tool error (#{name}): response is not valid UTF-8" unless body.valid_encoding?
    body
  rescue JSON::ParserError => e
    report(e, name, "invalid arguments: #{e.message}")
  rescue Net::OpenTimeout => e
    report(e, name, "request timed out after #{OpenAiClient::OPEN_TIMEOUT}s")
  rescue Net::ReadTimeout => e
    report(e, name, "read timed out after #{OpenAiClient::READ_TIMEOUT}s")
  rescue SocketError => e
    report(e, name, e.message)
  end

  private

  def report(exception, name, detail)
    Sentry.capture_exception(exception)
    "Tool error (#{name}): #{detail}"
  end
end
