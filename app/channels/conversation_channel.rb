class ConversationChannel < ApplicationCable::Channel
  extend Turbo::Streams::Broadcasts
  extend Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  def subscribed
    @stream_name = verified_stream_name_from_params
    @conversation = current_user&.conversations&.find_by(public_id: params[:public_id])

    if @conversation && @stream_name == self.class.send(:stream_name_from, @conversation)
      stream_from @stream_name
      broadcast_messages_frame
    else
      reject
    end
  end

  private

  def broadcast_messages_frame
    self.class.broadcast_replace_to @conversation,
      target: "messages-#{@conversation.public_id}",
      partial: 'conversations/messages_frame',
      locals: { conversation: @conversation, messages: @conversation.messages, show_progress: false }
  end
end
