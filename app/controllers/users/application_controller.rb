module Users
  class ApplicationController < ApplicationController
    layout 'user'
    before_action :authenticate_user!
    before_action :load_conversations
  end
end
