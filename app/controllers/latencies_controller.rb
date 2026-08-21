require 'net/http'
require 'uri'

class LatenciesController < ApplicationController
  def show
    begin
      start_time = Time.now.to_f

      host = Rails.application.credentials.dig(:openai_api, :host)
      port = Rails.application.credentials.dig(:openai_api, :port)
      url = URI("http://#{host}:#{port}/health")
      response = Net::HTTP.get_response(url)

      latency_ms = ((Time.now.to_f - start_time) * 1000).round

      render json: { latency: latency_ms }
    rescue StandardError => e
      render json: { latency: nil, error: 'Hiding' }, status: 500
    end
  end
end
