class Folder < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: 'Folder', optional: true
  has_many :children, class_name: 'Folder', foreign_key: :parent_id, dependent: :destroy
  has_many :conversations, dependent: :nullify

  validates :name, presence: true

  def descendant_ids
    children.flat_map { |child| [ child.id, *child.descendant_ids ] }
  end

  def ancestor_of?(folder)
    folder.id == id || descendant_ids.include?(folder.id)
  end
end
