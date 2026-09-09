class Prompt < ApplicationRecord
  BUILTIN = %w[ system compacting digest title ].freeze

  SYSTEM_DEFAULT = 'You are a helpful assistant. Answer concisely and use the available tools when they help.'
  COMPACTING_DEFAULT = <<~TEXT.chomp
    This is a compaction and summary request. Write a factual summary of the conversation above. It replaces the summarized messages and becomes the only record of them, so nothing in it may be lost.

    STRICT DATA PRESERVATION RULES — follow all of them:
    1. List every distinct subject or entity mentioned as its own entry. Do not merge, consolidate, or drop any, even if several are similar or redundant.
    2. For each, keep the specifics and details that matter to the user's question.
    3. Preserve every number, figure, date, name, and measurement exactly as stated. Do not round, approximate, estimate, or omit values.
    4. Preserve comparisons and contrasts between subjects.
    5. Keep the source or URL for each data point.
    6. Use a structured layout: one section per topic; within each, one bullet per subject with its data. Do not write flowing prose that buries or drops data points.

    Also capture the user's requests, goals, decisions, conclusions, constraints, preferences, and open questions.

    Summarize only the substance — the findings, data, decisions, and answers. Do not continue the conversation or answer any question in it. Do not include meta-statements about the conversation (for example whether the context was compacted), and do not mention the summary process.

    Output only the summary.
  TEXT
  DIGEST_DEFAULT = <<~TEXT.chomp
    CONTEXT COMPACTION: Earlier messages in this conversation were summarized to fit the context window. The digest below is now their only record. It is a lossy digest, not the raw history: exact figures, full lists, ratings, prices, and sources may be missing, rounded, or incomplete. Do not assume you still have the original detail. When an answer needs a specific value or a complete list the digest does not clearly contain, re-run the relevant tool (for example web search) to recover it instead of relying on the digest.

    DIGEST:
    {{summary}}
  TEXT
  TITLE_DEFAULT = 'Write a concise title (at most 6 words) that captures the topic of the conversation. Output only the title, no quotes.'

  DEFAULTS = {
    'system' => SYSTEM_DEFAULT,
    'compacting' => COMPACTING_DEFAULT,
    'digest' => DIGEST_DEFAULT,
    'title' => TITLE_DEFAULT
  }.freeze

  belongs_to :user, optional: true
  validates :key, presence: true
  validates :content, presence: true

  def self.global(key)
    find_by(key: key, user_id: nil)&.content.to_s
  end
end
