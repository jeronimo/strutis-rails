class ConversationCompletionJob < ApplicationJob
  STOP_REQUEST_EXPIRES_AFTER = 20.minutes
  STOP_REQUEST_READ_EVERY = 2.seconds
  ALIVE_EXPIRES_AFTER = 30.seconds
  ALIVE_REWRITE_EVERY = 10.seconds
  MAX_TOOL_ROUNDS = 100

  def self.request_stop(conversation_id)
    Rails.cache.write(stop_key(conversation_id), true, expires_in: STOP_REQUEST_EXPIRES_AFTER)
  end

  def self.stop_requested?(conversation_id)
    requested = Rails.cache.read(stop_key(conversation_id)).present?
    Rails.cache.delete(stop_key(conversation_id)) if requested
    requested
  end

  def self.alive?(conversation_id)
    Rails.cache.exist?(alive_key(conversation_id))
  end

  def self.rewrite_alive(conversation_id)
    Rails.cache.write(alive_key(conversation_id), true, expires_in: ALIVE_EXPIRES_AFTER)
  end

  def self.stop_key(conversation_id)
    "conversation_completion:stop:#{conversation_id}"
  end

  def self.alive_key(conversation_id)
    "conversation_completion:alive:#{conversation_id}"
  end

  def perform(conversation_id)
    self.class.rewrite_alive(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation
    @openai = @conversation.open_ai_service

    @finalized = false
    @failure = nil
    @stopped = false
    @stop_seen = false
    @last_stop_read = 0.0
    @conversation.update_column(:last_error, nil)
    begin
      run_completion
    rescue StandardError => e
      @failure = e
      Sentry.capture_exception(e)
      Rails.logger.error { "[ConversationCompletionJob] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
    ensure
      finish_failed_turn
    end
    if @finalized
      drain_queued_messages
      ConversationTitleJob.perform_later(@conversation.id) if @conversation.title_generation_needed?
    end
  ensure
    Rails.cache.delete(self.class.alive_key(conversation_id))
  end

  private

  def drain_queued_messages
    queued = @conversation.messages.where(role: 'user', queued: true)
    return unless queued.exists?

    queued.find_each do |msg|
      blobs = msg.attachments.map(&:blob)
      content, model = msg.content, msg.model
      msg.destroy!
      @conversation.messages.create!(role: 'user', content: content, model: model).attachments.attach(blobs)
    end
    broadcast_frame(show_progress: true)
    self.class.perform_later(@conversation.id)
  end

  def run_completion
    tools = @openai.tools
    metrics = { prompt_tokens: 0, completion_tokens: 0, reasoning_tokens: 0, latency_ms: 0, inference_ms: 0 }
    turns = 0
    loop do
      if stop_requested_now?
        @stopped = true
        break
      end
      self.class.rewrite_alive(@conversation.id)
      compact_conversation if @conversation.compaction_needed? || @conversation.prompt_over_budget?
      wrap_up = turns >= MAX_TOOL_ROUNDS
      result = stream_turn(wrap_up ? nil : tools)
      if result[:stopped]
        @stopped = true
        @message.update!(content: result[:content]) if @message && result[:content].present?
        break
      end
      accumulate_metrics(metrics, result)
      record_context_tokens(result)
      if result[:tool_calls].present? && !wrap_up
        record_tool_turn(result, tools)
        self.class.rewrite_alive(@conversation.id)
        turns += 1
        next
      end
      finalize(result, metrics)
      break
    end
  end

  def stream_turn(tools)
    @message = nil
    last_alive = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @openai.completion(@conversation.prompt_messages, @conversation.model, tools: tools,
      chat_template_kwargs: @conversation.chat_template_kwargs,
      should_stop: -> { stop_requested_now? }) do |delta|
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if now - last_alive > ALIVE_REWRITE_EVERY
        self.class.rewrite_alive(@conversation.id)
        last_alive = now
      end
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

  def stop_requested_now?
    return true if @stop_seen
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return false if now - @last_stop_read < STOP_REQUEST_READ_EVERY
    @last_stop_read = now
    @stop_seen = self.class.stop_requested?(@conversation.id)
  end

  def record_tool_turn(result, tools)
    if @message
      @message.update!(content: result[:content], tool_calls: result[:tool_calls], latency_ms: result[:latency_ms], inference_ms: result[:inference_ms])
    else
      @message = @conversation.messages.create!(role: 'assistant', content: result[:content], tool_calls: result[:tool_calls], latency_ms: result[:latency_ms], inference_ms: result[:inference_ms], model: @conversation.model)
    end
    broadcast_frame(show_progress: true)
    result[:tool_calls].each do |tool_call|
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tool_result = @openai.execute_tool(tool_call, tools)
      tool_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
      @conversation.messages.create!(role: 'tool', tool_call_id: tool_call[:id], content: tool_result, latency_ms: tool_ms, inference_ms: tool_ms, model: @conversation.model)
    end
    broadcast_frame(show_progress: true)
  end

  def compact_conversation
    ConversationCompactionService.perform(@conversation, @openai)
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
      @conversation.update_column(:unread, true)
      UserChannel.broadcast_unread(@conversation, unread: true)
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
    record_unexecuted_tools
    @conversation.last_error = if @stopped
      'Stopped by user.'
    elsif @failure
      "Completion failed: #{@failure.message}"
    else
      'Completion failed. Please try again.'
    end
    @conversation.update_column(:last_error, @conversation.last_error)
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

  def format_duration(ms)
    seconds = ms.to_i / 1000
    minutes = seconds / 60
    seconds %= 60
    minutes.positive? ? "#{minutes}m #{seconds}s" : "#{seconds}s"
  end
end
