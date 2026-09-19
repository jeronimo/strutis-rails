Rails.application.routes.draw do
  devise_for :users, path_names: { sign_in: 'sign-in' }, case_insensitive_keys: [ :email ], strip_whitespace_keys: [ :email ],
    skip: %i[registrations],
    controllers: { sessions: 'users/devise/sessions', passwords: 'users/devise/passwords', unlocks: 'users/devise/unlocks' }

  get 'users/sign-in/verify', to: 'users/two_factors#new', as: :user_sign_in_verify
  post 'users/sign-in/verify', to: 'users/two_factors#create'
  post 'users/sign-in/token', to: 'users/token_sessions#create', as: :user_token_sign_in

  devise_scope :user do
    get 'users/sign-in/email', to: 'users/devise/sessions#email', as: :user_email_sign_in
  end
  devise_for :admins, path: 'admin',
    controllers: {
      sessions: 'admins/devise/sessions',
      passwords: 'admins/devise/passwords'
    },
    skip: %i[confirmations registrations unlocks omniauth_callbacks],
    sign_out_via: :delete

  namespace :admins, path: 'admin' do
    resources :users
    resources :prompts, only: [ :index, :new, :create, :edit, :update, :destroy ]
    get 'dashboard', to: 'dashboard#index'
    root 'dashboard#index'
  end

  namespace :users do
    resource :prompt, only: [ :edit, :update ]
    resource :profile, only: [ :edit, :update ]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  get 'latency' => 'latencies#show'

  resources :conversations, only: [ :index, :new, :create, :show, :update, :destroy ] do
    post 'stop', on: :member
    patch 'move', on: :member
  end

  resources :folders, only: [ :create, :update, :destroy ] do
    patch 'move', on: :member
    patch 'toggle', on: :member
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker

  root 'home#index'
end
