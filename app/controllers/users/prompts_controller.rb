module Users
  class PromptsController < Users::ApplicationController
    def edit
      @prompt = current_user.prompts.find_by(key: 'system') || Prompt.new(key: 'system', user: current_user, content: Prompt.global('system'))
    end

    def update
      @prompt = current_user.prompts.find_by(key: 'system') || current_user.prompts.build(key: 'system')
      if @prompt.update(prompt_params)
        flash[:user] = { notice: 'System prompt was successfully updated.' }
        redirect_to edit_users_prompt_path
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def prompt_params
      params.require(:prompt).permit(:content)
    end
  end
end
