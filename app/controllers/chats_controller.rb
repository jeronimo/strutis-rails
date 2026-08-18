class ChatsController < ApplicationController
  layout 'user'
  before_action :authenticate_user!

  def new
  end
end
