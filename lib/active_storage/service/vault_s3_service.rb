require 'active_storage/service/s3_service'

module ActiveStorage
  class Service
    class VaultS3Service < S3Service
      CDN_HOST = 'cdn.strutis.ai'

      def public?
        Rails.env.production?
      end

      def public_url(key, **_options)
        "https://#{CDN_HOST}/#{key}"
      end
    end
  end
end
