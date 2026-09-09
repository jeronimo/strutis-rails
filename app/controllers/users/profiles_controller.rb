module Users
  class ProfilesController < Users::ApplicationController
    def edit
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(profile_params)
        redirect_to edit_users_profile_path, notice: 'Profile was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:user).permit(:full_name, :password, :password_confirmation)
    end
  end
end
