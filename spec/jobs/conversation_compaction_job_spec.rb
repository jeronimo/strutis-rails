require 'rails_helper'

RSpec.describe ConversationCompactionJob, type: :job do
  let(:user) { User.create!(email: 'compaction-job-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  before do
    allow(ConversationChannel).to receive(:broadcast_frame)
  end

  it 'does nothing when the conversation does not exist' do
    allow(ConversationCompactionService).to receive(:perform)

    described_class.perform_now(999_999)

    expect(ConversationCompactionService).not_to have_received(:perform)
  end

  it 'broadcasts the frame when compaction succeeds' do
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(ConversationCompactionService).to have_received(:perform).with(conversation, an_instance_of(OpenaiService))
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
end
