def sign_in_user(user)
  Warden.test_mode!
  Warden.on_next_request { |proxy| proxy.set_user(user, scope: :user) }
end

def sign_out_user
  Warden.test_reset!
end

def last_email_code
  ActionMailer::Base.deliveries.last.text_part.decoded[/\d{6}/]
end
