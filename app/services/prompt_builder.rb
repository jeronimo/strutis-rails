class PromptBuilder
  def initialize(conversation)
    @conversation = conversation
  end

  def build
    active = @conversation.messages.where(compacted_at: nil).where.not(role: 'compaction').where(queued: false).to_a
    image_input = OpenAiService.supports_image_input?(@conversation.model)
    entries = active.select { |message| message.role == 'system' }.map(&:to_prompt_entry)
    digest = compaction_digest
    entries << { role: 'user', content: digest } if digest.present?
    entries.concat(active.reject { |message| message.role == 'system' }.flat_map { |message| message.prompt_entries(image_input: image_input) })
    entries
  end

  private

  def compaction_digest
    return '' if @conversation.summary.blank?
    template = Prompt.global('digest')
    return '' if template.blank?
    template.sub('{{summary}}', @conversation.summary)
  end
end
