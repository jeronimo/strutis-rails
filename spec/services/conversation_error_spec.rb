require 'rails_helper'

RSpec.describe ConversationError do
  describe '.from_failure' do
    it 'returns the stopped message when the turn was stopped' do
      expect(described_class.from_failure(stopped: true, failure: nil)).to eq('Stopped by user.')
    end

    it 'returns the service unavailable message for a retryable client error' do
      failure = OpenAiClient::Error.new('boom', status: 503)
      expect(described_class.from_failure(stopped: false, failure:)).to eq('The service is temporarily unavailable. Please try again in a moment.')
    end

    it 'returns the generic message for a non-retryable client error' do
      failure = OpenAiClient::Error.new('boom', status: 400)
      expect(described_class.from_failure(stopped: false, failure:)).to eq('Something went wrong. Please try again.')
    end

    it 'returns the generic message when there is no failure' do
      expect(described_class.from_failure(stopped: false, failure: nil)).to eq('Something went wrong. Please try again.')
    end
  end

  describe '.thinking_only' do
    it 'formats sub-minute durations in seconds' do
      expect(described_class.thinking_only(45_000)).to eq('The model stopped after thinking for 45s without producing a response.')
    end

    it 'formats durations over a minute in minutes and seconds' do
      expect(described_class.thinking_only(125_000)).to eq('The model stopped after thinking for 2m 5s without producing a response.')
    end
  end
end
