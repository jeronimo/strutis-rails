class ConversationTitleService
  def self.perform(conversation)
    new(conversation).perform
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def perform
    title = generate_title
    return if title.blank?

    @conversation.update!(title: title)
    title
  end

  private

  def generate_title
    conversation = title_messages.map { |message| "#{message.role}: #{message.content}" }.join("\n\n")
    prompt = [
      { role: 'system', content: title_prompt },
      { role: 'user', content: conversation }
    ]
    OpenaiService.completion(prompt, @conversation.model, @conversation.public_id)[:content].to_s.strip.presence
  end

  def title_prompt
    Prompt.global('title').presence || Prompt::TITLE_DEFAULT
  end

  def title_messages
    @conversation.messages.where(compacted_at: nil).where(role: [ 'user', 'assistant' ]).select { |message| message.content.present? }
  end
end
