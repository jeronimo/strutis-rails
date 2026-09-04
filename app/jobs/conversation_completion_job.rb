class ConversationCompletionJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    @finalized = false
    run_completion
  rescue StandardError => e
    Rails.logger.error "[ConversationCompletionJob] #{e.class}: #{e.message}"
    discard_message
    broadcast_frame(show_progress: false) if @conversation
    broadcast_error if @conversation
  end

  private

  def run_completion
    tools = OpenaiService.tools
    metrics = { prompt_tokens: 0, completion_tokens: 0, reasoning_tokens: 0, latency_ms: 0, inference_ms: 0 }
    loop do
      result = stream_turn(tools)
      accumulate_metrics(metrics, result)
      if result[:tool_calls].present?
        record_tool_turn(result, tools)
        next
      end
      finalize(result, metrics)
      break
    end
  end

  def stream_turn(tools)
    @message = nil
    OpenaiService.completion(prompt, @conversation.model, @conversation.public_id, tools: tools) do |delta|
      if @message.nil?
        @message = @conversation.messages.create!(role: 'assistant', content: delta, model: @conversation.model)
        broadcast_frame(show_progress: false)
      else
        broadcast_delta(delta)
      end
    end
  end

  def prompt
    @conversation.messages.map do |message|
      entry = { role: message.role, content: message.content }
      entry[:tool_calls] = message.tool_calls if message.tool_calls.present?
      entry[:tool_call_id] = message.tool_call_id if message.tool_call_id.present?
      entry
    end
  end

  def record_tool_turn(result, tools)
    if @message
      @message.update!(content: result[:content], tool_calls: result[:tool_calls])
    else
      @message = @conversation.messages.create!(role: 'assistant', content: result[:content], tool_calls: result[:tool_calls], model: @conversation.model)
    end
    broadcast_frame(show_progress: true)
    result[:tool_calls].each do |tool_call|
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tool_result = execute_tool(tool_call, tools)
      tool_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      @conversation.messages.create!(role: 'tool', tool_call_id: tool_call[:id], content: tool_result, latency_ms: tool_ms, inference_ms: tool_ms, model: @conversation.model)
    end
    broadcast_frame(show_progress: true)
  end

  def execute_tool(tool_call, tools)
    OpenaiService.execute_tool(tool_call, tools)
  rescue StandardError => e
    Rails.logger.error "[ConversationCompletionJob] Tool #{tool_call.dig(:function, :name)} failed: #{e.class}: #{e.message}"
    { error: e.message }.to_json
  end

  def accumulate_metrics(metrics, result)
    metrics[:prompt_tokens] += result[:prompt_tokens].to_i
    metrics[:completion_tokens] += result[:completion_tokens].to_i
    metrics[:reasoning_tokens] += result[:reasoning_tokens].to_i
    metrics[:latency_ms] += result[:latency_ms].to_i
    metrics[:inference_ms] += result[:inference_ms].to_i
  end

  def finalize(result, metrics)
    if @message
      @message.update!(content: result[:content], latency_ms: metrics[:latency_ms], inference_ms: metrics[:inference_ms],
        prompt_tokens: metrics[:prompt_tokens], completion_tokens: metrics[:completion_tokens],
        reasoning_tokens: metrics[:reasoning_tokens])
      @finalized = true
      broadcast_frame(show_progress: false)
    else
      broadcast_frame(show_progress: false)
      broadcast_error
    end
  end

  def broadcast_frame(show_progress:)
    ConversationChannel.broadcast_replace_to @conversation,
      target: "messages-#{@conversation.public_id}",
      partial: 'conversations/messages_frame',
      locals: { conversation: @conversation, messages: @conversation.messages.reload, show_progress: }
  end

  def broadcast_delta(delta)
    ConversationChannel.broadcast_append_to @conversation,
      target: "message-content-#{@message.id}",
      html: ERB::Util.html_escape(delta)
  end

  def discard_message
    return unless @message && !@finalized
    @message.destroy!
    @message = nil
  end

  def broadcast_error
    ConversationChannel.broadcast_replace_to @conversation,
      target: 'conversation-error',
      html: ApplicationController.render(partial: 'conversations/error', locals: { error: 'Completion failed.' }, formats: :html)
  end
end
