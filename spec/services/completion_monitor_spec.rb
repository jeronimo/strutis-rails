require 'rails_helper'

RSpec.describe CompletionMonitor do
  let(:conversation_id) { 987_654 }
  let(:other_id) { 123_456 }

  def notify(id)
    @notifier ||= PG.connect(described_class.conninfo)
    @notifier.exec("NOTIFY #{described_class::STOP_CHANNEL}, '#{id}'")
  end

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.02
    end
    true
  end

  after { @notifier&.close }

  it 'flags the stop once a notification for its conversation id arrives' do
    monitor = described_class.new(conversation_id).tap(&:start)
    expect(wait_until { monitor.listening? }).to be true

    notify(conversation_id)

    expect(wait_until { monitor.stop_requested? }).to be true
  ensure
    monitor&.stop
  end

  it 'ignores notifications for other conversation ids' do
    monitor = described_class.new(conversation_id).tap(&:start)
    expect(wait_until { monitor.listening? }).to be true

    notify(other_id)
    sleep 0.3

    expect(monitor.stop_requested?).to be false
  ensure
    monitor&.stop
  end
end
