class ConversationWatchdogJob < ApplicationJob
  def perform
    Conversation.where.not(running_at: nil).where(running_at: ..Conversation::COMPLETION_STALE_AFTER.ago).find_each do |conversation|
      conversation.mark_completion_idle!
      ConversationChannel.broadcast_frame(conversation, show_progress: false)
    end
  end
end
