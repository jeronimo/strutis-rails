# frozen_string_literal: true

module Admins
  class UsersController < Admins::ApplicationController
    before_action :find_user, only: [ :show, :edit, :update, :destroy ]

    def index
      @users = User.order(created_at: :desc)
    end

    def show
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      if @user.save
        flash[:admin] = { notice: 'User was successfully created.' }
        redirect_to admins_users_path
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @user.update(user_params)
        flash[:admin] = { notice: 'User was successfully updated.' }
        redirect_to admins_users_path
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @user.destroy
      flash[:admin] = { notice: 'User was successfully destroyed.' }
      redirect_to admins_users_path
    end

    private

    def find_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:full_name, :email, :password, :password_confirmation)
    end
  end
end
