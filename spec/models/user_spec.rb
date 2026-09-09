require 'rails_helper'

RSpec.describe User, type: :model do
  let(:user) { User.create!(email: 'user@example.com', password: 'password123') }

  describe '#effective_prompt' do
    it 'returns the global content without a user prompt' do
      Prompt.create!(key: 'system', user_id: nil, content: 'global content')
      expect(user.effective_prompt('system')).to eq('global content')
    end

    it 'returns the user content when present' do
      Prompt.create!(key: 'system', user_id: nil, content: 'global content')
      Prompt.create!(key: 'system', user: user, content: 'mine')
      expect(user.effective_prompt('system')).to eq('mine')
    end

    it 'returns an empty string when there is no prompt at all' do
      expect(user.effective_prompt('system')).to eq('')
    end
  end
end
