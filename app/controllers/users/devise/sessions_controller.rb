module Users
  module Devise
    class SessionsController < ::Devise::SessionsController
      def create
        if params[resource_name].present? && params[resource_name][:authentication_token].present?
          self.resource = resource_class.find_by(authentication_token: params[:user][:authentication_token])
          return fail_authentication unless resource && resource.valid_for_authentication?

          set_flash_message!(:notice, :signed_in)
          sign_in(resource_name, resource)
          yield resource if block_given?
        else
          self.resource = warden.authenticate!(auth_options)
          set_flash_message!(:notice, :signed_in)
          sign_in(resource_name, resource)
          yield resource if block_given?
        end

        redirect_to after_sign_in_path_for(resource), status: :see_other
      end

      def new
        redirect_to user_signed_in? ? new_chat_path : root_path
      end

      protected

      def after_sign_in_path_for(_resource)
        new_chat_path
      end

      private

      def fail_authentication
        redirect_to root_path
      end
    end
  end
end
