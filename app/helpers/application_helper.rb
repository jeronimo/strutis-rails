module ApplicationHelper
  def isolated_importmap_tags(entry_point)
    importmap = Rails.application.config.public_send("#{entry_point}_importmap".to_sym)
    javascript_importmap_tags(entry_point, importmap: importmap)
  end

  def format_ms(ms)
    ms >= 1000 ? format('%.1fs', ms / 1000.0) : "#{ms} ms"
  end

  def message_breakdown(message)
    inference = message.inference_ms || 0
    transport = (message.latency_ms || 0) - inference
    parts = []
    parts << "thinking #{format_ms(inference)}" if inference.positive?
    parts << "transport #{format_ms(transport)}" if transport.positive?
    parts.empty? ? format_ms(message.latency_ms) : "#{parts.join(' · ')} — #{format_ms(message.latency_ms)}"
  end

  def render_message_markdown(content)
    sanitize(Commonmarker.to_html(content.to_s, plugins: { syntax_highlighter: nil }))
  end
end
