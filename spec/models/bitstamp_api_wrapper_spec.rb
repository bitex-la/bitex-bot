require 'spec_helper'

describe BitstampApiWrapper do
  before(:each) do
    BitexBot::Robot.stub(taker: 'bitstamp')
    BitexBot::Robot.stub(taker: BitstampApiWrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_request(:post, 'https://www.bitstamp.net/api/v2/balance/btcusd/')
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    BitstampApiWrapper.balance rescue nil # we don't care about the response
  end

  it 'raises OrderNotFound error on bitstamp errors' do
    Bitstamp.orders.stub(:buy) do
      raise BitexBot::OrderNotFound
    end

    expect do
      BitstampApiWrapper.place_order(:buy, 10, 100)
    end.to raise_exception(BitexBot::OrderNotFound)
  end
end
