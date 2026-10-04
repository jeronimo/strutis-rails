require 'rails_helper'

RSpec.describe UserChannel, type: :channel do
  let(:user) { User.create!(email: 'user-channel@example.com', password: 'password123') }

  before do
    stub_connection(current_user: user)
  end

  it 'streams from the same stream name turbo broadcasts to' do
    subscription = subscribe

    expect(subscription.streams).to include(user.to_gid_param)
  end
end
