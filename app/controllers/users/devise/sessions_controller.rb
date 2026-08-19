module Users
  module Devise
    class SessionsController < ::Devise::SessionsController
      skip_before_action :require_no_authentication, only: [ :create ], if: -> { request.format.turbo_stream? }

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

        respond_to do |format|
          format.turbo_stream { render turbo_stream: view_context.turbo_stream_action_tag('redirect', url: after_sign_in_path_for(resource)) }
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

      private

      def fail_authentication
        self.resource = resource_class.new
        respond_to do |format|
          format.all { render :new, status: :unauthorized }
        end
      end
    end
  end
end
