require 'rails_helper'

RSpec.describe 'Admins::Prompts', type: :request do
  let(:admin) { Admin.create!(email: 'admin@example.com', password: 'password123') }

  before do
    get '/admin/sign_in'
    post '/admin/sign_in', params: { admin: { email: admin.email, password: 'password123' } }
  end

  describe 'GET /admin/prompts' do
    it 'lists the global prompts' do
      Prompt.create!(key: 'system', user_id: nil, content: 'global content')
      get '/admin/prompts'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('system')
    end
  end

  describe 'POST /admin/prompts' do
    it 'creates a new global prompt' do
      post '/admin/prompts', params: { prompt: { key: 'custom', content: 'custom content' } }
      expect(Prompt.where(key: 'custom', user_id: nil).count).to eq(1)
    end
  end

  describe 'PATCH /admin/prompts/:id' do
    it 'updates the global prompt' do
      prompt = Prompt.create!(key: 'system', user_id: nil, content: 'old content')
      patch "/admin/prompts/#{prompt.id}", params: { prompt: { content: 'new content' } }
      expect(prompt.reload.content).to eq('new content')
    end
  end

  describe 'DELETE /admin/prompts/:id' do
    it 'destroys the global prompt' do
      prompt = Prompt.create!(key: 'system', user_id: nil, content: 'content')
      delete "/admin/prompts/#{prompt.id}"
      expect(Prompt.where(id: prompt.id).count).to eq(0)
    end
  end
end
