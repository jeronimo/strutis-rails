class ConversationsController < ApplicationController
  layout 'user'
  before_action :authenticate_user!
  before_action :load_conversations

  def new
    @conversation = nil
    setup_conversation_model
  end

  def show
    @conversation = current_user.conversations.find_by!(public_id: params[:id])
    setup_conversation_model
  end

  def create
    model = create_params[:model].presence
    message = create_params[:message].presence
    public_id = create_params[:conversation_public_id].presence

    if model.blank? || message.blank?
      render_conversation_error('Model and message are required.', :unprocessable_entity)
      return
    end

    return handle_compact(model, public_id) if message.strip == '/compact'

    conversation = find_or_create_conversation(public_id, message, model)

    if conversation.nil?
      render_conversation_error('Conversation not found.', :not_found)
      return
    end

    apply_conversation_settings(conversation, model)

    if ConversationCompletionJob.active?(conversation.id)
      conversation.messages.create!(role: 'user', content: message, model: model, queued: true)
      render turbo_stream: turbo_stream.replace("messages-#{conversation.public_id}", partial: 'conversations/messages_frame', locals: { conversation:, messages: conversation.messages, show_progress: true })
    else
      user_message = conversation.messages.create!(role: 'user', content: message, model: model)
      ConversationCompletionJob.perform_later(conversation.id)
      render_conversation_created(conversation, user_message, new_conversation: public_id.blank?)
    end
  end

  def stop
    conversation = current_user.conversations.find_by!(public_id: params[:id])
    ConversationCompletionJob.request_stop(conversation.id)
    render turbo_stream: turbo_stream.remove("conversation-progress-#{conversation.public_id}")
  end

  def update
    conversation = current_user.conversations.find_by!(public_id: params[:id])
    conversation.update!(title: update_params[:title].to_s.strip)

    streams = [ turbo_stream.replace("conversation-title-#{conversation.public_id}", conversation.title.presence || 'Untitled') ]
    if request.referer.to_s.end_with?(conversation_path(conversation.public_id))
      streams << turbo_stream.replace('conversation-drawer-title', conversation.title.presence || 'New Conversation')
    end
    render turbo_stream: streams
  end

  def destroy
    conversation = current_user.conversations.find_by!(public_id: params[:id])
    conversation.destroy!

    if request.referer.to_s.end_with?(conversation_path(conversation.public_id))
      redirect_to new_conversation_path
    else
      redirect_back fallback_location: new_conversation_path
    end
  end

  private

  def create_params
    @create_params ||= params.permit(:model, :message, :conversation_public_id, :thinking, :reasoning_effort)
  end

  def update_params
    params.permit(:title)
  end

  def apply_conversation_settings(conversation, model)
    conversation.update!(model: model, thinking: create_params[:thinking] == '1', reasoning_effort: valid_reasoning_effort(model))
  end

  def valid_reasoning_effort(model)
    effort = create_params[:reasoning_effort].presence
    options = OpenaiService.chat_template_kwargs(model)&.dig(:reasoning_effort_options) || []
    options.include?(effort) ? effort : nil
  end

  def handle_compact(model, public_id)
    conversation = current_user.conversations.find_by(public_id: public_id)
    unless conversation&.compactable?
      render_conversation_error('Nothing to compact yet.', :unprocessable_entity)
      return
    end

    apply_conversation_settings(conversation, model)
    ConversationCompactionJob.perform_later(conversation.id)
    render turbo_stream: [
      turbo_stream.replace('conversation-error', ''),
      turbo_stream.append("messages-#{conversation.public_id}", partial: 'conversations/progress', locals: { conversation: })
    ]
  end

  def find_or_create_conversation(public_id, message, model)
    if public_id
      current_user.conversations.find_by(public_id: public_id)
    else
      conversation = current_user.conversations.create!(title: message[0, Conversation::TITLE_PLACEHOLDER_LENGTH], model: model)
      system_content = current_user.effective_prompt('system')
      conversation.messages.create!(role: 'system', content: system_content, model: model) if system_content.present?
      conversation
    end
  end

  def render_conversation_error(error, status)
    render turbo_stream: turbo_stream.replace('conversation-error', partial: 'conversations/error', locals: { error: error }), status: status
  end

  def available_models
    OpenaiService.models.map { |model| model[:id] }
  end

  def model_metadata
    OpenaiService.models.each_with_object({}) do |model, metadata|
      kwargs = model[:chat_template_kwargs] || {}
      metadata[model[:id]] = {
        context_length: model[:context_length],
        supports_thinking: kwargs.key?(:enable_thinking),
        default_thinking: kwargs[:enable_thinking] || false,
        reasoning_effort_options: Array(kwargs[:reasoning_effort_options]),
        default_reasoning_effort: kwargs[:reasoning_effort]
      }
    end
  end

  def setup_conversation_model
    @models = available_models
    @model_metadata = model_metadata
    @current_model = current_model
    meta = @model_metadata[@current_model]
    @current_thinking = @conversation ? @conversation.thinking : meta&.fetch(:default_thinking, false)
    @current_reasoning_effort = @conversation ? (@conversation.reasoning_effort || meta&.dig(:default_reasoning_effort)) : meta&.dig(:default_reasoning_effort)
    @reasoning_effort_options = meta&.fetch(:reasoning_effort_options, []) || []
    @thinking_visible = meta&.fetch(:supports_thinking, false)
    @reasoning_visible = meta&.fetch(:reasoning_effort_options, []).present?
  end

  def current_model
    return @models.first unless @conversation
    @models.include?(@conversation.model) ? @conversation.model : @models.first
  end

  def render_conversation_created(conversation, user_message, new_conversation:)
    streams = [
      user_message_stream(conversation, user_message, new_conversation:),
      conversation_hidden_fields_stream(conversation),
      turbo_stream.replace('conversation-error', ''),
      turbo_stream.append("messages-#{conversation.public_id}", partial: 'conversations/progress', locals: { conversation: })
    ]
    streams << conversation_list_stream(conversation, active: new_conversation) if new_conversation
    streams << turbo_stream.remove('system-prompt-section') if new_conversation
    render turbo_stream: streams
  end

  def conversation_hidden_fields_stream(conversation)
    turbo_stream.replace('conversation-hidden-fields', partial: 'conversations/conversation_hidden_fields', locals: { conversation: })
  end

  def conversation_list_stream(conversation, active:)
    turbo_stream.after('new-conversation', partial: 'conversations/conversation_link', locals: { conversation:, active: })
  end

  def user_message_stream(conversation, user_message, new_conversation:)
    if new_conversation
      turbo_stream.replace('conversation-messages', partial: 'conversations/messages_container', locals: { conversation:, messages: [ user_message ] })
    else
      turbo_stream.append("messages-#{conversation.public_id}", partial: 'conversations/message', locals: { message: user_message })
    end
  end
end
