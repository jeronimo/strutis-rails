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

  describe '#compactable?' do
    it 'is false when there is nothing before the last user message' do
      conversation.messages.create!(role: 'user', content: 'only')
      expect(conversation.compactable?).to be false
    end

    it 'is true when compactable messages exist before the last user message' do
      conversation.messages.create!(role: 'user', content: 'old')
      conversation.messages.create!(role: 'assistant', content: 'old reply')
      conversation.messages.create!(role: 'user', content: 'new')
      expect(conversation.compactable?).to be true
    end
  end

  describe '#chat_template_kwargs' do
    it 'returns nil when the model has no chat_template_kwargs' do
      allow(OpenaiService).to receive(:chat_template_kwargs).with('test-model').and_return(nil)
      expect(conversation.chat_template_kwargs).to be_nil
    end

    it 'merges enable_thinking and keeps other defaults' do
      allow(OpenaiService).to receive(:chat_template_kwargs).with('test-model')
        .and_return({ enable_thinking: true, reasoning_effort: 'medium', preserve_thinking: true })
      conversation.update!(thinking: false)
      expect(conversation.chat_template_kwargs).to eq({ enable_thinking: false, reasoning_effort: 'medium', preserve_thinking: true })
    end

    it 'merges reasoning_effort only when set' do
      allow(OpenaiService).to receive(:chat_template_kwargs).with('test-model')
        .and_return({ enable_thinking: true, reasoning_effort: 'medium' })
      conversation.update!(thinking: true)
      expect(conversation.chat_template_kwargs).to eq({ enable_thinking: true, reasoning_effort: 'medium' })
      conversation.update!(reasoning_effort: 'xhigh')
      expect(conversation.chat_template_kwargs).to eq({ enable_thinking: true, reasoning_effort: 'xhigh' })
    end
  end

  describe '#prompt_messages' do
    before do
      Prompt.create!(key: 'digest', user_id: nil, content: Prompt::DIGEST_DEFAULT)
    end

    it 'keeps system messages first, wraps the summary in a compaction marker, and excludes compacted and compaction messages' do
      conversation.update!(summary: 'summary')
      conversation.messages.create!(role: 'system', content: 'rules')
      old_user = conversation.messages.create!(role: 'user', content: 'old')
      old_assistant = conversation.messages.create!(role: 'assistant', content: 'old reply')
      conversation.messages.create!(role: 'compaction', content: 'compaction event')
      conversation.messages.create!(role: 'user', content: 'new')
      [ old_user, old_assistant ].each { |message| message.update!(compacted_at: Time.current) }

      entries = conversation.prompt_messages
      expect(entries.size).to eq(3)
      expect(entries[0]).to eq({ role: 'system', content: 'rules' })
      expect(entries[1][:role]).to eq('user')
      expect(entries[1][:content]).to include('summary')
      expect(entries[1][:content]).to include('lossy')
      expect(entries[2]).to eq({ role: 'user', content: 'new' })
    end
  end
end
