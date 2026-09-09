require 'rails_helper'

RSpec.describe 'Users::Prompts', type: :request do
  let(:user) { User.create!(email: 'user@example.com', password: 'password123') }

  before do
    get '/users/sign_in'
    post '/users/sign_in', params: { user: { email: user.email, password: 'password123' } }
  end

  describe 'GET /users/prompt/edit' do
    it 'shows the global default without a user prompt' do
      Prompt.create!(key: 'system', user_id: nil, content: 'global content')
      get '/users/prompt/edit'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('global content')
    end
  end

  describe 'PATCH /users/prompt' do
    it 'creates a user prompt when none exists' do
      patch '/users/prompt', params: { prompt: { content: 'my rules' } }
      expect(user.prompts.where(key: 'system').count).to eq(1)
      expect(user.prompts.where(key: 'system').first.content).to eq('my rules')
    end

    it 'updates the user prompt when it exists' do
      Prompt.create!(key: 'system', user: user, content: 'old rules')
      patch '/users/prompt', params: { prompt: { content: 'new rules' } }
      expect(user.prompts.where(key: 'system').first.reload.content).to eq('new rules')
    end
  end
end
