class TwoFactorMailer < ApplicationMailer
  def code_email(user, code)
    @user = user
    @code = code
    @expiry_minutes = (User::TWO_FACTOR_CODE_EXPIRY / 1.minute).to_i
    mail(to: user.email, subject: 'Your Strutis sign-in code')
  end
end
