require 'rails_helper'

RSpec.describe ConversationTitleService do
  let(:user) { User.create!(email: 'title-service-user@example.com', password: 'password123') }
  let(:content) { 'A' * 100 }
  let(:conversation) { user.conversations.create!(model: 'test-model', title: content[0, 60]) }
  let(:openai) { instance_double(OpenaiService) }

  before do
    conversation.messages.create!(role: 'user', content: content)
  end

  it 'generates a title, strips it, and updates the conversation' do
    allow(openai).to receive(:completion).and_return(content: '  Generated Title  ')

    expect(described_class.perform(conversation, openai)).to eq('Generated Title')
    expect(conversation.reload.title).to eq('Generated Title')
  end

  it 'returns nil and does not update when the title is blank' do
    allow(openai).to receive(:completion).and_return(content: '   ')

    expect(described_class.perform(conversation, openai)).to be_nil
    expect(conversation.reload.title).to eq(content[0, 60])
  end

  it 'builds the prompt from the title template and the conversation messages' do
    prompts = []
    allow(openai).to receive(:completion) do |prompt, _model, **_options|
      prompts << prompt
      { content: 'Title' }
    end

    described_class.perform(conversation, openai)

    expect(prompts.size).to eq(1)
    expect(prompts.first[0]).to eq({ role: 'system', content: Prompt::TITLE_DEFAULT })
    expect(prompts.first[1][:content]).to include(content)
  end
end
