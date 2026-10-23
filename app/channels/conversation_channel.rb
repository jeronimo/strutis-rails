class ConversationChannel < ApplicationCable::Channel
  extend Turbo::Streams::Broadcasts
  extend Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  def self.broadcast_frame(conversation, show_progress:)
    broadcast_replace_to conversation,
      target: "messages-#{conversation.public_id}",
      partial: 'conversations/messages_frame',
      locals: { conversation:, messages: conversation.messages.with_attachments.reload, show_progress: }
  end

  def self.broadcast_message(conversation, message)
    broadcast_append_to conversation, target: "messages-list-#{conversation.public_id}",
      partial: 'conversations/message', locals: { message: }
  end

  def self.replace_message(conversation, message)
    broadcast_replace_to conversation, target: "message-#{message.id}",
      partial: 'conversations/message', locals: { message: }
  end

  def self.broadcast_progress(conversation, active:, retry_status: nil)
    broadcast_replace_to conversation, target: "conversation-progress-#{conversation.public_id}",
      partial: 'conversations/progress', locals: { conversation:, active:, retry_status: }
  end

  def self.broadcast_retry(conversation, attempt:, max:, wait:)
    broadcast_progress(conversation, active: true, retry_status: { attempt:, max:, wait: })
  end

  def self.broadcast_retry_clear(conversation)
    broadcast_progress(conversation, active: true)
  end

  def self.broadcast_context_usage(conversation)
    broadcast_replace_to conversation, target: "conversation-context-usage-#{conversation.public_id}",
      partial: 'conversations/context_usage', locals: { conversation: }
  end

  def self.broadcast_error(conversation)
    html = conversation.last_error.present? ? ApplicationController.render(partial: 'conversations/error', locals: { error: conversation.last_error }) : ''
    broadcast_replace_to conversation, target: "conversation-frame-error-#{conversation.public_id}", html: html
    broadcast_replace_to conversation, target: 'conversation-error', html: ''
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
      @conversation.mark_read!
      self.class.broadcast_progress(@conversation, active: @conversation.completion_alive?)
      Rails.logger.info "ConversationChannel subscribed to #{@stream_name}"
    else
      reject
    end
  end

  def read
    return unless @conversation
    @conversation.reload.mark_read!
  end

  def unsubscribed
    Rails.logger.info "ConversationChannel unsubscribed from #{@stream_name}"
  end
end
