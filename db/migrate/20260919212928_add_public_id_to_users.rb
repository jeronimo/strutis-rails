class AddPublicIdToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :public_id, :string
    User.find_each { |user| user.update_column(:public_id, SecureRandom.hex(16)) }
    change_column_null :users, :public_id, false
    add_index :users, :public_id, unique: true
  end

  def down
    remove_index :users, :public_id
    remove_column :users, :public_id
  end
end
