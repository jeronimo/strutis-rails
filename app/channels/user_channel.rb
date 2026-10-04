class UserChannel < ApplicationCable::Channel
  extend Turbo::Streams::Broadcasts
  extend Turbo::Streams::StreamName
  include Turbo::Streams::StreamName::ClassMethods

  def self.broadcast_unread(conversation, unread:)
    broadcast_replace_to conversation.user,
      target: "conversation-unread-#{conversation.public_id}",
      partial: 'conversations/unread_badge',
      locals: { conversation:, unread: }
  end

  def subscribed
    stream_from self.class.send(:stream_name_from, current_user)
  end
end
