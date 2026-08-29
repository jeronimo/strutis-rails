class HomeController < ApplicationController
  before_action :redirect_if_signed_in, only: :index

  def index; end

  private

  def redirect_if_signed_in
    redirect_to new_conversation_path if user_signed_in?
  end
end
