require 'spec_helper'

describe BitexBot::Robot do
  before(:each) do
    BitexBot::Settings.stub(
      time_to_live: 10,
      buying: double(
        amount_to_spend_per_order: 50,
        profit: 0),
      selling: double(
        quantity_to_sell_per_order: 1,
        profit: 0),
      mailer: double(
        from: 'test@test.com',
        to: 'test@test.com',
        method: :test,
        options: {}
      )
    )
    Bitex.api_key = "valid_key"
    Bitex::Profile.stub(get: {fee: 0.5})
    stub_bitex_orders
    stub_bitstamp_sell
    stub_bitstamp_buy
    stub_bitstamp_balance
    stub_bitstamp_order_book
    stub_bitstamp_transactions
    stub_bitstamp_user_transactions
  end
  let(:bot){ BitexBot::Robot.new }

  it 'Starts out by creating opening flows that timeout' do
    stub_bitex_orders
    bot.trade!
    stub_bitex_transactions
    buying = BitexBot::BuyOpeningFlow.last
    selling = BitexBot::SellOpeningFlow.last

    Timecop.travel 10.minutes.from_now
    bot.trade!
 
    buying.reload.should be_settling
    selling.reload.should be_settling

    bot.trade!
    buying.reload.should be_finalised
    selling.reload.should be_finalised
  end
  
  it 'creates alternating opening flows' do
    Bitex::Transaction.stub(all: [])
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should == 1
    Timecop.travel 2.seconds.from_now
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should == 1
    Timecop.travel 5.seconds.from_now
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should == 2
    
    # When transactions appear, all opening flows
    # should get old and die.
    # We stub our finder to make it so all orders
    # have been successfully cancelled.
    stub_bitex_transactions

    Timecop.travel 5.seconds.from_now
    bot.trade!
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should == 1
    Timecop.travel 5.seconds.from_now
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should == 0
  end

  it 'does not place new opening flows until all closing flows are done' do
    bot.trade!
    stub_bitex_transactions
    expect do
      bot.trade!
    end.to change{ BitexBot::BuyClosingFlow.count }.by(1)

    Timecop.travel 15.seconds.from_now
    bot.trade!
    bot.trade!
    bot.should be_active_closing_flows
    bot.should_not be_active_opening_flows

    stub_bitstamp_orders_into_transactions
    expect do
      bot.trade!
      bot.should_not be_active_closing_flows
    end.to change{ BitexBot::BuyOpeningFlow.count }.by(1)
  end
 
  it 'notifies exceptions and sleeps' do
    Bitstamp.stub(:balance) do
      raise StandardError.new('oh moova')
    end
    bot.trade!
    Mail::TestMailer.deliveries.count.should == 1
  end

  #it 'goes through all the motions buying and selling' do
  #  pending
  #end
end
