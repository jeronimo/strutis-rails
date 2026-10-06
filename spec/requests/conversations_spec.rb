require 'rails_helper'

RSpec.describe 'Conversations', type: :request do
  let(:user) { User.create!(email: 'conversation-user@example.com', password: 'password123') }

  before do
    allow(ModelCatalog).to receive(:models).and_return([ { id: 'test-model', context_length: 1000, capabilities: { input: [ 'text' ] } } ])
    sign_in_user(user)
  end

  after { sign_out_user }

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

  describe 'POST /conversations/transcribe' do
    it 'returns the transcription text' do
      allow(OpenAiService).to receive(:stt_model).and_return({ id: 'stt-model' })
      service_instance = instance_double(OpenAiService, transcribe: 'hello world')
      allow(OpenAiService).to receive(:new).and_return(service_instance)

      post '/conversations/transcribe', params: { file: fixture_file_upload('audio.webm', 'audio/webm'), model: 'test-model' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ 'text' => 'hello world' })
    end

    it 'requires an audio file' do
      allow(OpenAiService).to receive(:stt_model).and_return({ id: 'stt-model' })

      post '/conversations/transcribe'

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /conversations/:id' do
    it 'marks the conversation read so the sidebar badge renders cleared' do
      conversation = user.conversations.create!(model: 'test-model', unread: true)

      get "/conversations/#{conversation.public_id}"

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.unread).to be false
    end

    it 'does not mark another user\'s shared conversation read' do
      other = User.create!(email: 'other-owner@example.com', password: 'password123')
      conversation = other.conversations.create!(model: 'test-model', unread: true)

      get "/conversations/#{conversation.public_id}"

      expect(conversation.reload.unread).to be true
    end
  end

  describe 'POST /conversations/:id/stop' do
    it 'records the stop request for the conversation found by public id' do
      conversation = user.conversations.create!(model: 'test-model')

      post "/conversations/#{conversation.public_id}/stop"

      expect(response).to have_http_status(:ok)
      expect(CompletionSignal.new(conversation.id).stopped?).to be true
    end
  end
end
