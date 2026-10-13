source 'https://rubygems.org'

gem 'json'
gem 'rails' # When #57517 (connection_lock) ships: delete config/initializers/pg_connection_lock.rb, set `connection_lock: monitor` in database.yml
gem 'propshaft'
gem 'pg' # Do NOT pin below 1.7.0: 1.6.x silently corrupts query results (ged/ruby-pg#751); interim race fix lives in config/initializers/pg_connection_lock.rb
gem 'puma'
gem 'importmap-rails'
gem 'turbo-rails'
gem 'stimulus-rails'
gem 'bootsnap', require: false
gem 'kamal', require: false
gem 'thruster', require: false
gem 'solid_queue'
gem 'solid_cache'
gem 'solid_cable'
gem 'devise'
gem 'sentry-rails'
gem 'haml'
gem 'haml-rails'
gem 'commonmarker'
gem 'aws-sdk-s3', require: false

group :development, :test do
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'
  gem 'bundler-audit', require: false
  gem 'brakeman', require: false
  gem 'rubocop-rails-omakase', require: false
  gem 'rspec-rails'
  gem 'haml-lint'
  gem 'pry'
  gem 'webmock', require: false
end

group :development do
  gem 'web-console'
end
