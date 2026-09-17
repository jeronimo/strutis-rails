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
    html = Commonmarker.to_html(content.to_s, plugins: { syntax_highlighter: nil })
    html = html.gsub(%r{<a\b}, '<a target="_blank" rel="noopener"')
    attributes = Rails::HTML::Concern::Scrubber::SafeList::DEFAULT_ALLOWED_ATTRIBUTES.to_a + %w[target rel]
    sanitize(html, tags: %w[p br strong em del a ul ol li code pre blockquote h1 h2 h3 h4 h5 h6 hr img table thead tbody tr th td], attributes: attributes)
  end

  def conversation_tree(folders, conversations)
    folders_by_parent = folders.group_by { |folder| folder.parent_id }
    conversations_by_folder = conversations.group_by { |conversation| conversation.folder_id }
    build_tree_level(folders_by_parent, conversations_by_folder, nil)
  end

  def render_tree_item(node, active_public_id:)
    if node[:folder]
      render 'folders/folder', folder: node[:folder], children: node[:children], active_public_id: active_public_id
    else
      conversation = node[:conversation]
      render 'conversations/link', conversation: conversation, active: conversation.public_id == active_public_id
    end
  end

  def render_flash(namespace)
    return unless flash[namespace]

    safe_join(flash[namespace].map do |type, message|
      content_tag(:div, message, class: "alert alert-#{type == 'notice' ? 'success' : 'danger'}")
    end)
  end

  private

  def build_tree_level(folders_by_parent, conversations_by_folder, parent_id)
    merge_tree_items(folders_by_parent[parent_id] || [], conversations_by_folder[parent_id] || [])
      .map do |item|
        item.is_a?(Folder) ? { folder: item, children: build_tree_level(folders_by_parent, conversations_by_folder, item.id) } : { conversation: item }
      end
  end

  def merge_tree_items(folders, conversations)
    (folders + conversations).sort_by { |item| [ item.position, item.id ] }
  end
end
