class ConversationChannel < ApplicationCable::Channel
  extend Turbo::Streams::Broadcasts
  extend Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  def self.broadcast_frame(conversation, show_progress:)
    broadcast_replace_to conversation,
      target: "messages-#{conversation.public_id}",
      partial: 'conversations/messages_frame',
      locals: { conversation:, messages: conversation.messages.reload, show_progress: }
  end

  def self.broadcast_title(conversation)
    title = ERB::Util.html_escape(conversation.title.presence || 'Untitled')
    broadcast_replace_to conversation, target: "conversation-title-#{conversation.public_id}", html: title
    broadcast_replace_to conversation, target: 'conversation-drawer-title', html: title
  end

  def subscribed
    @conversation = current_user&.conversations&.find_by(public_id: params[:public_id])

    if @conversation
      @stream_name = self.class.send(:stream_name_from, @conversation)
      stream_from @stream_name
      Rails.logger.info "ConversationChannel subscribed to #{@stream_name}"
    else
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "ConversationChannel unsubscribed from #{@stream_name}"
  end
end
