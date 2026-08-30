class ConversationCompletionJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    content = assistant_response(@conversation)
    @conversation.messages.create!(role: 'assistant', content: content, model: @conversation.model)
    broadcast_messages
  rescue StandardError => e
    Rails.logger.error "[ConversationCompletionJob] #{e.class}: #{e.message}"
    broadcast_error if @conversation
  end

  private

  def assistant_response(conversation)
    messages = conversation.messages.map { |message| { role: message.role, content: message.content } }
    OpenaiService.completion(messages, conversation.model, conversation.public_id)
  end

  def broadcast_messages
    ConversationChannel.broadcast_replace_to @conversation,
      target: "messages-#{@conversation.public_id}",
      partial: 'conversations/messages_frame',
      locals: { conversation: @conversation, messages: @conversation.messages.reload }
  end

  def broadcast_error
    ConversationChannel.broadcast_replace_to @conversation,
      target: 'conversation-error',
      html: ApplicationController.render(partial: 'conversations/error', locals: { error: 'Completion failed.' }, formats: :html)
  end
end
