require 'rails_helper'

RSpec.describe OpenAiClient do
  before do
    allow(described_class).to receive(:credentials).and_return({ host: 'localhost', port: 8080, key: 'test-key' })
    stub_const('OpenAiClient::RETRY_WAITS', [ 0 ])
  end

  describe 'retries' do
    it 'retries a refused connection until the service responds' do
      stub_request(:get, 'http://localhost:8080/v1/models')
        .to_raise(Errno::ECONNREFUSED).then
        .to_return(status: 200, body: '{"data":[]}')

      expect(described_class.new.get('/v1/models')).to eq({ data: [] })
      expect(a_request(:get, 'http://localhost:8080/v1/models')).to have_been_made.times(2)
    end

    it 'retries retryable http statuses' do
      stub_request(:get, 'http://localhost:8080/v1/tools')
        .to_return(status: 503, body: 'unavailable').then
        .to_return(status: 200, body: '{"data":[]}')

      expect(described_class.new.get('/v1/tools')).to eq({ data: [] })
    end

    it 'raises the original error after exhausting retries' do
      stub_request(:get, 'http://localhost:8080/v1/tools').to_raise(Errno::ECONNREFUSED)

      expect { described_class.new.get('/v1/tools') }.to raise_error(Errno::ECONNREFUSED)
      expect(a_request(:get, 'http://localhost:8080/v1/tools')).to have_been_made.times(2)
    end

    it 'does not retry non-retryable statuses' do
      stub_request(:get, 'http://localhost:8080/v1/tools').to_return(status: 500, body: '{"error":{"message":"boom"}}')

      expect { described_class.new.get('/v1/tools') }.to raise_error(OpenAiClient::Error, /boom/)
      expect(a_request(:get, 'http://localhost:8080/v1/tools')).to have_been_made.times(1)
    end

    it 'waits follow the configured retry schedule' do
      stub_const('OpenAiClient::RETRY_WAITS', [ 3, 6 ])
      client = described_class.new
      waits = []
      allow(client).to receive(:sleep) { |seconds| waits << seconds }
      stub_request(:get, 'http://localhost:8080/v1/tools').to_raise(Errno::ECONNREFUSED)

      expect { client.get('/v1/tools') }.to raise_error(Errno::ECONNREFUSED)

      expect(waits).to eq([ 3, 6 ])
    end
  end

  describe '#post_stream' do
    it 'yields raw chunks' do
      stub_request(:post, 'http://localhost:8080/v1/chat/completions')
        .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: "data: [DONE]\n\n")
      chunks = []

      described_class.new.post_stream('/v1/chat/completions', {}) { |chunk| chunks << chunk }

      expect(chunks.join).to eq("data: [DONE]\n\n")
    end

    it 'raises Stopped when should_stop fires' do
      stub_request(:post, 'http://localhost:8080/v1/chat/completions')
        .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: "data: x\n\n")

      expect { described_class.new.post_stream('/v1/chat/completions', {}, should_stop: -> { true }) { |chunk| } }.to raise_error(OpenAiClient::Stopped)
    end

    it 'aborts a stream that exceeds the maximum duration' do
      stub_const('OpenAiClient::STREAM_MAX_DURATION', 0)
      stub_request(:post, 'http://localhost:8080/v1/chat/completions')
        .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: "data: x\n\n")

      expect { described_class.new.post_stream('/v1/chat/completions', {}) { |chunk| } }.to raise_error(OpenAiClient::Error, /maximum duration/)
    end

    it 'watchdog closes the connection once the stop request lands' do
      stub_const('OpenAiClient::STOP_WITHIN', 0.01)
      stopped = false
      http = instance_double(Net::HTTP)
      expect(http).to receive(:finish).at_least(:once)

      thread = described_class.new.send(:watch_stop, http, -> { stopped })
      stopped = true
      sleep 0.1
      thread.kill
    end
  end
end
