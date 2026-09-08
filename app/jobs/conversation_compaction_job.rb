class ConversationCompactionJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    compacted = false
    begin
      compacted = ConversationCompactionService.perform(@conversation)
    ensure
      if compacted
        ConversationChannel.broadcast_frame(@conversation, show_progress: false)
      else
        @conversation.last_error = 'Compaction failed.'
        @conversation.update_column(:last_error, @conversation.last_error)
        ConversationChannel.broadcast_frame(@conversation, show_progress: false)
      end
    end
  end
end
