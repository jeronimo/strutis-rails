require 'rails_helper'

RSpec.describe ConversationCompactionService do
  let(:user) { User.create!(email: 'compaction-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  it 'compacts old non-system messages and keeps system messages and the latest user turn' do
    system_message = conversation.messages.create!(role: 'system', content: 'rules')
    old_user = conversation.messages.create!(role: 'user', content: 'old')
    old_assistant = conversation.messages.create!(role: 'assistant', content: 'old reply')
    new_user = conversation.messages.create!(role: 'user', content: 'new')
    allow(OpenaiService).to receive(:tools).and_return([])
    allow(OpenaiService).to receive(:completion).and_return(content: 'summary', prompt_tokens: 10)

    expect(described_class.perform(conversation)).to be true

    expect(system_message.reload.compacted_at).to be_nil
    expect(old_user.reload.compacted_at).to be_present
    expect(old_assistant.reload.compacted_at).to be_present
    expect(new_user.reload.compacted_at).to be_nil
    expect(conversation.reload.summary).to eq('summary')
    expect(conversation.context_tokens).to eq(10)

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

  it 'skips context measurement when refresh_tokens is false' do
    conversation.messages.create!(role: 'user', content: 'old')
    conversation.messages.create!(role: 'assistant', content: 'old reply')
    conversation.messages.create!(role: 'user', content: 'new')
    allow(OpenaiService).to receive(:completion).and_return(content: 'summary', prompt_tokens: 10)

    expect(described_class.perform(conversation, refresh_tokens: false)).to be true
    expect(OpenaiService).to have_received(:completion).once
    expect(conversation.reload.context_tokens).to eq(0)
    expect(conversation.messages.where(role: 'compaction').count).to eq(1)
  end
end
