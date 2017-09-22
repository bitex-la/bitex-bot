require 'spec_helper'

describe BitstampApiWrapper do
  before(:each) do
    BitexBot::Robot.stub(taker: 'bitstamp')
    BitexBot::Robot.stub(taker: BitstampApiWrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_request(:post, "https://www.bitstamp.net/api/v2/balance/btcusd/")
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    BitstampApiWrapper.balance rescue nil # we don't care about the response
  end
end
