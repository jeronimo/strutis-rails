require 'rails_helper'

RSpec.describe ConversationCompactionJob, type: :job do
  let(:user) { User.create!(email: 'compaction-job-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  before do
    allow(ConversationChannel).to receive(:broadcast_frame)
    allow(ConversationChannel).to receive(:broadcast_error)
    allow(UserChannel).to receive(:broadcast_unread)
    allow(UserChannel).to receive(:broadcast_progress)
    allow(CompletionMonitor).to receive(:start).and_return(instance_double(CompletionMonitor, stop_requested?: false, stop: nil))
  end

  it 'broadcasts the busy indicator on start and finish' do
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(UserChannel).to have_received(:broadcast_progress).with(conversation, active: true).ordered
    expect(UserChannel).to have_received(:broadcast_progress).with(conversation, active: false).ordered
  end

  it 'does nothing when the conversation does not exist' do
    allow(ConversationCompactionService).to receive(:perform)

    described_class.perform_now(999_999)

    expect(ConversationCompactionService).not_to have_received(:perform)
  end

  it 'broadcasts the frame when compaction succeeds' do
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(ConversationCompactionService).to have_received(:perform).with(conversation, an_instance_of(OpenAiService), on_retry: anything)
    expect(ConversationChannel).to have_received(:broadcast_frame).with(conversation, show_progress: false)
    expect(conversation.reload.last_error).to be_nil
  end

  it 'sets last_error and broadcasts when compaction returns false' do
    allow(ConversationCompactionService).to receive(:perform).and_return(false)

    described_class.perform_now(conversation.id)

    expect(conversation.reload.last_error).to eq('Compaction failed.')
    expect(ConversationChannel).to have_received(:broadcast_frame).with(conversation, show_progress: false)
  end

  it 'sets last_error, broadcasts, and re-raises when compaction raises' do
    allow(ConversationCompactionService).to receive(:perform).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(conversation.id) }.to raise_error(StandardError, 'boom')
    expect(conversation.reload.last_error).to eq('Compaction failed.')
    expect(ConversationChannel).to have_received(:broadcast_frame).with(conversation, show_progress: false)
  end

  it 'marks the conversation unread after a successful compaction' do
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(conversation.reload.unread).to be true
    expect(UserChannel).to have_received(:broadcast_unread).with(conversation, unread: true)
  end

  it 'marks the conversation unread after a failed compaction' do
    allow(ConversationCompactionService).to receive(:perform).and_return(false)

    described_class.perform_now(conversation.id)

    expect(conversation.reload.unread).to be true
    expect(UserChannel).to have_received(:broadcast_unread).with(conversation, unread: true)
  end

  it 'marks the conversation alive while compacting and idle after finishing' do
    alive_during = nil
    allow(ConversationCompactionService).to receive(:perform) do |conv, *_args|
      alive_during = Conversation.find(conversation.id).completion_alive?
      true
    end

    described_class.perform_now(conversation.id)

    expect(alive_during).to be true
    expect(conversation.reload.completion_alive?).to be false
  end

  it 'enqueues a completion when a message was queued during compaction' do
    allow(ConversationCompactionService).to receive(:perform).and_return(true)
    conversation.messages.create!(role: 'user', content: 'queued while compacting', queued: true)

    expect { described_class.perform_now(conversation.id) }.to have_enqueued_job(ConversationCompletionJob).with(conversation.id)

    expect(conversation.messages.reload.where(queued: true).count).to eq(0)
    expect(conversation.messages.where(content: 'queued while compacting', queued: false).count).to eq(1)
    expect(UserChannel).not_to have_received(:broadcast_progress).with(conversation, active: false)
  end

  it 'broadcasts the inactive progress when nothing was queued' do
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(UserChannel).to have_received(:broadcast_progress).with(conversation, active: false)
  end
end
