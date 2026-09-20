require 'rails_helper'

RSpec.describe Folder, type: :model do
  let(:user) { User.create!(email: 'folder-user@example.com', password: 'password123') }
  let(:parent) { user.folders.create!(name: 'Parent') }
  let(:folder) { user.folders.create!(name: 'Child', parent: parent) }

  describe '#destroy' do
    it 'moves conversations to the parent folder' do
      conversation = user.conversations.create!(model: 'test-model', folder_id: folder.id)
      folder.destroy!

      expect(conversation.reload.folder_id).to eq(parent.id)
    end

    it 'moves soft-deleted conversations to the parent folder' do
      conversation = user.conversations.create!(model: 'test-model', folder_id: folder.id)
      conversation.destroy

      folder.destroy!

      expect(Conversation.with_deleted.find(conversation.id).folder_id).to eq(parent.id)
    end

    it 'moves conversations from descendant folders to the parent folder' do
      grandchild = user.folders.create!(name: 'Grandchild', parent: folder)
      conversation = user.conversations.create!(model: 'test-model', folder_id: grandchild.id)
      folder.destroy!

      expect(conversation.reload.folder_id).to eq(parent.id)
      expect(Folder.exists?(grandchild.id)).to be false
    end

    it 'leaves conversations unfiled when the folder has no parent' do
      root = user.folders.create!(name: 'Root')
      conversation = user.conversations.create!(model: 'test-model', folder_id: root.id)
      root.destroy!

      expect(conversation.reload.folder_id).to be_nil
    end
  end
end
