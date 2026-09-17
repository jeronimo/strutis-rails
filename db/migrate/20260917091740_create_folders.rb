class CreateFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :folders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :folders }
      t.string :name, null: false, default: ''
      t.float :position, null: false, default: 0.0
      t.timestamps
    end
    add_index :folders, :position
  end
end
