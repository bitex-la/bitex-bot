require 'webmock/rspec'

RSpec.configure do |config|
  config.before(:each) do
   WebMock.reset!
   WebMock.disable_net_connect!(allow_localhost: true)
  end
end
