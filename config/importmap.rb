# Main importmap file - delegates to isolated maps
# Application importmap
Rails.application.config.application_importmap.draw(Rails.root.join('config/importmap/application.rb'))

# Admin importmap
Rails.application.config.admin_importmap.draw(Rails.root.join('config/importmap/admin.rb'))
