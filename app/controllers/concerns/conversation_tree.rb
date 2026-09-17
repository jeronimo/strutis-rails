module ConversationTree
  extend ActiveSupport::Concern

  MIN_POSITION_GAP = 0.000001

  private

  def render_tree
    load_conversations
    render turbo_stream: turbo_stream.replace('conversation-tree', partial: 'conversations/tree', locals: { conversations: @conversations, folders: @folders, active_public_id: params[:active_conversation_public_id].presence })
  end

  def move_tree_item(record, attribute:, parent_id:, prev:, following:)
    position = position_between(prev, following)
    if position.nil?
      renormalize_tree_level(parent_id)
      prev.reload if prev
      following.reload if following
      position = position_between(prev, following)
    end
    record.update_columns(attribute => parent_id, position: position)
    render_tree
  end

  def find_tree_item(type, id)
    return nil if id.blank?

    type == 'folder' ? current_user.folders.find(id) : current_user.conversations.find_by!(public_id: id)
  end

  def tree_level_items(parent_id)
    conversations = current_user.conversations.where(folder_id: parent_id).order(:position, :id).to_a
    folders = current_user.folders.where(parent_id: parent_id).order(:position, :id).to_a
    (conversations + folders).sort_by { |item| [ item.position, item.id ] }
  end

  def first_tree_position(parent_id)
    first = tree_level_items(parent_id).first
    first ? first.position - 1 : 1.0
  end

  def last_tree_position(parent_id)
    last = tree_level_items(parent_id).last
    last ? last.position + 1 : 1.0
  end

  def position_between(previous, following)
    return 1.0 if previous.nil? && following.nil?
    return following.position - 1 if previous.nil?
    return previous.position + 1 if following.nil?
    return nil if following.position - previous.position < MIN_POSITION_GAP

    (previous.position + following.position) / 2
  end

  def renormalize_tree_level(parent_id)
    tree_level_items(parent_id).each_with_index do |item, index|
      item.update_column(:position, index + 1)
    end
  end
end
