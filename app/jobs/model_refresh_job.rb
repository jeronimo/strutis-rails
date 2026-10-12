class ModelRefreshJob < ApplicationJob
  def perform
    data = OpenAiClient.new.get('/v1/models')[:data]
    Rails.cache.write(ModelCatalog::CACHE_KEY, { data:, fetched_at: Time.now }) if data.present?
  end
end
