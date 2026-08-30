class ConversationsController < ApplicationController
  layout 'user'
  before_action :authenticate_user!

  def new
    @models = available_models
    @conversation = nil
    @current_model = @models.first
  end

  def show
    @conversation = current_user.conversations.find_by!(public_id: params[:id])
    @models = [ @conversation.model, *available_models ].compact.uniq
    @current_model = @conversation.model
  end

  def create
    model = create_params[:model].presence
    message = create_params[:message].presence
    public_id = create_params[:conversation_public_id].presence

    if model.blank? || message.blank?
      render_conversation_error('Model and message are required.', :unprocessable_entity)
      return
    end

    conversation = find_or_create_conversation(public_id, message, model)

    if conversation.nil?
      render_conversation_error('Conversation not found.', :not_found)
      return
    end

    conversation.update!(model: model)
    user_message = conversation.messages.create!(role: 'user', content: message, model: model)
    ConversationCompletionJob.perform_later(conversation.id)

    render_conversation_created(conversation, user_message, new_conversation: public_id.blank?)
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
    @create_params ||= params.permit(:model, :message, :conversation_public_id)
  end

  def find_or_create_conversation(public_id, message, model)
    if public_id
      current_user.conversations.find_by(public_id: public_id)
    else
      current_user.conversations.create!(title: message[0, 60], model: model)
    end
  end

  def render_conversation_error(error, status)
    render turbo_stream: turbo_stream.replace('conversation-error', partial: 'conversations/error', locals: { error: error }), status: status
  end

  def available_models
    OpenaiService.models.map { |model| model[:id] }
  end

  def render_conversation_created(conversation, user_message, new_conversation:)
    streams = [
      user_message_stream(conversation, user_message, new_conversation:),
      conversation_hidden_fields_stream(conversation),
      turbo_stream.replace('conversation-error', '')
    ]
    streams << conversation_list_stream(conversation, active: new_conversation) if new_conversation
    render turbo_stream: streams
  end

  def conversation_hidden_fields_stream(conversation)
    turbo_stream.replace('conversation-hidden-fields', partial: 'conversations/conversation_hidden_fields', locals: { conversation: })
  end

  def conversation_list_stream(conversation, active:)
    turbo_stream.insert_after('new-conversation', partial: 'conversations/conversation_link', locals: { conversation:, active: })
  end

  def user_message_stream(conversation, user_message, new_conversation:)
    if new_conversation
      turbo_stream.replace('conversation-messages', partial: 'conversations/messages_container', locals: { conversation:, messages: [ user_message ] })
    else
      turbo_stream.append("messages-#{conversation.public_id}", partial: 'conversations/message', locals: { role: user_message.role, content: user_message.content })
    end
  end
end
