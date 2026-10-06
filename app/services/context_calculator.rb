class ContextCalculator
  CHARS_PER_TOKEN = 4
  TEMPLATE_TOKENS_PER_MESSAGE = 8

  def initialize(conversation)
    @conversation = conversation
  end

  def window
    OpenAiService.context_length(@conversation.model)
  end

  def usage_percent
    return nil unless window.to_i.positive?

    (@conversation.context_tokens.to_f / window * 100).round
  end

  def compaction_needed?
    window.to_i.positive? && @conversation.context_tokens.to_f / window > Conversation::COMPACT_THRESHOLD
  end

  def prompt_over_budget?
    window.to_i.positive? && prompt_token_estimate / window.to_f > Conversation::COMPACT_THRESHOLD
  end

  def prompt_token_estimate
    entries = @conversation.prompt_messages
    content_chars = entries.sum { |entry| entry_content_chars(entry[:content]) }
    (content_chars / CHARS_PER_TOKEN.to_f).ceil + entries.size * TEMPLATE_TOKENS_PER_MESSAGE
  end

  private

  def entry_content_chars(content)
    content.is_a?(Array) ? content.sum { |part| part[:text].to_s.length } : content.to_s.length
  end
end
