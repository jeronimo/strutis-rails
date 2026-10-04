require 'rails_helper'

RSpec.describe ConversationChannel, type: :channel do
  let(:user) { User.create!(email: 'channel-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  before do
    stub_connection(current_user: user)
  end

  it 'clears unread on subscribe and broadcasts the hidden badge' do
    conversation.update_column(:unread, true)

    subscribe public_id: conversation.public_id

    expect(conversation.reload.unread).to be false
    message = ActiveSupport::JSON.decode(broadcasts(user.to_gid_param).last).to_s
    expect(message).to include("conversation-unread-#{conversation.public_id}")
    expect(message).to include('d-none')
  end

  it 'clears unread set by the job after the subscription was opened' do
    subscribe public_id: conversation.public_id
    conversation.update_column(:unread, true)

    perform :read

    expect(conversation.reload.unread).to be false
  end

  it 'ignores read when there is nothing unread' do
    subscribe public_id: conversation.public_id

    expect { perform :read }.not_to raise_error
    expect(conversation.reload.unread).to be false
  end
end
