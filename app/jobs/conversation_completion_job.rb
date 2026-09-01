class ConversationCompletionJob < ApplicationJob
  def perform(conversation_id)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    @finalized = false
    result = assistant_response
    if @message
      @message.update!(content: result[:content], latency_ms: result[:latency_ms], inference_ms: result[:inference_ms])
      @finalized = true
      broadcast_messages
    else
      broadcast_error
    end
  rescue StandardError => e
    Rails.logger.error "[ConversationCompletionJob] #{e.class}: #{e.message}"
    discard_message
    broadcast_error if @conversation
  end

  private

  def assistant_response
    prompt = @conversation.messages.map { |message| { role: message.role, content: message.content } }
    @message = nil
    OpenaiService.completion(prompt, @conversation.model, @conversation.public_id) do |delta|
      if @message.nil?
        @message = @conversation.messages.create!(role: 'assistant', content: delta, model: @conversation.model)
        broadcast_append_message
      else
        broadcast_delta(delta)
      end
    end
  end

  def broadcast_append_message
    ConversationChannel.broadcast_append_to @conversation,
      target: "messages-#{@conversation.public_id}",
      partial: 'conversations/message',
      locals: { message: @message }
  end

  def broadcast_delta(delta)
    ConversationChannel.broadcast_append_to @conversation,
      target: "message-content-#{@message.id}",
      html: ERB::Util.html_escape(delta)
  end

  def broadcast_messages
    ConversationChannel.broadcast_replace_to @conversation,
      target: "messages-#{@conversation.public_id}",
      partial: 'conversations/messages_frame',
      locals: { conversation: @conversation, messages: @conversation.messages.reload }
  end

  def discard_message
    return unless @message && !@finalized
    @message.destroy!
    @message = nil
    broadcast_messages
  end

  def broadcast_error
    ConversationChannel.broadcast_replace_to @conversation,
      target: 'conversation-error',
      html: ApplicationController.render(partial: 'conversations/error', locals: { error: 'Completion failed.' }, formats: :html)
  end
end
