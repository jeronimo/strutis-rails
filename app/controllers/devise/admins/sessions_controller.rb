# frozen_string_literal: true

module Devise
  module Admins
    class SessionsController < Devise::SessionsController
      layout 'admins/devise'

      protected

      def after_sign_in_path_for(resource_or_scope)
        admins_root_path
      end

      def after_sign_out_path_for(resource_or_scope)
        new_admin_session_path
      end
    end
  end
end
