require 'rails_helper'

RSpec.describe ConversationTitleJob, type: :job do
  let(:user) { User.create!(email: 'title-job-user@example.com', password: 'password123') }
  let(:content) { 'A' * 100 }
  let(:conversation) { user.conversations.create!(model: 'test-model', title: content[0, 60]) }

  before do
    conversation.messages.create!(role: 'user', content: content)
    allow(ConversationChannel).to receive(:broadcast_title)
  end

  it 'does nothing when the conversation does not exist' do
    allow(ConversationTitleService).to receive(:perform)

    described_class.perform_now(999_999)

    expect(ConversationTitleService).not_to have_received(:perform)
  end

  it 'does nothing when title generation is not needed' do
    conversation.update!(title: 'Different title')
    allow(ConversationTitleService).to receive(:perform)

    described_class.perform_now(conversation.id)

    expect(ConversationTitleService).not_to have_received(:perform)
  end

  it 'calls the service with the conversation and its openai service' do
    allow(ConversationTitleService).to receive(:perform).and_return('')

    described_class.perform_now(conversation.id)

    expect(ConversationTitleService).to have_received(:perform).with(conversation, an_instance_of(OpenaiService))
  end

  it 'broadcasts the title when the service returns one' do
    allow(ConversationTitleService).to receive(:perform).and_return('Generated title')

    described_class.perform_now(conversation.id)

    expect(ConversationChannel).to have_received(:broadcast_title).with(conversation)
  end

  it 'does not broadcast when the service returns a blank title' do
    allow(ConversationTitleService).to receive(:perform).and_return('')

    described_class.perform_now(conversation.id)

    expect(ConversationChannel).not_to have_received(:broadcast_title)
  end

  it 're-raises errors after capturing them' do
    allow(ConversationTitleService).to receive(:perform).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(conversation.id) }.to raise_error(StandardError, 'boom')
  end
end
