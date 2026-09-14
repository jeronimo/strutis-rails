module Users
  class DeviseMailer < ::Devise::Mailer
    layout 'mailer'

    def mail(headers = {}, &)
      attachments.inline['logo.webp'] = Rails.root.join('app/assets/images/logo.webp').read
      super
    end

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
