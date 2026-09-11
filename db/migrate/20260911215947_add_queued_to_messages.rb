class AddQueuedToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :queued, :boolean, default: false, null: false
  end
end
