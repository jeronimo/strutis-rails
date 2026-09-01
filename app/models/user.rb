class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable, :timeoutable, :lockable

  has_many :conversations, dependent: :destroy

  before_create { self.authentication_token = SecureRandom.hex(20) if authentication_token.blank? }

  def self.find_for_authentication(conditions)
    if conditions[:authentication_token].present?
      find_by(authentication_token: conditions[:authentication_token])
    else
      super
    end
  end

  def password_required?
    !persisted? || password.present? || password_confirmation.present?
  end
end
