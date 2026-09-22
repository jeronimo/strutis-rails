require 'active_storage/service/s3_service'

module ActiveStorage
  class Service
    class VaultS3Service < S3Service
      def public?
        Rails.env.production?
      end

      def public_url(key, **_options)
        "https://#{ENV.fetch('FILES_HOST')}/#{key}"
      end
    end
  end
end
