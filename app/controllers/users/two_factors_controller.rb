module Users
  class TwoFactorsController < ::ApplicationController
    layout 'devise'
    before_action :require_sign_in_user

    def new; end

    def create
      if params[:resend].present?
        sign_in_user.issue_two_factor_code!
        return redirect_to user_sign_in_verify_path, status: :see_other
      end

      if sign_in_user.consume_two_factor_code(params[:code])
        session.delete(:sign_in_user_id)
        sign_in(:user, sign_in_user)
        flash[:user] = { notice: t('devise.sessions.signed_in') }
        redirect_to new_conversation_path, status: :see_other
      else
        flash.now[:user] = { alert: t('two_factor.invalid_code') }
        render :new, status: :ok
      end
    end

    def sign_in_user
      @sign_in_user ||= User.find_by(id: session[:sign_in_user_id])
    end

    private

    def require_sign_in_user
      return if sign_in_user
      flash[:user] = { alert: t('two_factor.sign_in_required') }
      redirect_to user_email_sign_in_path, status: :see_other
    end
  end
end
