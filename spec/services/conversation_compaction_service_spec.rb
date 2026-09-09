require 'rails_helper'

RSpec.describe ConversationCompactionService do
  let(:user) { User.create!(email: 'compaction-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  before do
    Prompt.create!(key: 'compacting', user_id: nil, content: Prompt::COMPACTING_DEFAULT)
  end

  it 'compacts old non-system messages and keeps system messages and the latest user turn' do
    system_message = conversation.messages.create!(role: 'system', content: 'rules')
    old_user = conversation.messages.create!(role: 'user', content: 'old')
    old_assistant = conversation.messages.create!(role: 'assistant', content: 'old reply')
    new_user = conversation.messages.create!(role: 'user', content: 'new')
    allow(OpenaiService).to receive(:completion).and_return(content: 'summary')

    expect(described_class.perform(conversation)).to be true

    expect(system_message.reload.compacted_at).to be_nil
    expect(old_user.reload.compacted_at).to be_present
    expect(old_assistant.reload.compacted_at).to be_present
    expect(new_user.reload.compacted_at).to be_nil
    expect(conversation.reload.summary).to eq('summary')

    compaction_message = conversation.messages.where(role: 'compaction').last
    expect(compaction_message).to be_present
    expect(compaction_message.content).to eq('summary')
    expect(compaction_message.compacted_at).to be_present
    expect(compaction_message.latency_ms).to be_present
  end

  it 'returns false when there is nothing to compact' do
    conversation.messages.create!(role: 'user', content: 'only')
    allow(OpenaiService).to receive(:completion)

    expect(described_class.perform(conversation)).to be false
    expect(OpenaiService).not_to have_received(:completion)
    expect(conversation.messages.where(role: 'compaction')).to be_empty
  end

  it 'raises when the summary is empty' do
    conversation.messages.create!(role: 'user', content: 'old')
    conversation.messages.create!(role: 'assistant', content: 'old reply')
    conversation.messages.create!(role: 'user', content: 'new')
    allow(OpenaiService).to receive(:completion).and_return(content: '')

    expect { described_class.perform(conversation) }.to raise_error(RuntimeError, 'Compaction summary is empty')
    expect(conversation.messages.where(role: 'compaction')).to be_empty
  end

  it 'includes tool results in the single summary prompt' do
    conversation.messages.create!(role: 'user', content: 'old')
    conversation.messages.create!(role: 'assistant', content: 'old reply')
    conversation.messages.create!(role: 'tool', content: '{"url":"x","content":"InSense 1620 EUR, 4.8 stars"}')
    conversation.messages.create!(role: 'user', content: 'new')

    prompts = []
    allow(OpenaiService).to receive(:completion) do |prompt, _model, _conversation_id, **_options|
      prompts << prompt
      { content: 'summary' }
    end

    expect(described_class.perform(conversation)).to be true

    expect(prompts.size).to eq(1)
    expect(prompts.first.map { |entry| entry[:content] }.join).to include('InSense 1620 EUR, 4.8 stars')
    expect(conversation.reload.summary).to eq('summary')
  end

  it 'preserves data and forbids answering questions in the conversation' do
    conversation.messages.create!(role: 'user', content: 'old')
    conversation.messages.create!(role: 'assistant', content: 'old reply')
    conversation.messages.create!(role: 'user', content: 'new')

    prompts = []
    allow(OpenaiService).to receive(:completion) do |prompt, _model, _conversation_id, **_options|
      prompts << prompt
      { content: 'summary' }
    end

    described_class.perform(conversation)

    instruction = prompts.first.first[:content]
    expect(instruction).to include('STRICT DATA PRESERVATION RULES')
    expect(instruction).to include('answer any question in it')
  end
end
