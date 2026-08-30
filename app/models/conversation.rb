class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, -> { order(:id) }, dependent: :destroy

  before_create { self.public_id = SecureRandom.hex(16) }

  validates :model, presence: true
end
