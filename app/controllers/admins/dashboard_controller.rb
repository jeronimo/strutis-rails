# frozen_string_literal: true

module Admins
  class DashboardController < Admins::ApplicationController
    def index
      @users = User.order(created_at: :desc).limit(5)
      @total_users = User.count
    end
  end
end
