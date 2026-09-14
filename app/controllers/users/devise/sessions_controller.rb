module Users
  module Devise
    class SessionsController < ::Devise::SessionsController
      include Users::TwoFactorStep

      def create
        self.resource = warden.authenticate(auth_options)
        return fail_authentication unless resource

        begin_two_factor(resource)
      end

      def email
        self.resource = resource_class.new
      end

      def new
        redirect_to user_signed_in? ? new_conversation_path : root_path
      end

      protected

      def fail_authentication
        self.resource = resource_class.new
        flash.now[:user] = { alert: t('sign_in.invalid_credentials') }
        render :email, status: :unprocessable_entity
      end
    end
  end
end
