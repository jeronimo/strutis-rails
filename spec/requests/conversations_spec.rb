require 'rails_helper'

RSpec.describe 'Conversations', type: :request do
  let(:user) { User.create!(email: 'conversation-user@example.com', password: 'password123') }

  before do
    allow(OpenaiService).to receive(:models).and_return([ { id: 'test-model', context_length: 1000 } ])
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
      allow(OpenaiService).to receive(:stt_model).and_return({ id: 'stt-model' })
      service_instance = instance_double(OpenaiService, transcribe: 'hello world')
      allow(OpenaiService).to receive(:new).and_return(service_instance)

      post '/conversations/transcribe', params: { file: fixture_file_upload('audio.webm', 'audio/webm') }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq({ 'text' => 'hello world' })
    end

    it 'requires an audio file' do
      allow(OpenaiService).to receive(:stt_model).and_return({ id: 'stt-model' })

      post '/conversations/transcribe'

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
