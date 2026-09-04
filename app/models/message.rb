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
end
