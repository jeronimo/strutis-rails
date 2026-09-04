require 'rails_helper'

RSpec.describe Conversation, type: :model do
  let(:user) { User.create!(email: 'conversation-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  describe '#context_usage_percent' do
    it 'returns nil without a context window' do
      allow(OpenaiService).to receive(:context_length).with('test-model').and_return(nil)
      expect(conversation.context_usage_percent).to be_nil
    end

    it 'calculates percentage from context window' do
      conversation.update!(context_tokens: 80)
      allow(OpenaiService).to receive(:context_length).with('test-model').and_return(1000)
      expect(conversation.context_usage_percent).to eq(8)
    end
  end

  describe '#compaction_needed?' do
    it 'is false at the threshold' do
      conversation.update!(context_tokens: 80)
      allow(OpenaiService).to receive(:context_length).with('test-model').and_return(100)
      expect(conversation.compaction_needed?).to be false
    end

    it 'is true above the threshold' do
      conversation.update!(context_tokens: 81)
      allow(OpenaiService).to receive(:context_length).with('test-model').and_return(100)
      expect(conversation.compaction_needed?).to be true
    end
  end

  describe '#prompt_messages' do
    it 'keeps system messages first, includes summary, and excludes compacted and compaction messages' do
      conversation.update!(summary: 'summary')
      conversation.messages.create!(role: 'system', content: 'rules')
      old_user = conversation.messages.create!(role: 'user', content: 'old')
      old_assistant = conversation.messages.create!(role: 'assistant', content: 'old reply')
      conversation.messages.create!(role: 'compaction', content: 'compaction event')
      conversation.messages.create!(role: 'user', content: 'new')
      [ old_user, old_assistant ].each { |message| message.update!(compacted_at: Time.current) }

      expect(conversation.prompt_messages).to eq([
        { role: 'system', content: 'rules' },
        { role: 'system', content: 'summary' },
        { role: 'user', content: 'new' }
      ])
    end
  end
end
