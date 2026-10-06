class ConversationCompactionJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    compacted = false
    begin
      compacted = ConversationCompactionService.perform(@conversation, @conversation.open_ai_service,
        on_retry: ->(attempt, max, wait) { ConversationChannel.broadcast_retry(@conversation, attempt:, max:, wait:) })
    rescue StandardError => e
      Sentry.capture_exception(e)
      Rails.logger.error { "[ConversationCompactionJob] #{e.class}: #{e.message}" }
      raise
    ensure
      if compacted
        ConversationChannel.broadcast_frame(@conversation, show_progress: false)
      else
        @conversation.last_error = 'Compaction failed.'
        @conversation.update_column(:last_error, @conversation.last_error)
        ConversationChannel.broadcast_frame(@conversation, show_progress: false)
      end
      @conversation.mark_unread!
    end
  end
end
