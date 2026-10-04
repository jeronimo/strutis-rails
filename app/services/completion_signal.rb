class CompletionSignal
  STOP_REQUEST_EXPIRES_AFTER = 20.minutes
  ALIVE_EXPIRES_AFTER = 30.seconds
  ALIVE_REWRITE_EVERY = 10.seconds

  def self.request_stop(conversation_id)
    new(conversation_id).request_stop
  end

  def self.alive?(conversation_id)
    new(conversation_id).alive?
  end

  def initialize(conversation_id)
    @conversation_id = conversation_id
    @stopped = false
    @last_alive = nil
  end

  def request_stop
    Rails.cache.write(stop_key, true, expires_in: STOP_REQUEST_EXPIRES_AFTER)
  end

  def alive?
    Rails.cache.exist?(alive_key)
  end

  def start!
    @last_alive = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Rails.cache.write(alive_key, true, expires_in: ALIVE_EXPIRES_AFTER)
  end

  def finish!
    Rails.cache.delete(alive_key)
  end

  def stopped?
    return true if @stopped
    rewrite_alive
    @stopped = Rails.cache.read(stop_key).present?
    Rails.cache.delete(stop_key) if @stopped
    @stopped
  end

  private

  def rewrite_alive
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @last_alive && now - @last_alive < ALIVE_REWRITE_EVERY
    @last_alive = now
    Rails.cache.write(alive_key, true, expires_in: ALIVE_EXPIRES_AFTER)
  end

  def stop_key
    "conversation_completion:stop:#{@conversation_id}"
  end

  def alive_key
    "conversation_completion:alive:#{@conversation_id}"
  end
end
