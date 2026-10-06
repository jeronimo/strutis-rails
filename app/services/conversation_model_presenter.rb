class ConversationModelPresenter
  def initialize(conversation)
    @conversation = conversation
  end

  def available_models
    @available_models ||= chat_models.map { |model| [ model[:display_name].presence || model[:id], model[:id] ] }
  end

  def model
    current = current_model
    metadata = model_metadata
    {
      id: current,
      metadata:,
      current_name: metadata[current]&.dig(:display_name) || current,
      thinking: @conversation ? @conversation.thinking : metadata[current]&.fetch(:default_thinking, false),
      supports_thinking: metadata[current][:supports_thinking],
      reasoning_effort: @conversation ? (@conversation.reasoning_effort || metadata[current]&.dig(:default_reasoning_effort)) : metadata[current]&.dig(:default_reasoning_effort),
      reasoning_effort_options: metadata[current]&.fetch(:reasoning_effort_options, []) || [],
      stt_available: ModelCatalog.stt_model.present?
    }
  end

  def context
    {
      tokens: @conversation&.context_tokens || 0,
      window: model_metadata[current_model]&.dig(:context_length) || 0,
      percent: @conversation&.context_usage_percent || 0,
      percent_display: format('%d%%', @conversation&.context_usage_percent || 0),
      compact_threshold: Conversation::COMPACT_THRESHOLD
    }
  end

  private

  def chat_models
    @chat_models ||= ModelCatalog.models.select { |model| ModelCatalog.supports_text_input?(model[:id]) && ModelCatalog.visible?(model[:id]) }
  end

  def model_metadata
    @model_metadata ||= chat_models.each_with_object({}) do |model, metadata|
      kwargs = model[:chat_template_kwargs] || {}
      metadata[model[:id]] = {
        display_name: model[:display_name].presence || model[:id],
        context_length: model[:context_length],
        supports_image_input: ModelCatalog.supports_image_input?(model[:id]),
        supports_thinking: kwargs.key?(:enable_thinking),
        default_thinking: kwargs[:enable_thinking] || false,
        reasoning_effort_options: Array(kwargs[:reasoning_effort_options]),
        default_reasoning_effort: kwargs[:reasoning_effort]
      }
    end
  end

  def current_model
    @current_model ||= compute_current_model
  end

  def compute_current_model
    ids = available_models.map { |_, id| id }
    return ids.first unless @conversation
    ids.include?(@conversation.model) ? @conversation.model : ids.first
  end
end
