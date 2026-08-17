# Set up separate importmaps for isolated sections
Rails.application.config.application_importmap = Importmap::Map.new
Rails.application.config.application_importmap.draw(Rails.root.join('config/importmap/application.rb'))

Rails.application.config.admin_importmap = Importmap::Map.new
Rails.application.config.admin_importmap.draw(Rails.root.join('config/importmap/admin.rb'))
