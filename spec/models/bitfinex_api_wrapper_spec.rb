require 'spec_helper'

describe BitfinexApiWrapper do
  before(:each) do
    BitexBot::Robot.stub(taker: 'bitfinex')
    BitexBot::Robot.stub(taker: BitfinexApiWrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_request(:post, "https://api.bitfinex.com/v1/balances")
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    stub_request(:post, "https://api.bitfinex.com/v1/account_infos")
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    BitfinexApiWrapper.balance rescue nil # we don't care about the response
  end
end
