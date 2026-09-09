class ConversationTitleJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation
    return unless @conversation.title_generation_needed?

    title = ConversationTitleService.perform(@conversation)
    return if title.blank?

    ConversationChannel.broadcast_title(@conversation)
  end
end
