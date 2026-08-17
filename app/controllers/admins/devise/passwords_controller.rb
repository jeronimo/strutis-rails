module Admins
  module Devise
    class PasswordsController < ::Devise::PasswordsController
      self.view_paths = [ Rails.root.join('app', 'views') ]
      layout 'admins/devise'
    end
  end
end
