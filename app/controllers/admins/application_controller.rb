# frozen_string_literal: true

module Admins
  class ApplicationController < ActionController::Base
    before_action :authenticate_admin!
    layout 'admins/application'
  end
end
