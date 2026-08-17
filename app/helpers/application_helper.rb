module ApplicationHelper
  def isolated_importmap_tags(entry_point)
    importmap = Rails.application.config.public_send("#{entry_point}_importmap".to_sym)
    javascript_importmap_tags(entry_point, importmap: importmap)
  end
end
