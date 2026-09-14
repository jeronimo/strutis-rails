module Users
  module Devise
    class PasswordsController < ::Devise::PasswordsController
      def create
        self.resource = resource_class.send_reset_password_instructions(params[resource_name])

        if successfully_sent?(resource)
          flash[:user] = { notice: t('devise.passwords.send_instructions') }
          redirect_to root_path
        else
          flash[:user] = { alert: resource.errors.full_messages.join(', ') }
          redirect_to new_password_path(resource_name)
        end
      end
    end
  end
end
