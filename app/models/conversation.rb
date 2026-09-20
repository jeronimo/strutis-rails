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

  def openai_service
    OpenaiService.new(conversation_id: public_id, user_public_id: user.public_id)
  end

  def context_window
    OpenaiService.context_length(model)
  end

  def context_usage_percent
    window = context_window
    return nil unless window.to_i.positive?

    (context_tokens.to_f / window * 100).round
  end

  def compaction_needed?
    window = context_window
    window.to_i.positive? && context_tokens.to_f / window > COMPACT_THRESHOLD
  end

  def prompt_over_budget?
    window = context_window
    window.to_i.positive? && prompt_token_estimate / window.to_f > COMPACT_THRESHOLD
  end

  def prompt_token_estimate
    entries = prompt_messages
    content_chars = entries.sum { |entry| entry[:content].to_s.length }
    (content_chars / ConversationCompactionService::CHARS_PER_TOKEN.to_f).ceil + entries.size * ConversationCompactionService::TEMPLATE_TOKENS_PER_MESSAGE
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
    kwargs = OpenaiService.chat_template_kwargs(model)
    return unless kwargs
    kwargs = kwargs.merge(enable_thinking: thinking)
    kwargs = kwargs.merge(reasoning_effort: reasoning_effort) if reasoning_effort.present?
    kwargs
  end

  def prompt_messages
    active = messages.where(compacted_at: nil).where.not(role: 'compaction').where(queued: false).to_a
    entries = active.select { |message| message.role == 'system' }.map(&:to_prompt_entry)
    digest = compaction_digest if summary.present?
    entries << { role: 'user', content: digest } if digest.present?
    entries.concat(active.reject { |message| message.role == 'system' }.map(&:to_prompt_entry))
    entries
  end

  def tool_call_names
    @tool_call_names ||= build_tool_call_names
  end

  def reset_tool_call_names!
    @tool_call_names = nil
  end

  private

  def build_tool_call_names
    source = messages.loaded? ? messages.to_a : messages.where(role: 'assistant').where.not(tool_calls: nil).load
    source
      .flat_map { |message| Array(message.tool_calls) }
      .to_h { |tool_call| [ tool_call['id'], tool_call.dig('function', 'name') ] }
  end

  def compaction_digest
    template = Prompt.global('digest')
    return '' if template.blank?
    template.sub('{{summary}}', summary)
  end
end
