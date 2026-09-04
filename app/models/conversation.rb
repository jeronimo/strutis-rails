class Conversation < ApplicationRecord
  COMPACT_THRESHOLD = 0.8

  belongs_to :user
  has_many :messages, -> { order(:id) }, dependent: :destroy

  before_create { self.public_id = SecureRandom.hex(16) }

  validates :model, presence: true

  def context_window
    OpenaiService.context_length(model)
  rescue StandardError
    nil
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

  def prompt_messages
    active = messages.where(compacted_at: nil).where.not(role: 'compaction').to_a
    entries = active.select { |message| message.role == 'system' }.map(&:to_prompt_entry)
    entries << { role: 'system', content: summary } if summary.present?
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
end
