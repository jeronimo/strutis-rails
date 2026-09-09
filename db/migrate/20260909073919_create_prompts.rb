class CreatePrompts < ActiveRecord::Migration[8.1]
  def change
    create_table :prompts do |t|
      t.string :key, null: false
      t.text :content, null: false
      t.references :user, foreign_key: true

      t.timestamps
    end

    add_index :prompts, [ :key, :user_id ]
  end
end
