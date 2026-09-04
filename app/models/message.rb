class Message < ApplicationRecord
  belongs_to :conversation

  validates :role, presence: true
  validates :content, presence: true, unless: -> { tool_calls.present? }

  def tool_name
    return 'unknown' unless tool_call_id
    calls = conversation.messages.where(role: 'assistant').where.not(tool_calls: nil).flat_map { |m| Array(m.tool_calls) }
    calls.find { |tool_call| tool_call['id'] == tool_call_id }&.dig('function', 'name') || 'unknown'
  end

  def display_content
    return content unless role == 'tool'
    JSON.pretty_generate(JSON.parse(content))
  rescue JSON::ParserError
    content
  end

  def tool_summary
    return unless role == 'tool'
    parsed = JSON.parse(content)
    parsed['query'] || parsed['url'] if parsed.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def to_prompt_entry
    entry = { role: role, content: content }
    entry[:tool_calls] = tool_calls if tool_calls.present?
    entry[:tool_call_id] = tool_call_id if tool_call_id.present?
    entry
  end
end
