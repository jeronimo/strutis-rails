module Users
  module Devise
    class SessionsController < ::Devise::SessionsController
      include Users::TwoFactorStep

      def create
        user = User.find_by(email: params.dig(:user, :email))
        return fail_authentication unless user&.valid_for_authentication? && user.valid_password?(params[:user][:password])

        begin_two_factor(user)
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
        render :email, status: :unprocessable_content
      end
    end
  end
end
