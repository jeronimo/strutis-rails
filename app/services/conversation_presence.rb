class ConversationPresence
  def self.viewing?(conversation_id)
    new(conversation_id).viewing?
  end

  def initialize(conversation_id)
    @conversation_id = conversation_id
  end

  def viewing?
    tokens.any?
  end

  def start!(token)
    Rails.cache.write(key, tokens | [ token ])
  end

  def finish!(token)
    remaining = tokens - [ token ]
    remaining.any? ? Rails.cache.write(key, remaining) : Rails.cache.delete(key)
  end

  private

  def tokens
    Array(Rails.cache.read(key))
  end

  def key
    "conversation_presence:viewing:#{@conversation_id}"
  end
end
