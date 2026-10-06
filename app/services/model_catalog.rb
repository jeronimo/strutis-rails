class ModelCatalog
  CACHE_KEY = 'openai:models'
  TTL = 600

  def self.models
    cached = Rails.cache.read(CACHE_KEY)
    return cached[:data] if cached && Time.now - cached[:fetched_at] <= TTL

    begin
      data = OpenAiClient.new.get('/v1/models', retries: 1)[:data] || []
      Rails.cache.write(CACHE_KEY, { data:, fetched_at: Time.now })
      data
    rescue OpenAiClient::Error, *OpenAiClient::RETRYABLE_EXCEPTIONS
      Rails.logger.warn '[OpenAI] Models refresh failed, serving stale list' if cached
      raise if cached.nil?
      cached[:data]
    end
  end

  def self.model(model_id)
    models.find { |model| model[:id] == model_id }
  end

  def self.display_name(model_id)
    model(model_id)&.dig(:display_name).presence || model_id
  end

  def self.context_length(model_id)
    model(model_id)&.dig(:context_length)
  end

  def self.chat_template_kwargs(model_id)
    model(model_id)&.dig(:chat_template_kwargs)
  end

  def self.supports_image_input?(model_id)
    model(model_id)&.dig(:capabilities, :input)&.include?('image') || false
  end

  def self.supports_text_input?(model_id)
    model(model_id)&.dig(:capabilities, :input)&.include?('text') || false
  end

  def self.supports_stt?(model_id)
    model(model_id)&.dig(:capabilities, :input)&.include?('audio') || false
  end

  def self.visible?(model_id)
    model(model_id)&.dig(:visible) != false
  end

  def self.stt_model
    models.find { |model| supports_stt?(model[:id]) }
  end
end
