require 'rails_helper'

RSpec.describe CompletionSignal do
  let(:conversation_id) { 42 }
  let(:alive_key) { "conversation_completion:alive:#{conversation_id}" }

  before do
    Rails.cache.delete("conversation_completion:stop:#{conversation_id}")
    Rails.cache.delete(alive_key)
  end

  describe 'stop request' do
    it 'is consumed exactly once' do
      described_class.request_stop(conversation_id)
      expect(described_class.new(conversation_id).stopped?).to be true
      expect(described_class.new(conversation_id).stopped?).to be false
    end

    it 'is sticky once seen' do
      described_class.request_stop(conversation_id)
      signal = described_class.new(conversation_id)
      expect(signal.stopped?).to be true
      expect(signal.stopped?).to be true
    end

    it 'is not stopped when no request was made' do
      expect(described_class.new(conversation_id).stopped?).to be false
    end
  end

  describe 'alive record' do
    it 'exists between start! and finish!' do
      signal = described_class.new(conversation_id)
      expect(described_class.alive?(conversation_id)).to be false
      signal.start!
      expect(described_class.alive?(conversation_id)).to be true
      signal.finish!
      expect(described_class.alive?(conversation_id)).to be false
    end

    it 're-arms the alive record when stopped? runs after the rewrite interval' do
      signal = described_class.new(conversation_id)
      now = 0.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }
      signal.start!
      now = described_class::ALIVE_REWRITE_EVERY + 1

      expect(Rails.cache).to receive(:write).with(alive_key, true, expires_in: described_class::ALIVE_EXPIRES_AFTER)
      expect(signal.stopped?).to be false
    end

    it 'leaves the alive record alone when stopped? runs before the rewrite interval' do
      signal = described_class.new(conversation_id)
      now = 0.0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }
      signal.start!
      now = described_class::ALIVE_REWRITE_EVERY - 1

      expect(Rails.cache).not_to receive(:write)
      expect(signal.stopped?).to be false
    end
  end
end
