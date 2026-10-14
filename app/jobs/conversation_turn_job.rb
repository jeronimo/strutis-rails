class ConversationTurnJob < ApplicationJob
  private

  def with_turn(conversation)
    conversation.update_column(:last_error, nil)
    ConversationChannel.broadcast_error(conversation)
    conversation.mark_completion_running!
    @monitor = CompletionMonitor.start(conversation)
    UserChannel.broadcast_progress(conversation, active: true)
    yield
  ensure
    @monitor&.stop
    conversation.mark_completion_idle!
  end

  def drain_queued_messages
    queued = @conversation.messages.where(role: 'user', queued: true)
    return false unless queued.exists?

    queued.find_each do |msg|
      blobs = msg.attachments.map(&:blob)
      content, model = msg.content, msg.model
      msg.destroy!
      @conversation.messages.create!(role: 'user', content: content, model: model).attachments.attach(blobs)
    end
    ConversationChannel.broadcast_frame(@conversation, show_progress: true)
    true
  end
end
