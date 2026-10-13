require 'rails_helper'

RSpec.describe ConversationWatchdogJob, type: :job do
  let(:user) { User.create!(email: 'watchdog-user@example.com', password: 'password123') }

  before { allow(ConversationChannel).to receive(:broadcast_frame) }

  it 'clears stale completion state and rebroadcasts the frame' do
    conversation = user.conversations.create!(model: 'test-model', running_at: 2.minutes.ago)

    described_class.perform_now

    expect(conversation.reload.running_at).to be_nil
    expect(ConversationChannel).to have_received(:broadcast_frame).with(conversation, show_progress: false)
  end

  it 'leaves live completions alone' do
    conversation = user.conversations.create!(model: 'test-model', running_at: 5.seconds.ago)

    described_class.perform_now

    expect(conversation.reload.running_at).to be_present
    expect(ConversationChannel).not_to have_received(:broadcast_frame)
  end
end
