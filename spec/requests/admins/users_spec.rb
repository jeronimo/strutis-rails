require 'rails_helper'

RSpec.describe 'Admins::Users', type: :request do
  let(:admin) { Admin.create!(email: 'admin@example.com', password: 'password123') }
  let(:user) { User.create!(email: 'user@example.com', password: 'password123') }

  before do
    get '/admin/sign_in'
    post '/admin/sign_in', params: { admin: { email: admin.email, password: 'password123' } }
  end

  describe 'GET /admin/users' do
    it 'shows per-user request and token totals' do
      conversation = user.conversations.create!(model: 'model-a')
      conversation.messages.create!(role: 'assistant', model: 'model-a', prompt_tokens: 100, completion_tokens: 50)
      conversation.messages.create!(role: 'assistant', model: 'model-a', prompt_tokens: 10, completion_tokens: 5)

      get '/admin/users'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.email)
      expect(response.body).to include('165')
    end
  end
end
