class Message < ApplicationRecord
  belongs_to :conversation
  has_many_attached :attachments

  after_create :reset_conversation_tool_call_cache
  after_update :reset_conversation_tool_call_cache
  after_destroy :reset_conversation_tool_call_cache

  validates :role, presence: true

  def tool_name
    return 'unknown' unless tool_call_id
    conversation.tool_call_names.fetch(tool_call_id) { 'unknown' }
  end

  def display_content
    return content unless role == 'tool'
    JSON.pretty_generate(JSON.parse(content))
  rescue JSON::ParserError => e
    Rails.logger.error { "[Message] Malformed tool JSON in message #{id}: #{e.message}" }
    Sentry.capture_exception(e)
    content
  end

  def tool_summary
    return unless role == 'tool'
    parsed = JSON.parse(content)
    parsed['filename'] || parsed['query'] || parsed['url'] if parsed.is_a?(Hash)
  rescue JSON::ParserError => e
    Rails.logger.error { "[Message] Malformed tool JSON in message #{id}: #{e.message}" }
    Sentry.capture_exception(e)
    nil
  end

  def truncated?
    return false unless role == 'tool'
    parsed = JSON.parse(content)
    parsed.is_a?(Hash) && parsed['truncated'] == true
  rescue JSON::ParserError => e
    Rails.logger.error { "[Message] Malformed tool JSON in message #{id}: #{e.message}" }
    Sentry.capture_exception(e)
    false
  end

  def to_prompt_entry
    entry = { role: role, content: prompt_content }
    entry[:tool_calls] = tool_calls if tool_calls.present?
    entry[:tool_call_id] = tool_call_id if tool_call_id.present?
    entry
  end

  def audio_attachment?(attachment)
    attachment.blob.content_type.to_s.start_with?('audio/')
  end

  def prompt_entries(image_input: false)
    return [ to_prompt_entry ] unless role == 'user' && image_input && image_attachments.any?

    text = prompt_content(exclude_images: true)
    image_attachments.map.with_index do |attachment, index|
      parts = index.zero? && text.present? ? [ { type: 'text', text: text } ] : []
      parts << { type: 'image_url', image_url: { url: attachment.blob.url(expires_in: 1.hour) } }
      { role: 'user', content: parts }
    end
  end

  def audio_attachment?(attachment)
    attachment.blob.content_type.to_s.start_with?('audio/')
  end

  private

  def image_attachments
    attachments.select { |attachment| image_attachment?(attachment) }
  end

  def image_attachment?(attachment)
    attachment.blob.content_type.to_s.start_with?('image/')
  end

  def prompt_content(exclude_images: false)
    files = exclude_images ? attachments.reject { |attachment| image_attachment?(attachment) } : attachments
    return content if files.empty?
    lines = files.map do |attachment|
      audio_attachment?(attachment) ? '[transcribed from audio]' : "- #{attachment.filename}: #{attachment.blob.url(expires_in: 1.hour)}"
    end
    "#{content}\n#{lines.join("\n")}"
  end

  def reset_conversation_tool_call_cache
    conversation.reset_tool_call_names!
  end
end
