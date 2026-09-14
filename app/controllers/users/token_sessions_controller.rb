module Users
  class TokenSessionsController < ::ApplicationController
    include Users::TwoFactorStep

    def create
      user = User.find_by(authentication_token: params.dig(:user, :authentication_token))
      return redirect_to root_path, status: :see_other unless user&.valid_for_authentication?

      begin_two_factor(user)
    end
  end
end
