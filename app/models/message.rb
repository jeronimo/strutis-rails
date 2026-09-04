class Message < ApplicationRecord
  belongs_to :conversation

  after_create :reset_conversation_tool_call_cache
  after_update :reset_conversation_tool_call_cache
  after_destroy :reset_conversation_tool_call_cache

  validates :role, presence: true
  validates :content, presence: true, unless: -> { tool_calls.present? }

  def tool_name
    return 'unknown' unless tool_call_id
    conversation.tool_call_names.fetch(tool_call_id) { 'unknown' }
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

  private

  def reset_conversation_tool_call_cache
    conversation.reset_tool_call_names!
  end
end
