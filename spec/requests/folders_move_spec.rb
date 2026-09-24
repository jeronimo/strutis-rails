require 'rails_helper'

RSpec.describe 'Folders move', type: :request do
  let(:user) { User.create!(email: 'folder-move-user@example.com', password: 'password123') }

  before do
    sign_in_user(user)
    @a = user.folders.create!(name: 'A', position: 1.0)
    @b = user.folders.create!(name: 'B', position: 2.0)
    @c = user.folders.create!(name: 'C', parent: @a, position: 1.0)
    @d = user.folders.create!(name: 'D', parent: @c, position: 1.0)
  end

  after { sign_out_user }

  def move_folder(folder, parent_id:, prev: nil, following: nil)
    patch "/folders/#{folder.id}/move", params: { parent_id: parent_id, prev_type: prev&.class&.name&.downcase, prev_id: prev&.id, next_type: following&.class&.name&.downcase, next_id: following&.id }.compact, as: :json
  end

  it 'reorders a subfolder within its current parent' do
    sibling = user.folders.create!(name: 'E', parent: @a, position: 2.0)
    move_folder(@c, parent_id: @a.id, following: sibling)
    expect(response).to have_http_status(:ok)
    expect(@c.reload.position).to be < sibling.reload.position
  end

  it 'moves a root folder into a folder' do
    move_folder(@b, parent_id: @a.id)
    expect(response).to have_http_status(:ok)
    expect(@b.reload.parent_id).to eq(@a.id)
  end

  it 'moves a folder back to the root' do
    move_folder(@c, parent_id: nil)
    expect(response).to have_http_status(:ok)
    expect(@c.reload.parent_id).to be_nil
  end

  it 'moves a folder between sibling folders' do
    move_folder(@c, parent_id: @b.id)
    expect(response).to have_http_status(:ok)
    expect(@c.reload.parent_id).to eq(@b.id)
  end

  it 'moves a folder up to a grandparent' do
    move_folder(@d, parent_id: @a.id)
    expect(response).to have_http_status(:ok)
    expect(@d.reload.parent_id).to eq(@a.id)
  end

  it 'rejects moving a folder into its own descendant' do
    move_folder(@a, parent_id: @d.id)
    expect(response).to have_http_status(:unprocessable_content)
    expect(@a.reload.parent_id).to be_nil
  end

  it 'rejects moving a folder into itself' do
    move_folder(@a, parent_id: @a.id)
    expect(response).to have_http_status(:unprocessable_content)
    expect(@a.reload.parent_id).to be_nil
  end
end
