module Users
  class TwoFactorsController < ::ApplicationController
    layout 'devise'
    before_action :require_pending_user

    def new; end

    def create
      if params[:resend].present?
        pending_user.issue_two_factor_code!
        return redirect_to user_sign_in_verify_path, status: :see_other
      end

      if pending_user.consume_two_factor_code(params[:code])
        session.delete(:pending_two_factor_user_id)
        sign_in(:user, pending_user)
        flash[:user] = { notice: t('devise.sessions.signed_in') }
        redirect_to new_conversation_path, status: :see_other
      else
        flash.now[:user] = { alert: t('two_factor.invalid_code') }
        render :new, status: :ok
      end
    end

    def pending_user
      @pending_user ||= User.find_by(id: session[:pending_two_factor_user_id])
    end

    private

    def require_pending_user
      redirect_to user_email_sign_in_path, status: :see_other unless pending_user
    end
  end
end
