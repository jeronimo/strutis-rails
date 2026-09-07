class AddThinkingAndReasoningEffortToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :thinking, :boolean, null: false, default: false
    add_column :conversations, :reasoning_effort, :string
  end
end
