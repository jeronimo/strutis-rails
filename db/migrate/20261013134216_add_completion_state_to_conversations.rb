class AddCompletionStateToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :running_at, :datetime
    add_column :conversations, :stop_requested_at, :datetime
    add_index :conversations, :running_at
  end
end
