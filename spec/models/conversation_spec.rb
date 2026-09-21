require 'rails_helper'

RSpec.describe Conversation, type: :model do
  let(:user) { User.create!(email: 'conversation-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  describe '#openai_service' do
    it 'builds a service with the conversation and user public ids' do
      service = conversation.openai_service

      expect(service).to be_a(OpenaiService)
      expect(service.instance_variable_get(:@conversation_id)).to eq(conversation.public_id)
      expect(service.instance_variable_get(:@user_public_id)).to eq(user.public_id)
    end
  end

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
      allow(OpenaiService).to receive(:supports_image_input?).with('test-model').and_return(false)
      ActiveStorage::Current.url_options = { host: 'test.host' }
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

    it 'sends one image_url entry per image with the text only on the first entry for image-capable models' do
      allow(OpenaiService).to receive(:supports_image_input?).with('test-model').and_return(true)
      message = conversation.messages.create!(role: 'user', content: 'describe these')
      first = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('img1'), filename: 'one.png', content_type: 'image/png')
      second = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('img2'), filename: 'two.png', content_type: 'image/png')
      message.attachments.attach([ first, second ])

      entries = conversation.prompt_messages
      expect(entries.size).to eq(2)
      expect(entries[0][:content].map { |part| part[:type] }).to eq([ 'text', 'image_url' ])
      expect(entries[0][:content][0][:text]).to eq('describe these')
      expect(entries[0][:content][1][:image_url][:url]).to end_with('/one.png')
      expect(entries[1][:content].map { |part| part[:type] }).to eq([ 'image_url' ])
      expect(entries[1][:content][0][:image_url][:url]).to end_with('/two.png')
    end

    it 'keeps non-image attachments as text lines alongside image_url entries' do
      allow(OpenaiService).to receive(:supports_image_input?).with('test-model').and_return(true)
      message = conversation.messages.create!(role: 'user', content: 'check both')
      image = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('img'), filename: 'one.png', content_type: 'image/png')
      doc = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('pdf'), filename: 'doc.pdf', content_type: 'application/pdf')
      message.attachments.attach([ image, doc ])

      entries = conversation.prompt_messages
      expect(entries.size).to eq(1)
      expect(entries[0][:content].first[:text]).to include('doc.pdf')
      expect(entries[0][:content].last[:type]).to eq('image_url')
      expect(entries[0][:content].last[:image_url][:url]).to end_with('/one.png')
    end

    it 'keeps image attachments as text url lines for models without image input' do
      allow(OpenaiService).to receive(:supports_image_input?).with('test-model').and_return(false)
      message = conversation.messages.create!(role: 'user', content: 'describe these')
      image = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('img'), filename: 'one.png', content_type: 'image/png')
      message.attachments.attach(image)

      entries = conversation.prompt_messages
      expect(entries.size).to eq(1)
      expect(entries[0][:content]).to be_a(String)
      expect(entries[0][:content]).to include('one.png')
    end
  end

  describe '#tool_call_names' do
    it 'maps tool call ids to function names from assistant messages' do
      conversation.messages.create!(role: 'assistant', content: '', tool_calls: [ { id: 'c1', type: 'function', function: { name: 'web-search', arguments: '{"query":"q"}' } } ])
      expect(conversation.tool_call_names).to eq({ 'c1' => 'web-search' })
    end

    it 'returns an empty hash when there are no tool calls' do
      expect(conversation.tool_call_names).to eq({})
    end
  end

  describe 'soft delete' do
    it 'sets deleted_at, hides the conversation, and keeps its messages' do
      message = conversation.messages.create!(role: 'user', content: 'hello')
      conversation.destroy!

      expect(Conversation.exists?(conversation.id)).to be false
      expect(Conversation.with_deleted.find(conversation.id).deleted_at).to be_present
      expect(Message.exists?(message.id)).to be true
    end

    it 'excludes deleted conversations from the user association' do
      conversation.destroy
      expect(user.conversations.reload).to be_empty
    end

    it 'restores the conversation' do
      conversation.destroy
      Conversation.with_deleted.find(conversation.id).restore
      expect(Conversation.exists?(conversation.id)).to be true
    end
  end
end
