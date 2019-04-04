require 'mail'

RSpec.configure do |config|
  config.include(Mail::Matchers)

  config.before(:each) do
    Mail::TestMailer.deliveries.clear
    Mail.defaults { delivery_method :test }
  end
end

