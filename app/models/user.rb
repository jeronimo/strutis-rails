class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable, :timeoutable, :lockable, :token_authenticatable

  def self.find_for_token_authentication(authentication_hash)
    where(authentication_hash).first
  end

  def after_token_authentication
    # Optional: clear token after successful authentication for one-time tokens
    # self.authentication_token = nil
    # save(validate: false)
  end
end
