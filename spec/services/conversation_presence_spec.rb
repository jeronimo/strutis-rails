require 'rails_helper'

RSpec.describe ConversationPresence do
  let(:conversation_id) { 42 }
  let(:key) { "conversation_presence:viewing:#{conversation_id}" }
  let(:presence) { described_class.new(conversation_id) }

  before { Rails.cache.delete(key) }

  it 'is not viewing until a subscription starts' do
    expect(described_class.viewing?(conversation_id)).to be false
  end

  it 'is viewing between start! and finish!' do
    presence.start!('a')
    expect(described_class.viewing?(conversation_id)).to be true

    presence.finish!('a')
    expect(described_class.viewing?(conversation_id)).to be false
  end

  it 'stays viewing until every subscription has finished' do
    presence.start!('a')
    presence.start!('b')

    presence.finish!('a')
    expect(described_class.viewing?(conversation_id)).to be true

    presence.finish!('b')
    expect(described_class.viewing?(conversation_id)).to be false
  end

  it 'ignores a finish from a subscription that no longer owns the record' do
    presence.start!('new')

    presence.finish!('stale')
    expect(described_class.viewing?(conversation_id)).to be true
  end
end
