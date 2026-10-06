require 'rails_helper'

RSpec.describe ConversationCompactionJob, type: :job do
  let(:user) { User.create!(email: 'compaction-job-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  before do
    allow(ConversationChannel).to receive(:broadcast_frame)
    allow(ConversationPresence).to receive(:viewing?).and_return(false)
    allow(UserChannel).to receive(:broadcast_unread)
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

  it 'marks the conversation unread after a successful compaction when nobody is viewing' do
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(conversation.reload.unread).to be true
    expect(UserChannel).to have_received(:broadcast_unread).with(conversation, unread: true)
  end

  it 'marks the conversation unread after a failed compaction when nobody is viewing' do
    allow(ConversationCompactionService).to receive(:perform).and_return(false)

    described_class.perform_now(conversation.id)

    expect(conversation.reload.unread).to be true
    expect(UserChannel).to have_received(:broadcast_unread).with(conversation, unread: true)
  end

  it 'does not mark the conversation unread while it is being viewed' do
    allow(ConversationPresence).to receive(:viewing?).with(conversation.id).and_return(true)
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(conversation.reload.unread).to be false
    expect(UserChannel).not_to have_received(:broadcast_unread)
  end
end
