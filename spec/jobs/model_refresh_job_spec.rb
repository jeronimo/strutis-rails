require 'rails_helper'

RSpec.describe ModelRefreshJob do
  before do
    allow(OpenAiClient).to receive(:credentials).and_return({ host: 'localhost', port: 8080, key: 'test-key' })
    Rails.cache.delete(ModelCatalog::CACHE_KEY)
  end

  it 'caches the fetched model list' do
    stub_request(:get, 'http://localhost:8080/v1/models').to_return(status: 200, body: '{"data":[{"id":"m1","context_length":100}]}')

    described_class.perform_now

    expect(Rails.cache.read(ModelCatalog::CACHE_KEY)[:data]).to eq([ { id: 'm1', context_length: 100 } ])
  end

  it 'keeps the cached list when the fetch returns no models' do
    Rails.cache.write(ModelCatalog::CACHE_KEY, { data: [ { id: 'm1' } ], fetched_at: Time.now - 700 })
    stub_request(:get, 'http://localhost:8080/v1/models').to_return(status: 200, body: '{"data":[]}')

    described_class.perform_now

    expect(Rails.cache.read(ModelCatalog::CACHE_KEY)[:data]).to eq([ { id: 'm1' } ])
  end
end
