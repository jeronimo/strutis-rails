require 'rails_helper'

RSpec.describe Prompt, type: :model do
  describe '.global' do
    it 'returns the content of the global prompt' do
      Prompt.create!(key: 'system', user_id: nil, content: 'global content')
      expect(Prompt.global('system')).to eq('global content')
    end

    it 'returns an empty string when there is no global prompt' do
      expect(Prompt.global('system')).to eq('')
    end
  end

  describe 'validations' do
    it 'requires a key' do
      prompt = Prompt.new(content: 'content')
      expect(prompt).not_to be_valid
      expect(prompt.errors[:key]).to be_present
    end

    it 'requires content' do
      prompt = Prompt.new(key: 'system')
      expect(prompt).not_to be_valid
      expect(prompt.errors[:content]).to be_present
    end
  end
end
