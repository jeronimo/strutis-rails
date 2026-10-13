class CompletionMonitor
  STOP_CHANNEL = 'conversation_stop'
  NOTIFY_TIMEOUT = 5
  HEARTBEAT_EVERY = 10.seconds

  def self.conninfo
    cfg = ActiveRecord::Base.connection_pool.db_config.configuration_hash
    return cfg[:url] if cfg[:url].present?
    { host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: cfg[:username], password: cfg[:password], sslmode: cfg[:sslmode] }.compact
  end

  def self.notify_stop(conversation_id)
    ActiveRecord::Base.connection.transaction do
      ActiveRecord::Base.connection.raw_connection.exec("NOTIFY #{STOP_CHANNEL}, '#{conversation_id.to_i}'")
    end
  end

  def self.start(conversation)
    new(conversation.id).tap(&:start)
  end

  def initialize(conversation_id)
    @conversation_id = conversation_id
    @mutex = Mutex.new
    @requested = false
    @listening = false
    @last_heartbeat = nil
  end

  def stop_requested?
    @mutex.synchronize { @requested }
  end

  def listening?
    @mutex.synchronize { @listening }
  end

  def start
    @thread = Thread.new { watch }
  end

  def stop
    @thread&.kill
    @thread = nil
  end

  private

  def watch
    until stop_requested?
      connect
      @connection.exec("LISTEN #{STOP_CHANNEL}")
      @mutex.synchronize { @listening = true }
      loop do
        payload = nil
        event = @connection.wait_for_notify(NOTIFY_TIMEOUT) { |_event, _pid, data| payload = data }
        if event.nil?
          heartbeat
        elsif payload == @conversation_id.to_s
          @mutex.synchronize { @requested = true }
          return
        end
      end
    end
  rescue PG::Error
    sleep 1
    retry unless stop_requested?
  ensure
    close
  end

  def connect
    close
    @mutex.synchronize { @listening = false }
    @connection = PG.connect(self.class.conninfo)
  end

  def close
    @connection&.close
    @connection = nil
  end

  def heartbeat
    now = Time.current
    return if @last_heartbeat && now - @last_heartbeat < HEARTBEAT_EVERY
    @last_heartbeat = now
    @connection.exec_params('UPDATE conversations SET running_at = $1 WHERE id = $2', [ now.iso8601(6), @conversation_id ])
  end
end
