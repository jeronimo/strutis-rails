class ConversationCompactionJob < ConversationTurnJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    @compacted = false
    begin
      with_turn(@conversation) do
        @compacted = ConversationCompactionService.perform(@conversation, @conversation.open_ai_service,
          on_retry: method(:notify_retry))
      end
    rescue StandardError => e
      Sentry.capture_exception(e)
      Rails.logger.error { "[ConversationCompactionJob] #{e.class}: #{e.message}" }
      raise
    ensure
      finish
    end
  end

  private

  def finish
    @conversation.update_column(:last_error, ConversationError::COMPACTION_FAILED) unless @compacted
    ConversationChannel.broadcast_frame(@conversation, show_progress: false)
    @conversation.mark_unread!
    if drain_queued_messages
      ConversationCompletionJob.perform_later(@conversation.id)
    else
      UserChannel.broadcast_progress(@conversation, active: false)
    end
  end

  def notify_retry(attempt, max, wait)
    ConversationChannel.broadcast_retry(@conversation, attempt:, max:, wait:)
  end
end
