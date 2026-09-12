require 'net/http'

class LatenciesController < ApplicationController
  CACHE_KEY = 'latency_check'
  CACHE_TTL = 1.second
  PING_MUTEX = Mutex.new

  def show
    result = Rails.cache.read(CACHE_KEY) || ping_and_cache
    if result[:latency_ms]
      render json: { latency: result[:latency_ms] }
    else
      render json: { latency: nil, error: result[:error] || 'Health check failed' }, status: 500
    end
  end

  private

  def ping_and_cache
    PING_MUTEX.synchronize do
      cached = Rails.cache.read(CACHE_KEY)
      return cached if cached

      result = begin
        { latency_ms: ping }
      rescue StandardError => e
        Sentry.capture_exception(e)
        Rails.logger.error { "[LatenciesController] #{e.full_message}" }
        { latency_ms: nil, error: e.message }
      end
      Rails.cache.write(CACHE_KEY, result, expires_in: CACHE_TTL)
      result
    end
  end

  def ping
    host = Rails.application.credentials.dig(:openai_api, :host)
    port = Rails.application.credentials.dig(:openai_api, :port)
    http = Net::HTTP.new(host, port)
    http.open_timeout = 1
    http.read_timeout = 1

    start_time = Time.now.to_f
    http.get('/health')
    ((Time.now.to_f - start_time) * 1000).round
  end
end
