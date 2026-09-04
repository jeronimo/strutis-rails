class ConversationCompactionJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    ConversationCompactionService.perform(@conversation)
    ConversationChannel.broadcast_frame(@conversation, show_progress: false)
  rescue StandardError => e
    Rails.logger.error "[ConversationCompactionJob] #{e.class}: #{e.message}"
    ConversationChannel.broadcast_frame(@conversation, show_progress: false) if @conversation
    broadcast_error if @conversation
  end

  private

  def broadcast_error
    ConversationChannel.broadcast_replace_to @conversation,
      target: 'conversation-error',
      html: ApplicationController.render(partial: 'conversations/error', locals: { error: 'Compaction failed.' }, formats: :html)
  end
end
