class Message < ApplicationRecord
  belongs_to :conversation

  validates :role, :content, presence: true
end
