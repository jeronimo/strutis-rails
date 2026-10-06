class OpenAiService
  Error = OpenAiClient::Error
  StoppedError = OpenAiClient::Stopped

  MODELS_TTL = 600

  attr_reader :client

  def self.models
    return @models if @models.present? && @models_fetched_at && (Time.now - @models_fetched_at) <= MODELS_TTL
    begin
      @models = new.client.get('/v1/models', retries: 1)[:data] || []
      @models_fetched_at = Time.now
    rescue OpenAiClient::Error, *OpenAiClient::RETRYABLE_EXCEPTIONS
      Rails.logger.warn '[OpenAI] Models refresh failed, serving stale list' if @models.present?
      raise if @models.blank?
    end
    @models
  end

  def self.model(model_id)
    models.find { |model| model[:id] == model_id }
  end

  def self.display_name(model_id)
    model(model_id)&.dig(:display_name).presence || model_id
  end

  def self.context_length(model_id)
    model(model_id)&.dig(:context_length)
  end

  def self.chat_template_kwargs(model_id)
    model(model_id)&.dig(:chat_template_kwargs)
  end

  def self.supports_image_input?(model_id)
    model(model_id)&.dig(:capabilities, :input)&.include?('image') || false
  end

  def self.supports_text_input?(model_id)
    model(model_id)&.dig(:capabilities, :input)&.include?('text') || false
  end

  def self.supports_stt?(model_id)
    model(model_id)&.dig(:capabilities, :input)&.include?('audio') || false
  end

  def self.visible?(model_id)
    model(model_id)&.dig(:visible) != false
  end

  def self.stt_model
    models.find { |model| supports_stt?(model[:id]) }
  end

  def initialize(conversation_id: nil, user_public_id: nil)
    @conversation_id = conversation_id
    @client = OpenAiClient.new(conversation_id: conversation_id, user_public_id: user_public_id)
  end

  def tools(on_retry: nil)
    client.get('/v1/tools', on_retry: on_retry)[:data] || []
  end

  def transcribe(audio_file, model)
    client.post_multipart('/v1/audio/transcriptions', model, audio_file)[:text].to_s
  end

  def completion(messages, model, tools: nil, chat_template_kwargs: nil, should_stop: nil, on_retry: nil)
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
      stream_request(body, timing, usage, should_stop, on_retry) do |delta|
        if delta[:content] && !delta[:content].empty?
          content << delta[:content]
          yield delta[:content] if block_given?
        end
        reasoning << delta[:reasoning] if delta[:reasoning] && !delta[:reasoning].empty?
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

    arguments = JSON.parse(tool_call.dig(:function, :arguments).to_s)
    response = client.post_to(definition[:endpoint], arguments)
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
    "Tool error (#{name}): request timed out after #{OpenAiClient::OPEN_TIMEOUT}s"
  rescue Net::ReadTimeout => e
    Sentry.capture_exception(e)
    "Tool error (#{name}): read timed out after #{OpenAiClient::READ_TIMEOUT}s"
  rescue SocketError => e
    Sentry.capture_exception(e)
    "Tool error (#{name}): #{e.message}"
  end

  private

  def stream_request(body, timing, usage, should_stop, on_retry)
    first_content = nil
    buffer = +''

    client.post_stream('/v1/chat/completions', body, should_stop:, on_retry:, timing:) do |chunk|
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

    unless buffer.strip.empty?
      parse_sse_event(buffer, usage) do |delta|
        first_content ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) if delta[:content].present?
        yield delta
      end
    end

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_content ||= finish
    timing[:latency_ms] = ms(finish - timing[:start])
    timing[:inference_ms] = ms(first_content - timing[:start])
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

  def ms(seconds)
    (seconds * 1000).round
  end
end
