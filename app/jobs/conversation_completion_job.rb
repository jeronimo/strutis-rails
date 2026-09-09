class ConversationCompletionJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    @finalized = false
    @conversation.update_column(:last_error, nil)
    begin
      run_completion
    ensure
      finish_failed_turn
    end
  end

  private

  def run_completion
    tools = OpenaiService.tools
    metrics = { prompt_tokens: 0, completion_tokens: 0, reasoning_tokens: 0, latency_ms: 0, inference_ms: 0 }
    loop do
      compact_conversation if @conversation.compaction_needed?
      result = stream_turn(tools)
      accumulate_metrics(metrics, result)
      record_context_tokens(result)
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
    result = OpenaiService.completion(@conversation.prompt_messages, @conversation.model, @conversation.public_id, tools: tools,
      chat_template_kwargs: @conversation.chat_template_kwargs) do |delta|
      if @message.nil?
        @message = @conversation.messages.create!(role: 'assistant', content: delta, model: @conversation.model)
        broadcast_frame(show_progress: false)
      else
        broadcast_delta(delta)
      end
    end
    if @message.nil? && result[:reasoning].present?
      @message = @conversation.messages.create!(role: 'assistant', content: '', reasoning: result[:reasoning], model: @conversation.model)
      broadcast_frame(show_progress: false)
    end
    result
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
      tool_result = OpenaiService.execute_tool(tool_call, tools)
      tool_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      @conversation.messages.create!(role: 'tool', tool_call_id: tool_call[:id], content: tool_result, latency_ms: tool_ms, inference_ms: tool_ms, model: @conversation.model)
    end
    broadcast_frame(show_progress: true)
  end

  def compact_conversation
    ConversationCompactionService.perform(@conversation)
  end

  def record_context_tokens(result)
    if result[:prompt_tokens]
      context_tokens = result[:prompt_tokens].to_i + result[:completion_tokens].to_i
      @conversation.context_tokens = context_tokens
      @conversation.update_column(:context_tokens, context_tokens)
    else
      Rails.logger.error { '[ConversationCompletionJob] Usage missing from stream; context_tokens not updated' }
    end
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
      @message.update!(content: result[:content], reasoning: result[:reasoning], latency_ms: metrics[:latency_ms], inference_ms: metrics[:inference_ms],
        prompt_tokens: metrics[:prompt_tokens], completion_tokens: metrics[:completion_tokens],
        reasoning_tokens: metrics[:reasoning_tokens])
      @finalized = true
      if result[:content].blank? && result[:reasoning].present?
        @conversation.last_error = "The model stopped after thinking for #{format_duration(metrics[:latency_ms])} without producing a response."
        @conversation.update_column(:last_error, @conversation.last_error)
      end
      broadcast_frame(show_progress: false)
    end
  end

  def broadcast_frame(show_progress:)
    ConversationChannel.broadcast_frame(@conversation, show_progress:)
  end

  def broadcast_delta(delta)
    ConversationChannel.broadcast_append_to @conversation,
      target: "message-content-#{@message.id}",
      html: ERB::Util.html_escape(delta)
  end

  def finish_failed_turn
    return if @finalized
    @message.destroy! if @message
    @conversation.last_error = 'Completion failed. Please try again.'
    @conversation.update_column(:last_error, @conversation.last_error)
    broadcast_frame(show_progress: false)
  end

  def format_duration(ms)
    seconds = ms.to_i / 1000
    minutes = seconds / 60
    seconds %= 60
    minutes.positive? ? "#{minutes}m #{seconds}s" : "#{seconds}s"
  end
end
