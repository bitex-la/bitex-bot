source 'https://rubygems.org'

# Specify your gem's dependencies in bitex_bot.gemspec
gem 'activerecord'
gem 'hashie', '~> 3.5.4'
gem 'mail'
gem 'mysql2'
gem 'sqlite3', '~> 1.3.6'
gem 'bitex', git: 'https://github.com/bitex-la/bitex-sdk-ruby'
gem 'bitstamp', git: 'https://github.com/bitex-la/bitstamp', branch: 'update-lib'
gem 'itbit'
gem 'kraken_client', '~> 1.2.1'

group :test, :development do
  gem 'bundler'
  gem 'rake'
  gem 'byebug'
  gem 'database_cleaner'
  gem 'factory_bot'
  gem 'faker'
  gem 'rspec'
  gem 'rspec-its'
  gem 'rspec-mocks'
  gem 'rspec_junit_formatter'
  gem 'rubocop'
  gem 'shoulda-matchers'
  gem 'timecop'
  gem 'vcr'
  gem 'webmock'

  gem 'capistrano', '~> 3.4.0', require: false
  gem 'capistrano-bundler', '~> 1.1.2', require: false
  gem 'capistrano-rbenv', '~> 2.0.2', require: false
  gem 'capistrano-rbenv-install', require: false
end
