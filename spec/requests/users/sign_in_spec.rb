require 'rails_helper'

RSpec.describe 'User sign-in', type: :request do
  let(:user) { User.create!(email: 'sign-in-user@example.com', password: 'password123') }

  describe 'POST /users/sign-in' do
    it 'sends a two-factor code and redirects to verify for valid credentials' do
      perform_enqueued_jobs do
        post '/users/sign-in', params: { user: { email: user.email, password: 'password123' } }
      end

      expect(response).to redirect_to('/users/sign-in/verify')
      expect(last_email_code).to be_present
    end

    it 'sends a two-factor code for a valid authentication token' do
      post '/users/sign-in/token', params: { user: { authentication_token: user.authentication_token } }
      expect(response).to redirect_to('/users/sign-in/verify')
    end

    it 'renders the email form with an error for invalid credentials' do
      post '/users/sign-in', params: { user: { email: user.email, password: 'wrong-password' } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /users/sign-in/email' do
    it 'renders the email form with a reset password link' do
      get '/users/sign-in/email'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('user[email]')
      expect(response.body).to include('Forgot your password?')
    end
  end

  describe 'GET /users/sign-in/verify' do
    it 'redirects to email sign-in without a pending user' do
      get '/users/sign-in/verify'
      expect(response).to redirect_to('/users/sign-in/email')
    end

    it 'shows the code form for a pending user' do
      post '/users/sign-in', params: { user: { email: user.email, password: 'password123' } }
      get '/users/sign-in/verify'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.email)
    end
  end

  describe 'POST /users/sign-in/verify' do
    it 'signs in with a valid code' do
      perform_enqueued_jobs do
        post '/users/sign-in', params: { user: { email: user.email, password: 'password123' } }
      end
      post '/users/sign-in/verify', params: { code: last_email_code }

      expect(response).to redirect_to('/conversations/new')
    end

    it 'rejects an invalid code' do
      perform_enqueued_jobs do
        post '/users/sign-in', params: { user: { email: user.email, password: 'password123' } }
      end
      code = format('%06d', (last_email_code.to_i + 1) % 1_000_000)
      post '/users/sign-in/verify', params: { code: }

      expect(response).to have_http_status(:ok)
    end

    it 'sends a new code on resend' do
      perform_enqueued_jobs do
        post '/users/sign-in', params: { user: { email: user.email, password: 'password123' } }
      end
      perform_enqueued_jobs do
        post '/users/sign-in/verify', params: { resend: true }
      end

      expect(response).to redirect_to('/users/sign-in/verify')
      expect(user.reload.two_factor_code_pending?).to be(true)
    end
  end
end
