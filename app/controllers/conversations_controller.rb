class ConversationsController < ApplicationController
  layout 'user'
  before_action :authenticate_user!

  def new
    @models = OpenaiService.models.map { |m| m[:id] }
    session[:current_conversation_id] = nil
    session[:current_model] = @models.first if @models.any?
    @messages = []
  end

  def show
    @models = OpenaiService.models.map { |m| m[:id] }
    @conversation_id = params[:id]
    conversation_data = session[:conversations] && session[:conversations][@conversation_id]
    @messages = conversation_data && conversation_data[:messages] || []
    @current_model = (conversation_data && conversation_data[:model]) || session[:current_model]
  end

  def create
    model = params[:model]
    message = params[:message]

    unless model && message
      render json: { error: 'Model and message are required' }, status: :bad_request and return
    end

    begin
      Rails.logger.info "[Conversations#create] session[:current_conversation_id] = #{session[:current_conversation_id].inspect}"
      conversation_id = session[:current_conversation_id]
      conversation_data = session[:conversations] && session[:conversations][conversation_id]
      messages = conversation_data && conversation_data[:messages] || []

      messages << { role: 'user', content: message }

      result = OpenaiService.completion(messages, model, conversation_id)

      ai_content = result[:response]
      conversation_id = result[:conversation_id]
      Rails.logger.info "[Conversations#create] API returned conversation_id = #{conversation_id.inspect}"
      messages << { role: 'assistant', content: ai_content }
      session[:conversations] ||= {}
      session[:current_conversation_id] = conversation_id
      Rails.logger.info "[Conversations#create] Stored session[:current_conversation_id] = #{session[:current_conversation_id].inspect}"
      session[:current_model] = model
        session[:conversations][conversation_id] = {
          messages: messages,
          model: model
        }

      render json: { response: ai_content }
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
