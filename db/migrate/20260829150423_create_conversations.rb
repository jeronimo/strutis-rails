class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :title, null: false, default: ''
      t.string :model, null: false
      t.text :summary
      t.integer :context_tokens, null: false, default: 0

      t.timestamps
    end

    add_index :conversations, :public_id, unique: true
  end
end
