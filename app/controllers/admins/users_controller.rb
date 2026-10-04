# frozen_string_literal: true

module Admins
  class UsersController < Admins::ApplicationController
    before_action :find_user, only: [ :show, :edit, :update, :destroy ]

    def index
      @users = User.order(created_at: :desc)
      @usage = @users.to_h { |user| [ user.id, { requests: 0, total_tokens: 0 } ] }
      usage_summary.each do |row|
        @usage[row.user_id] = { requests: row.requests.to_i, total_tokens: row.total_tokens.to_i }
      end
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
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @user.update(user_params)
        flash[:admin] = { notice: 'User was successfully updated.' }
        redirect_to admins_users_path
      else
        render :edit, status: :unprocessable_content
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

    def usage_summary
      table = Message.arel_table
      conversation = Conversation.arel_table
      Message.joins(conversation: :user)
        .where.not(prompt_tokens: nil)
        .reorder(nil)
        .group(conversation[:user_id])
        .select(
          conversation[:user_id],
          table[:id].count.as('requests'),
          (table[:prompt_tokens].sum + table[:completion_tokens].sum).as('total_tokens')
        )
    end

    def user_params
      params.require(:user).permit(:full_name, :email, :password, :password_confirmation)
    end
  end
end
