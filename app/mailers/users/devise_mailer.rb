module Users
  class DeviseMailer < Devise::Mailer
    layout false

    def reset_password_instructions(record, token, opts = {})
      @token = token
      @user = record
      mail(
        to: @user.email,
        subject: 'Reset your Strutis password'
      )
    end

    def unlock_instructions(record, token, opts = {})
      @token = token
      @user = record
      mail(
        to: @user.email,
        subject: 'Unlock your Strutis account'
      )
    end
  end
end
