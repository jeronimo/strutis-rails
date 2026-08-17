# frozen_string_literal: true

module Devise
  module Admins
    class PasswordsController < Devise::PasswordsController
      layout 'admins/application'
    end
  end
end
