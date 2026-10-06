class ConversationChannel < ApplicationCable::Channel
  extend Turbo::Streams::Broadcasts
  extend Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  def self.broadcast_frame(conversation, show_progress:)
    broadcast_replace_to conversation,
      target: "messages-#{conversation.public_id}",
      partial: 'conversations/messages_frame',
      locals: { conversation:, messages: conversation.messages.includes(attachments_attachments: :blob).reload, show_progress: }
  end

  def self.broadcast_title(conversation)
    title = ERB::Util.html_escape(conversation.title.presence || 'Untitled')
    broadcast_replace_to conversation, target: "conversation-title-#{conversation.public_id}", html: title
    broadcast_replace_to conversation, target: 'conversation-drawer-title', html: title
  end

  def self.broadcast_retry(conversation, attempt:, max:, wait:)
    broadcast_replace_to conversation,
      target: "conversation-progress-status-#{conversation.public_id}",
      partial: 'conversations/retry_status',
      locals: { conversation:, attempt:, max:, wait: }
  end

  def subscribed
    @conversation = current_user&.conversations&.find_by(public_id: params[:public_id])

    if @conversation
      @stream_name = self.class.send(:stream_name_from, @conversation)
      stream_from @stream_name
      @presence_token = SecureRandom.hex(16)
      ConversationPresence.new(@conversation.id).start!(@presence_token)
      @conversation.mark_read!
      Rails.logger.info "ConversationChannel subscribed to #{@stream_name}"
    else
      reject
    end
  end

  def read
    @conversation&.reload&.mark_read!
  end

  def unsubscribed
    ConversationPresence.new(@conversation.id).finish!(@presence_token) if @conversation && @presence_token
    Rails.logger.info "ConversationChannel unsubscribed from #{@stream_name}"
  end
end
