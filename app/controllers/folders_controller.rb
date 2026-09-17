class FoldersController < ApplicationController
  layout 'user'
  include ConversationTree
  before_action :authenticate_user!
  before_action :load_conversations

  def create
    folder = current_user.folders.create!(name: create_params[:name].to_s.strip, parent: find_tree_item('folder', create_params[:parent_id]), position: last_tree_position(create_params[:parent_id].presence))
    render_tree
  end

  def update
    folder = current_user.folders.find(params[:id])
    folder.update!(name: update_params[:name].to_s.strip)
    render_tree
  end

  def destroy
    folder = current_user.folders.find(params[:id])
    folder.destroy!
    render_tree
  end

  def move
    folder = current_user.folders.find(params[:id])
    parent_id = move_params[:parent_id].presence
    if parent_id.present? && current_user.folders.find(parent_id).ancestor_of?(folder)
      head :unprocessable_entity
      return
    end
    move_tree_item(folder, attribute: :parent_id, parent_id: parent_id, prev: find_tree_item(move_params[:prev_type], move_params[:prev_id]), following: find_tree_item(move_params[:next_type], move_params[:next_id]))
  end

  private

  def create_params
    params.permit(:name, :parent_id)
  end

  def update_params
    params.permit(:name)
  end

  def move_params
    params.permit(:parent_id, :prev_type, :prev_id, :next_type, :next_id)
  end
end
