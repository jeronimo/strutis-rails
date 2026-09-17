class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes
  respond_to :html, :turbo_stream

  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [ :email, :password, :authentication_token ])
  end

  private

  def load_conversations
    if current_user
      @conversations = current_user.conversations.order(:position, :id).to_a
      @folders = current_user.folders.order(:position, :id).to_a
    else
      @conversations = []
      @folders = []
    end
  end
end
