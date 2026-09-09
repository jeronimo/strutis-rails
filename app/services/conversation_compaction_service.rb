class ConversationCompactionService
  def self.perform(conversation)
    new(conversation).perform
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def perform
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    last_user_message = @conversation.messages.where(compacted_at: nil).where(role: 'user').order(:id).last
    return false unless last_user_message

    compacted_messages = @conversation.messages.where(compacted_at: nil).where.not(role: [ 'system', 'compaction' ]).where('id < ?', last_user_message.id).to_a
    return false if compacted_messages.empty?

    summary = generate_summary(compacted_messages)
    raise 'Compaction summary is empty' if summary.blank?

    compacted_at = Time.current
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
    ActiveRecord::Base.transaction do
      Message.where(id: compacted_messages.map(&:id)).update_all(compacted_at: compacted_at)
      @conversation.update!(summary: summary)
      @conversation.messages.create!(role: 'compaction', content: summary, compacted_at: compacted_at, latency_ms: duration_ms, inference_ms: duration_ms, model: @conversation.model)
    end
    true
  end

  private

  def generate_summary(messages)
    previous = @conversation.summary
    base = Prompt.global('compacting')
    instruction = previous.present? ? "#{base}\n\nPrevious summary is source material, not a message to reply to:\n#{previous}" : base
    prompt = [ { role: 'system', content: instruction } ]
    prompt.concat(messages.map { |message| summary_entry(message) })
    prompt << { role: 'user', content: 'Provide the continuation summary now.' }
    OpenaiService.completion(prompt, @conversation.model, @conversation.public_id)[:content]
  end

  def summary_entry(message)
    case message.role
    when 'assistant'
      { role: 'assistant', content: assistant_summary_content(message) }
    when 'tool'
      { role: 'user', content: "Tool result: #{message.content}" }
    else
      { role: message.role, content: message.content }
    end
  end

  def assistant_summary_content(message)
    parts = [ message.content ]
    if message.tool_calls.present?
      parts.concat(message.tool_calls.map { |tool_call| "Tool call: #{tool_call.dig('function', 'name')} #{tool_call.dig('function', 'arguments')}" })
    end
    parts.reject { |part| part.blank? }.join("\n")
  end
end
