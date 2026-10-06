class OpenAiService
  Error = OpenAiClient::Error
  StoppedError = OpenAiClient::Stopped

  attr_reader :client

  def self.models
    ModelCatalog.models
  end

  def self.model(model_id)
    ModelCatalog.model(model_id)
  end

  def self.display_name(model_id)
    ModelCatalog.display_name(model_id)
  end

  def self.context_length(model_id)
    ModelCatalog.context_length(model_id)
  end

  def self.chat_template_kwargs(model_id)
    ModelCatalog.chat_template_kwargs(model_id)
  end

  def self.supports_image_input?(model_id)
    ModelCatalog.supports_image_input?(model_id)
  end

  def self.supports_text_input?(model_id)
    ModelCatalog.supports_text_input?(model_id)
  end

  def self.supports_stt?(model_id)
    ModelCatalog.supports_stt?(model_id)
  end

  def self.visible?(model_id)
    ModelCatalog.visible?(model_id)
  end

  def self.stt_model
    ModelCatalog.stt_model
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
    body = build_body(messages, model, tools, chat_template_kwargs)
    timing = {}
    usage = {}
    content = +''
    reasoning = +''
    tool_calls = ToolCallAccumulator.new
    stopped = false
    begin
      stream_request(body, timing, usage, should_stop, on_retry) do |delta|
        if delta[:content] && !delta[:content].empty?
          content << delta[:content]
          yield delta[:content] if block_given?
        end
        reasoning << delta[:reasoning] if delta[:reasoning] && !delta[:reasoning].empty?
        tool_calls.add(delta[:tool_calls])
      end
    rescue StoppedError
      stopped = true
    end

    { content: content, reasoning: reasoning.presence, tool_calls: tool_calls.normalized, stopped: stopped, latency_ms: timing[:latency_ms], inference_ms: timing[:inference_ms],
      prompt_tokens: usage[:prompt_tokens], completion_tokens: usage[:completion_tokens],
      reasoning_tokens: usage.dig(:completion_tokens_details, :reasoning_tokens) }
  end

  def execute_tool(tool_call, tools)
    ToolExecutor.new(client).execute(tool_call, tools)
  end

  private

  def build_body(messages, model, tools, chat_template_kwargs)
    body = { model: model, messages: messages, stream: true, stream_options: { include_usage: true } }
    body[:conversation_id] = @conversation_id if @conversation_id
    body[:tools] = tools.map { |tool| tool.except(:endpoint).tap { |t| t[:function] = t[:function].merge(strict: true) if t[:function].is_a?(Hash) } } if tools.present?
    body[:chat_template_kwargs] = chat_template_kwargs if chat_template_kwargs.present?
    body
  end

  def stream_request(body, timing, usage, should_stop, on_retry)
    parser = SseParser.new
    first_content = nil

    client.post_stream('/v1/chat/completions', body, should_stop:, on_retry:, timing:) do |chunk|
      parser.push(chunk) do |delta|
        first_content ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) if delta[:content].present?
        yield delta
      end
    end

    parser.finish do |delta|
      first_content ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) if delta[:content].present?
      yield delta
    end

    usage.merge!(parser.usage)

    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    first_content ||= finish
    timing[:latency_ms] = ms(finish - timing[:start])
    timing[:inference_ms] = ms(first_content - timing[:start])
  end

  def ms(seconds)
    (seconds * 1000).round
  end
end
