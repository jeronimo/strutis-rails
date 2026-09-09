# frozen_string_literal: true

module Admins
  class PromptsController < Admins::ApplicationController
    before_action :ensure_builtin_prompts, only: [ :index ]

    def index
      @prompts = Prompt.where(user_id: nil)
    end

    def new
      @prompt = Prompt.new
    end

    def create
      @prompt = Prompt.new(prompt_params.merge(user_id: nil))
      if @prompt.save
        redirect_to admins_prompts_path, notice: 'Prompt was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @prompt = find_prompt
    end

    def update
      @prompt = find_prompt
      if @prompt.update(prompt_params)
        redirect_to admins_prompts_path, notice: 'Prompt was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      find_prompt.destroy
      redirect_to admins_prompts_path, notice: 'Prompt was successfully deleted.'
    end

    private

    def ensure_builtin_prompts
      Prompt::DEFAULTS.each do |key, content|
        Prompt.find_or_create_by!(key: key, user_id: nil) { |prompt| prompt.content = content }
      end
    end

    def find_prompt
      Prompt.where(user_id: nil).find(params[:id])
    end

    def prompt_params
      params.require(:prompt).permit(:key, :content)
    end
  end
end
