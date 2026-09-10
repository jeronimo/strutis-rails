require 'rails_helper'

RSpec.describe ConversationCompletionJob, type: :job do
  let(:user) { User.create!(email: 'completion-job-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model', context_tokens: 81) }

  before do
    allow(OpenaiService).to receive(:context_length).with('test-model').and_return(100)
    allow(OpenaiService).to receive(:chat_template_kwargs).and_return(nil)
    allow(OpenaiService).to receive(:tools).and_return([])
    allow(ConversationChannel).to receive(:broadcast_frame)
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

    expect(ConversationCompactionService).to have_received(:perform).with(a_kind_of(Conversation))
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

  it 'persists last_error, drops the partial message, and broadcasts the error when completion fails' do
    conversation.update!(context_tokens: 0)
    conversation.messages.create!(role: 'user', content: 'new')
    allow(OpenaiService).to receive(:completion) do |_messages, _model, _conversation_id, **_options, &block|
      block&.call('partial')
      raise OpenaiService::Error, 'boom'
    end

    expect { described_class.perform_now(conversation.id) }.to raise_error(OpenaiService::Error)

    expect(conversation.reload.last_error).to eq('Completion failed. Please try again.')
    expect(conversation.messages.where(role: 'assistant')).to be_empty
    expect(ConversationChannel).to have_received(:broadcast_frame).at_least(:once)
  end

  it 'records per-turn latency_ms and inference_ms on intermediate assistant messages and the accumulated total on the final one' do
    conversation.update!(context_tokens: 0)
    conversation.messages.create!(role: 'user', content: 'new')
    tool_call = { id: 'call_1', type: 'function', function: { name: 'search', arguments: '{"query":"x"}' } }
    calls = 0
    allow(OpenaiService).to receive(:completion) do |_messages, _model, _conversation_id, **_options, &block|
      calls += 1
      if calls == 1
        { content: '', reasoning: 'thinking', tool_calls: [ tool_call ], latency_ms: 1200, inference_ms: 1100, prompt_tokens: 10, completion_tokens: 5, reasoning_tokens: 4 }
      else
        block&.call('done')
        { content: 'done', tool_calls: [], latency_ms: 300, inference_ms: 200, prompt_tokens: 12, completion_tokens: 3, reasoning_tokens: 0 }
      end
    end
    allow(OpenaiService).to receive(:execute_tool).and_return('{"result":"ok"}')

    described_class.perform_now(conversation.id)

    assistant_messages = conversation.messages.reload.where(role: 'assistant')
    expect(assistant_messages.count).to eq(2)
    expect(assistant_messages.first.inference_ms).to eq(1100)
    expect(assistant_messages.first.latency_ms).to eq(1200)
    expect(assistant_messages.last.inference_ms).to eq(1300)
    expect(assistant_messages.last.latency_ms).to eq(1500)
  end

  it 'keeps the last known context_tokens when usage is missing from the stream' do
    conversation.update!(context_tokens: 50)
    conversation.messages.create!(role: 'user', content: 'new')
    allow(OpenaiService).to receive(:completion) do |_messages, _model, _conversation_id, **_options, &block|
      block&.call('hello')
      { content: 'hello', tool_calls: [], latency_ms: 1, inference_ms: 1 }
    end

    described_class.perform_now(conversation.id)

    expect(conversation.reload.context_tokens).to eq(50)
  end
end
