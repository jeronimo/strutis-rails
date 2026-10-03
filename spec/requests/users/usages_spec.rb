require 'rails_helper'

RSpec.describe 'Users::Usages', type: :request do
  let(:user) { User.create!(email: 'user@example.com', password: 'password123') }
  let(:other_user) { User.create!(email: 'other@example.com', password: 'password123') }

  before do
    allow(OpenaiService).to receive(:credentials).and_return({ host: 'localhost', port: 8080, key: 'test-key' })
    OpenaiService.instance_variable_set(:@models, nil)
    OpenaiService.instance_variable_set(:@models_fetched_at, nil)
    stub_request(:get, 'http://localhost:8080/v1/models')
      .to_return(status: 200, body: { data: [ { id: 'model-a', display_name: 'Model A' }, { id: 'model-b', display_name: 'Model B' } ] }.to_json)
    sign_in_user(user)
  end

  after { sign_out_user }

  describe 'GET /users/usage' do
    it 'shows per-model token usage' do
      conversation = user.conversations.create!(model: 'model-a')
      conversation.messages.create!(role: 'assistant', model: 'model-a', prompt_tokens: 100, completion_tokens: 50, reasoning_tokens: 10)
      conversation.messages.create!(role: 'assistant', model: 'model-a', prompt_tokens: 10, completion_tokens: 5)
      other_conversation = other_user.conversations.create!(model: 'model-b')
      other_conversation.messages.create!(role: 'assistant', model: 'model-b', prompt_tokens: 999, completion_tokens: 999)

      get '/users/usage'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Model A')
      expect(response.body).to include('110')
      expect(response.body).to include('165')
      expect(response.body).not_to include('Model B')
    end

    it 'shows an empty state without usage' do
      get '/users/usage'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No usage yet.')
    end
  end
end
