module Users
  module Devise
    class SessionsController < ::Devise::SessionsController
      skip_before_action :require_no_authentication, only: [ :create ], if: -> { request.format.turbo_stream? }

      def create
        self.resource = warden.authenticate!(auth_options)
        set_flash_message!(:notice, :signed_in)
        sign_in(resource_name, resource)
        yield resource if block_given?
        respond_to do |format|
          format.html { redirect_to after_sign_in_path_for(resource) }
          format.turbo_stream { render turbo_stream: turbo_stream.action('redirect', after_sign_in_path_for(resource)) }
        end
      end

      def new
        redirect_to new_chat_path if user_signed_in?
        self.resource = resource_class.new(sign_in_params)
        respond_to do |format|
          format.html { render :new }
          format.turbo_stream { render turbo_stream: turbo_stream.replace('auth_form', partial: 'users/devise/sessions/token_form', locals: { resource: resource, resource_name: resource_name }) }
        end
      end

      protected

      def after_sign_in_path_for(_resource)
        new_chat_path
      end
    end
  end
end
