module Users
  module Devise
    class UnlocksController < ::Devise::UnlocksController
      def create
        self.resource = resource_class.send_unlock_instructions(params[resource_name])

        if successfully_sent?(resource)
          flash[:user] = { notice: t('devise.unlocks.send_instructions') }
          redirect_to new_session_path(resource_name)
        else
          flash[:user] = { alert: resource.errors.full_messages.join(', ') }
          redirect_to new_unlock_path(resource_name)
        end
      end
    end
  end
end
