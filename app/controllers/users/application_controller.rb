module Users
  class ApplicationController < ApplicationController
    layout 'user'
    before_action :authenticate_user!
  end
end
