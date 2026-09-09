require 'rails_helper'

RSpec.describe 'Conversations', type: :request do
  let(:user) { User.create!(email: 'conversation-user@example.com', password: 'password123') }

  before do
    allow(OpenaiService).to receive(:models).and_return([ { id: 'test-model', context_length: 1000 } ])
    get '/users/sign_in'
    post '/users/sign_in', params: { user: { email: user.email, password: 'password123' } }
  end

  describe 'POST /conversations' do
    it 'creates the conversation with a system message from the global default' do
      Prompt.create!(key: 'system', user_id: nil, content: 'global system prompt')
      post '/conversations', params: { model: 'test-model', message: 'hello' }

      conversation = user.conversations.last
      expect(conversation).to be_present
      expect(conversation.messages.where(role: 'system').pluck(:content)).to eq([ 'global system prompt' ])
    end

    it 'uses the user system prompt when present' do
      Prompt.create!(key: 'system', user: user, content: 'my rules')
      post '/conversations', params: { model: 'test-model', message: 'hello' }

      conversation = user.conversations.last
      expect(conversation.messages.where(role: 'system').pluck(:content)).to eq([ 'my rules' ])
    end
  end
end
