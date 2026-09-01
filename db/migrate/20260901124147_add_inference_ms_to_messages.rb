class AddInferenceMsToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :inference_ms, :integer
  end
end
