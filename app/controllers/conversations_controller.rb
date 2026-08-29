class ConversationsController < ApplicationController
  layout 'user'
  before_action :authenticate_user!

  def new
    @models = OpenaiService.models.map { |m| m[:id] }
    @conversation = nil
    @messages = []
    @current_model = @models.first if @models.any?
  end

  def show
    @conversation = current_user.conversations.find_by!(public_id: params[:id])
    @messages = @conversation.messages
    @models = OpenaiService.models.map { |m| m[:id] }
    @current_model = @conversation.model
  end

  def create
    model = params[:model]
    message = params[:message]

    unless model && message
      render json: { error: 'Model and message are required' }, status: :bad_request and return
    end

    conversation = find_or_create_conversation(message, model)
    conversation.update(model: model)
    conversation.messages.create!(role: 'user', content: message, model: model)

    api_messages = conversation.messages.map { |m| { role: m.role, content: m.content } }
    result = OpenaiService.completion(api_messages, model, conversation.public_id)
    conversation.messages.create!(role: 'assistant', content: result[:response], model: model)

    render json: { response: result[:response], conversation_id: conversation.public_id }
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def find_or_create_conversation(message, model)
    public_id = params[:conversation_public_id]
    if public_id.present?
      current_user.conversations.find_by!(public_id: public_id)
    else
      current_user.conversations.create!(title: message.strip[0, 60], model: model)
    end
  end
end
