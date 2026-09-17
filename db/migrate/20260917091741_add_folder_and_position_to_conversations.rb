class AddFolderAndPositionToConversations < ActiveRecord::Migration[8.1]
  def up
    add_reference :conversations, :folder, foreign_key: true
    add_column :conversations, :position, :float, null: false, default: 0.0
    add_index :conversations, :position
    execute 'UPDATE conversations SET position = COALESCE((SELECT MAX(id) FROM conversations), 0) - id + 1'
  end

  def down
    remove_index :conversations, :position
    remove_column :conversations, :position
    remove_reference :conversations, :folder
  end
end
