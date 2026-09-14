class AddTwoFactorCodeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :two_factor_code_digest, :string
    add_column :users, :two_factor_code_salt, :string
    add_column :users, :two_factor_code_sent_at, :datetime
  end
end
