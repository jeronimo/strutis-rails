class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  respond_to :html, :turbo_stream

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :load_conversations, if: :user_signed_in?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :email, :password, :password_confirmation, :authentication_token ])
    devise_parameter_sanitizer.permit(:sign_in, keys: [ :email, :password, :authentication_token ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :email, :password, :password_confirmation, :current_password, :authentication_token ])
  end

  private

  def load_conversations
    @conversations = current_user.conversations.order(created_at: :desc)
  end
end
