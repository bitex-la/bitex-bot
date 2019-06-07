require 'bundler/setup'
Bundler.setup

require 'bitex_bot/settings'
BitexBot::Settings.load_test

require 'byebug'
require 'database_cleaner'
require 'factory_bot'
require 'faker'
require 'rspec/its'
require 'shoulda/matchers'
require 'timecop'
require 'webmock/rspec'

require 'bitex_bot'
FactoryBot.find_definitions
Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

# Automatically do rake db:test:prepare
ActiveRecord::Migration.maintain_test_schema!

# Transactional fixtures do not work with Selenium tests, because Capybara uses a separate server thread, which the transactions
# would be hidden from. We hence use DatabaseCleaner to truncate our test database.
DatabaseCleaner.strategy = :truncation

RSpec.configure do |config|
  config.include(FactoryBot::Syntax::Methods)
  config.include(Shoulda::Matchers::ActiveModel)
  config.include(Shoulda::Matchers::ActiveRecord)

  config.mock_with :rspec do |mocks|
    mocks.yield_receiver_to_any_instance_implementation_blocks = false
    mocks.syntax = %i[expect should]
  end

  config.expect_with :rspec do |c|
    c.syntax = %i[expect should]
  end

  config.before(:all) do
    BitexBot::Notifier.logger = Logger.new('/dev/null')
  end

  config.before(:each) do
    BitexBot::Robot.stub(:sleep_for)
  end

  config.before(:suite) do
    DatabaseCleaner.clean
  end

  config.after(:each) do
    DatabaseCleaner.clean
    Timecop.return
  end

  config.order = 'random'
end

I18n.enforce_available_locales = false
