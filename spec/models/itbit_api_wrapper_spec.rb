require 'spec_helper'

describe ItbitApiWrapper do
  before(:each) do
    BitexBot::Robot.stub(taker: 'itbit')
    BitexBot::Robot.stub(taker: ItbitApiWrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_request(:get, "https://api.itbit.com/v1/wallets?userId=the-user-id")
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    ItbitApiWrapper.balance rescue nil # we don't care about the response
  end
end
