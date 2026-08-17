module Admins
  module Devise
    class SessionsController < ::Devise::SessionsController
      self.view_paths = [ Rails.root.join('app', 'views') ]
      layout 'admins/devise'

      protected

      def after_sign_out_path_for(_resource_or_scope)
        new_admin_session_path
      end

      def after_sign_in_path_for(_resource)
        admins_root_path
      end
    end
  end
end
