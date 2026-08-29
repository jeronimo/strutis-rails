class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content
      t.text :reasoning
      t.string :model
      t.jsonb :tool_calls
      t.string :tool_call_id
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :reasoning_tokens
      t.integer :latency_ms
      t.datetime :compacted_at

      t.timestamps
    end
  end
end
