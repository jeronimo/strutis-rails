class SseParser
  attr_reader :usage

  def initialize
    @buffer = +''
    @usage = {}
  end

  def push(chunk)
    @buffer << chunk
    @buffer.gsub!("\r\n", "\n")
    while (separator = @buffer.index("\n\n"))
      event = @buffer[0...separator]
      @buffer = @buffer[(separator + 2)..]
      parse_event(event) { |delta| yield delta }
    end
  end

  def finish
    return if @buffer.strip.empty?
    parse_event(@buffer) { |delta| yield delta }
  end

  private

  def parse_event(event)
    event.each_line do |line|
      next unless line.start_with?('data:')
      data = line[5..].strip
      next if data == '[DONE]'
      json = JSON.parse(data, symbolize_names: true)
      @usage.merge!(json[:usage]) if json[:usage]
      delta = json.dig(:choices, 0, :delta)
      yield delta if delta
    end
  end
end
