# frozen_string_literal: true

module Devise
  module Admin
    class PasswordsController < Devise::PasswordsController
      layout 'admin/application'
    end
  end
end
