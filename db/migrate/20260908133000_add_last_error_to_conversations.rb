class AddLastErrorToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :last_error, :string
  end
end
