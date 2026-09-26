module Users
  module TwoFactorStep
    extend ActiveSupport::Concern

    def begin_two_factor(user)
      session[:sign_in_user_id] = user.id
      user.issue_two_factor_code!
      redirect_to user_sign_in_verify_path, status: :see_other
    end
  end
end
