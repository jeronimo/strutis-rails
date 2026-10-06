class Conversation < ApplicationRecord
  COMPACT_THRESHOLD = 0.8
  TITLE_PLACEHOLDER_LENGTH = 60

  belongs_to :user
  belongs_to :folder, optional: true
  has_many :messages, -> { order(:id) }, dependent: :destroy

  default_scope { where(deleted_at: nil) }
  scope :with_deleted, -> { unscope(where: :deleted_at) }

  before_create { self.public_id = SecureRandom.hex(16) }

  validates :model, presence: true

  def destroy
    update_columns(deleted_at: Time.current)
  end

  def restore
    update_columns(deleted_at: nil)
  end

  def mark_read!
    return unless unread?
    update_column(:unread, false)
    UserChannel.broadcast_unread(self, unread: false)
  end

  def mark_unread!
    return if ConversationPresence.viewing?(id)
    update_column(:unread, true)
    UserChannel.broadcast_unread(self, unread: true)
  end

  def open_ai_service
    OpenAiService.new(conversation_id: public_id, user_public_id: user.public_id)
  end

  def context_usage_percent
    context_calculator.usage_percent
  end

  def compaction_needed?
    context_calculator.compaction_needed?
  end

  def prompt_over_budget?
    context_calculator.prompt_over_budget?
  end

  def prompt_token_estimate
    context_calculator.prompt_token_estimate
  end

  def compactable?
    last_user_message = messages.where(compacted_at: nil).where(role: 'user').order(:id).last
    return false unless last_user_message
    messages.where(compacted_at: nil).where.not(role: [ 'system', 'compaction' ]).where('id < ?', last_user_message.id).exists?
  end

  def title_generation_needed?
    first_user_message = messages.where(role: 'user').first
    return false if first_user_message.blank? || first_user_message.content.blank?
    title == first_user_message.content[0, TITLE_PLACEHOLDER_LENGTH]
  end

  def chat_template_kwargs
    kwargs = OpenAiService.chat_template_kwargs(model)
    return unless kwargs
    kwargs = kwargs.merge(enable_thinking: thinking)
    kwargs = kwargs.merge(reasoning_effort: reasoning_effort) if reasoning_effort.present?
    kwargs
  end

  def prompt_messages
    prompt_builder.build
  end

  def tool_call_names
    @tool_call_names ||= build_tool_call_names
  end

  def reset_tool_call_names!
    @tool_call_names = nil
  end

  private

  def context_calculator
    @context_calculator ||= ContextCalculator.new(self)
  end

  def prompt_builder
    @prompt_builder ||= PromptBuilder.new(self)
  end

  def build_tool_call_names
    source = messages.loaded? ? messages.to_a : messages.where(role: 'assistant').where.not(tool_calls: nil).load
    source
      .flat_map { |message| Array(message.tool_calls) }
      .to_h { |tool_call| [ tool_call['id'], tool_call.dig('function', 'name') ] }
  end
end
