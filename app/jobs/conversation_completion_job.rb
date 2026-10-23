class ConversationCompletionJob < ConversationTurnJob
  MAX_TOOL_ROUNDS = 100
  DELTA_FLUSH_EVERY = 0.2

  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return if @conversation.nil?

    @finalized = false
    @failure = nil
    @stopped = false
    @message = nil
    @retry_pending = false
    with_turn(@conversation) { run_turn }
    if drain_queued_messages
      self.class.perform_later(@conversation.id)
    else
      UserChannel.broadcast_progress(@conversation, active: false)
    end
    ConversationTitleJob.perform_later(@conversation.id) if @finalized && @conversation.title_generation_needed?
  end

  private

  def run_turn
    @metrics = { prompt_tokens: 0, completion_tokens: 0, reasoning_tokens: 0, latency_ms: 0, inference_ms: 0 }
    @openai = @conversation.open_ai_service
    ConversationChannel.broadcast_progress(@conversation, active: true)
    begin
      run_completion
    rescue StandardError => e
      @failure = e
      Sentry.capture_exception(e)
      Rails.logger.error { "[ConversationCompletionJob] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
    ensure
      finish_failed_turn
    end
  end

  def run_completion
    tools = @openai.tools(on_retry: method(:notify_retry))
    clear_retry
    turns = 0
    loop do
      if stop_requested?
        @stopped = true
        @conversation.clear_stop!
        break
      end
      if @conversation.compaction_needed? || @conversation.prompt_over_budget?
        broadcast_frame(show_progress: true) if compact_conversation
      end
      wrap_up = turns >= MAX_TOOL_ROUNDS
      result = stream_turn(wrap_up ? nil : tools)
      if result[:stopped]
        @stopped = true
        @conversation.clear_stop!
        @message.update!(content: result[:content]) if @message && result[:content].present?
        break
      end
      accumulate_metrics(result)
      record_context_tokens(result)
      if result[:tool_calls].present? && !wrap_up
        record_tool_turn(result, tools)
        turns += 1
        next
      end
      finalize(result)
      break
    end
  end

  def stream_turn(tools)
    @message = nil
    buffer = +''
    last_flush = nil
    result = @openai.completion(@conversation.prompt_messages, @conversation.model, tools: tools,
      chat_template_kwargs: @conversation.chat_template_kwargs,
      should_stop: -> { @monitor.stop_requested? }, on_retry: method(:notify_retry)) do |delta|
      buffer << delta
      if @message.nil?
        next if buffer.blank?
        @message = @conversation.messages.create!(role: 'assistant', content: buffer, model: @conversation.model)
        ConversationChannel.broadcast_message(@conversation, @message)
        clear_retry
        buffer.clear
        last_flush = monotonic
      else
        now = monotonic
        if now - last_flush >= DELTA_FLUSH_EVERY
          broadcast_delta(buffer)
          buffer.clear
          last_flush = now
        end
      end
    end
    clear_retry
    broadcast_delta(buffer) if @message && buffer.present?
    if @message.nil? && result[:reasoning].present?
      @message = @conversation.messages.create!(role: 'assistant', content: '', reasoning: result[:reasoning], model: @conversation.model)
      ConversationChannel.broadcast_message(@conversation, @message)
    end
    result
  end

  def record_tool_turn(result, tools)
    if @message
      @message.update!(content: result[:content], tool_calls: result[:tool_calls], latency_ms: result[:latency_ms], inference_ms: result[:inference_ms])
      ConversationChannel.replace_message(@conversation, @message)
    else
      @message = @conversation.messages.create!(role: 'assistant', content: result[:content], tool_calls: result[:tool_calls], latency_ms: result[:latency_ms], inference_ms: result[:inference_ms], model: @conversation.model)
      ConversationChannel.broadcast_message(@conversation, @message)
    end
    result[:tool_calls].each do |tool_call|
      break if stop_requested?
      start = monotonic
      tool_result = @openai.execute_tool(tool_call, tools)
      tool_ms = ((monotonic - start) * 1000).round
      tool_message = @conversation.messages.create!(role: 'tool', tool_call_id: tool_call[:id], content: tool_result, latency_ms: tool_ms, inference_ms: tool_ms, model: @conversation.model)
      ConversationChannel.broadcast_message(@conversation, tool_message)
    end
  end

  def compact_conversation
    ConversationCompactionService.perform(@conversation, @openai, on_retry: method(:notify_retry))
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

  def accumulate_metrics(result)
    @metrics[:prompt_tokens] += result[:prompt_tokens].to_i
    @metrics[:completion_tokens] += result[:completion_tokens].to_i
    @metrics[:reasoning_tokens] += result[:reasoning_tokens].to_i
    @metrics[:latency_ms] += result[:latency_ms].to_i
    @metrics[:inference_ms] += result[:inference_ms].to_i
  end

  def finalize(result)
    if @message
      @message.update!(content: result[:content], reasoning: result[:reasoning], latency_ms: @metrics[:latency_ms], inference_ms: @metrics[:inference_ms],
        prompt_tokens: @metrics[:prompt_tokens], completion_tokens: @metrics[:completion_tokens],
        reasoning_tokens: @metrics[:reasoning_tokens])
      @finalized = true
      @conversation.mark_unread!
      if result[:content].blank? && result[:reasoning].present?
        @conversation.last_error = ConversationError.thinking_only(@metrics[:latency_ms])
        @conversation.update_column(:last_error, @conversation.last_error)
        ConversationChannel.broadcast_error(@conversation)
      end
      ConversationChannel.replace_message(@conversation, @message)
      ConversationChannel.broadcast_progress(@conversation, active: false)
      ConversationChannel.broadcast_context_usage(@conversation)
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

  def notify_retry(attempt, max, wait)
    @retry_pending = true
    ConversationChannel.broadcast_retry(@conversation, attempt:, max:, wait:)
  end

  def clear_retry
    return unless @retry_pending
    @retry_pending = false
    ConversationChannel.broadcast_retry_clear(@conversation)
  end

  def stop_requested?
    @monitor.stop_requested? || Conversation.stop_requested_for?(@conversation.id)
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def finish_failed_turn
    return if @finalized
    record_unexecuted_tools
    if @message&.content.present?
      @message.update!(latency_ms: @metrics[:latency_ms], inference_ms: @metrics[:inference_ms])
      ConversationChannel.replace_message(@conversation, @message)
    end
    @conversation.last_error = ConversationError.from_failure(stopped: @stopped, failure: @failure)
    @conversation.update_column(:last_error, @conversation.last_error)
    @conversation.mark_unread!
    broadcast_frame(show_progress: false)
  end

  def record_unexecuted_tools
    return unless @message&.tool_calls.present?
    executed = @conversation.messages.where(role: 'tool').where(tool_call_id: tool_call_ids).pluck(:tool_call_id)
    tool_call_ids.each do |id|
      next if executed.include?(id)
      @conversation.messages.create!(role: 'tool', tool_call_id: id, content: "Tool not executed: #{@failure&.message}", model: @conversation.model)
    end
  end

  def tool_call_ids
    @message.tool_calls.map { |tool_call| tool_call[:id] || tool_call['id'] }
  end
end
