class ToolCallAccumulator
  def initialize
    @calls = {}
  end

  def add(delta_tool_calls)
    return unless delta_tool_calls
    delta_tool_calls.each do |delta|
      call = @calls[delta[:index]] ||= { id: nil, type: 'function', name: nil, arguments: +'' }
      call[:id] = delta[:id] if delta[:id]
      call[:type] = delta[:type] if delta[:type]
      call[:name] = delta.dig(:function, :name) if delta.dig(:function, :name)
      call[:arguments] << delta.dig(:function, :arguments) if delta.dig(:function, :arguments)
    end
  end

  def normalized
    @calls.values.map { |call| { id: call[:id], type: call[:type], function: { name: call[:name], arguments: call[:arguments] } } }
  end
end
