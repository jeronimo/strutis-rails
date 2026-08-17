# frozen_string_literal: true

module Devise
  module Models
    module TokenAuthenticatable
      extend ActiveSupport::Concern

      included do
        before_create :generate_authentication_token
      end

      def self.required_fields(klass)
        [ :authentication_token ]
      end

      module ClassMethods
        def find_for_authentication(conditions)
          if conditions.key?(:token) && conditions[:token].present?
            find_by(authentication_token: conditions.delete(:token))
          else
            super
          end
        end
      end

      def generate_authentication_token
        loop do
          self.authentication_token = SecureRandom.hex(20)
          break unless self.class.where(authentication_token: authentication_token).exists?
        end
      end

      def reset_authentication_token
        generate_authentication_token
        save(validate: false)
      end
    end
  end
end
