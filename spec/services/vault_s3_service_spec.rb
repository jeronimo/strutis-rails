require 'rails_helper'
require "active_storage/service/vault_s3_service"

RSpec.describe ActiveStorage::Service::VaultS3Service do
  let(:service) do
    described_class.new(bucket: 'strutis-rails', region: 'us-east-1', endpoint: 'http://10.100.11.11:9000',
      force_path_style: true, access_key_id: 'key', secret_access_key: 'secret')
  end

  def url(key)
    service.url(key, expires_in: 1.hour, filename: ActiveStorage::Filename.new('file.png'), disposition: nil, content_type: 'image/png')
  end

  it 'returns a presigned url to the s3 endpoint outside production' do
    expect(url('abc123/file.png')).to start_with('http://10.100.11.11:9000/strutis-rails/abc123/file.png')
    expect(url('abc123/file.png')).to include('X-Amz-Signature=')
  end

  it 'returns the files url in production' do
    allow(Rails.env).to receive(:production?).and_return(true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FILES_HOST').and_return('files.strutis.ai')
    expect(url('abc123/file.png')).to eq('https://files.strutis.ai/abc123/file.png')
  end
end
