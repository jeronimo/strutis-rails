Rails.application.routes.draw do
  devise_for :users, case_insensitive_keys: [ :email ], strip_whitespace_keys: [ :email ], authentication_keys: [ :email, :token ]
  devise_for :admins, path: 'admin',
    controllers: {
      sessions: 'devise/admins/sessions',
      passwords: 'devise/admins/passwords'
    },
    skip: %i[confirmations registrations unlocks omniauth_callbacks],
    sign_out_via: :delete

  namespace :admins, path: 'admin' do
    resources :users
    get 'dashboard', to: 'dashboard#index'
    root 'dashboard#index'
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  get 'latency' => 'latencies#show'

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root 'home#index'
end
