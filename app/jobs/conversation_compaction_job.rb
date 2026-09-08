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
        broadcast_error
      end
    end
  end

  private

  def broadcast_error
    ConversationChannel.broadcast_replace_to @conversation,
      target: 'conversation-error',
      html: ApplicationController.render(partial: 'conversations/error', locals: { error: 'Compaction failed.' }, formats: :html)
  end
end
