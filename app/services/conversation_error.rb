module ConversationError
  STOPPED = 'Stopped by user.'
  SERVICE_UNAVAILABLE = 'The service is temporarily unavailable. Please try again in a moment.'
  GENERIC = 'Something went wrong. Please try again.'
  COMPACTION_FAILED = 'Compaction failed.'

  def self.thinking_only(duration_ms)
    seconds = duration_ms.to_i / 1000
    minutes, seconds = seconds.divmod(60)
    duration = minutes.positive? ? "#{minutes}m #{seconds}s" : "#{seconds}s"
    "The model stopped after thinking for #{duration} without producing a response."
  end

  def self.from_failure(stopped:, failure:)
    return STOPPED if stopped
    return SERVICE_UNAVAILABLE if failure.is_a?(OpenAiClient::Error) && OpenAiClient::RETRYABLE_STATUSES.include?(failure.status)
    GENERIC
  end
end
