class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable, :timeoutable, :lockable

  TWO_FACTOR_CODE_EXPIRY = 10.minutes

  has_many :conversations, dependent: :destroy
  has_many :prompts, dependent: :destroy

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

  def effective_prompt(key)
    prompts.find_by(key: key)&.content || Prompt.global(key)
  end

  def issue_two_factor_code!
    self.two_factor_code_salt = SecureRandom.hex(16)
    code = format('%06d', SecureRandom.random_number(1_000_000))
    self.two_factor_code_digest = digest_two_factor_code(code, two_factor_code_salt)
    self.two_factor_code_sent_at = Time.current
    save!
    TwoFactorMailer.code_email(self, code).deliver_later
  end

  def consume_two_factor_code(code)
    return false unless two_factor_code_pending?
    return false unless ActiveSupport::SecurityUtils.secure_compare(two_factor_code_digest, digest_two_factor_code(code.to_s, two_factor_code_salt))

    self.two_factor_code_digest = nil
    self.two_factor_code_salt = nil
    self.two_factor_code_sent_at = nil
    save!
    true
  end

  def two_factor_code_pending?
    two_factor_code_digest.present? && two_factor_code_sent_at.present? && two_factor_code_sent_at + TWO_FACTOR_CODE_EXPIRY > Time.current
  end

  private

  def digest_two_factor_code(code, salt)
    Digest::SHA256.hexdigest("#{code}:#{salt}")
  end
end
