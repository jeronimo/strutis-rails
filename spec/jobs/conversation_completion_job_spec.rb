require 'rails_helper'

RSpec.describe ConversationCompletionJob, type: :job do
  let(:user) { User.create!(email: 'completion-job-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model', context_tokens: 81) }

  before do
    allow(OpenaiService).to receive(:context_length).with('test-model').and_return(100)
    allow(OpenaiService).to receive(:tools).and_return([])
    allow(ConversationChannel).to receive(:broadcast_frame)
    allow(ConversationChannel).to receive(:broadcast_replace_to)
    allow(OpenaiService).to receive(:completion) do |_messages, _model, _conversation_id, **_options, &block|
      block&.call('hello')
      { content: 'hello', tool_calls: [], latency_ms: 1, inference_ms: 1, prompt_tokens: 10, completion_tokens: 2, reasoning_tokens: 0 }
    end
  end

  it 'compacts automatically before completion when context usage is above the threshold' do
    conversation.messages.create!(role: 'user', content: 'old')
    conversation.messages.create!(role: 'assistant', content: 'old reply')
    conversation.messages.create!(role: 'user', content: 'new')
    allow(ConversationCompactionService).to receive(:perform).and_return(true)

    described_class.perform_now(conversation.id)

    expect(ConversationCompactionService).to have_received(:perform).with(a_kind_of(Conversation), hash_including(refresh_tokens: false))
    expect(conversation.messages.reload.where(role: 'assistant').last&.content).to eq('hello')
  end

  it 'does not compact before completion when context usage is at the threshold' do
    conversation.update!(context_tokens: 80)
    conversation.messages.create!(role: 'user', content: 'new')
    allow(ConversationCompactionService).to receive(:perform)

    described_class.perform_now(conversation.id)

    expect(ConversationCompactionService).not_to have_received(:perform)
    expect(conversation.messages.reload.where(role: 'assistant').last&.content).to eq('hello')
  end
end
