class ApplicationMailer < ActionMailer::Base
  default from: Rails.application.credentials.dig(:mailer, :from) || 'noreply@strutis.ai'
  layout 'mailer'

  def mail(headers = {}, &)
    attachments.inline['logo.webp'] = Rails.root.join('app/assets/images/logo.webp').read
    super
  end
end
