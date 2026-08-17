# frozen_string_literal: true

module Devise
  module Admin
    class SessionsController < Devise::SessionsController
      layout 'admin/application'

      def new
        super
      end

      def create
        super
      end

      def destroy
        super
      end
    end
  end
end
