require 'rails_helper'

RSpec.describe Message, type: :model do
  let(:user) { User.create!(email: 'message-user@example.com', password: 'password123') }
  let(:conversation) { user.conversations.create!(model: 'test-model') }

  before { ActiveStorage::Current.url_options = { host: 'test.host' } }

  def upload(filename, content_type)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(filename), filename: filename, content_type: content_type)
  end

  describe '#prompt_entries' do
    it 'returns the plain entry for messages without image attachments' do
      message = conversation.messages.create!(role: 'user', content: 'hello')
      expect(message.prompt_entries(image_input: true)).to eq([ { role: 'user', content: 'hello' } ])
    end

    it 'returns the plain entry with text url lines when image input is disabled' do
      message = conversation.messages.create!(role: 'user', content: 'hello')
      message.attachments.attach(upload('one.png', 'image/png'))

      entries = message.prompt_entries(image_input: false)
      expect(entries.size).to eq(1)
      expect(entries[0][:content]).to include('one.png')
    end

    it 'splits one image per entry with the text only on the first entry' do
      message = conversation.messages.create!(role: 'user', content: 'describe')
      first = upload('one.png', 'image/png')
      second = upload('two.png', 'image/png')
      message.attachments.attach([ first, second ])

      entries = message.prompt_entries(image_input: true)
      expect(entries.size).to eq(2)
      expect(entries[0][:content].map { |part| part[:type] }).to eq([ 'text', 'image_url' ])
      expect(entries[0][:content][0][:text]).to eq('describe')
      expect(entries[0][:content][1][:image_url][:url]).to end_with('/one.png')
      expect(entries[1][:content].map { |part| part[:type] }).to eq([ 'image_url' ])
      expect(entries[1][:content][0][:image_url][:url]).to end_with('/two.png')
    end

    it 'does not split non-user messages' do
      message = conversation.messages.create!(role: 'assistant', content: 'reply')
      message.attachments.attach(upload('one.png', 'image/png'))

      travel_to Time.utc(2026, 1, 1) do
        expect(message.prompt_entries(image_input: true)).to eq([ message.to_prompt_entry ])
      end
    end
  end
end
