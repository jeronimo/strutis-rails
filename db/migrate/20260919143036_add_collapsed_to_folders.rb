class AddCollapsedToFolders < ActiveRecord::Migration[8.1]
  def change
    add_column :folders, :collapsed, :boolean, default: false, null: false
  end
end
