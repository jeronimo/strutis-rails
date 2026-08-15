require 'net/http'
require 'uri'

class LatenciesController < ApplicationController
  def show
    begin
      start_time = Time.now.to_f

      url = URI('http://10.10.10.10:8000/health')
      response = Net::HTTP.get_response(url)

      latency_ms = ((Time.now.to_f - start_time) * 1000).round

      render json: { latency: latency_ms }
    rescue StandardError => e
      render json: { latency: nil, error: e.message }, status: 500
    end
  end
end
