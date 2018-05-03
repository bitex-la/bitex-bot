require 'spec_helper'

describe BitexBot::Robot do
  before(:each) do
    Bitex.api_key = 'valid_key'

    BitexBot::Settings.stub(
      time_to_live: 10,
      buying: double(amount_to_spend_per_order: 50, profit: 0),
      selling: double(quantity_to_sell_per_order: 1, profit: 0),
      mailer: double(
        from: 'test@test.com',
        to: 'test@test.com',
        delivery_method: :test,
        options: {}
      )
    )

    Bitex::Profile.stub(
      get: {
        fee: 0.5,
        usd_balance: 10000.0,  # Total USD balance
        usd_reserved: 2000.0,  # USD reserved in open orders
        usd_available: 8000.0, # USD available for trading
        btc_balance: 20.0,     # Total BTC balance
        btc_reserved: 5.0,     # BTC reserved in open orders
        btc_available: 15.0,   # BTC available for trading
        ltc_balance: 250.0,    # Total LTC balance
        ltc_reserved: 100.0,   # LTC reserved in open orders
        ltc_available: 150.0   # Total LTC balance
      }
    )

    stub_bitex_orders
    stub_bitstamp_sell
    stub_bitstamp_buy
    stub_bitstamp_api_wrapper_balance
    stub_bitstamp_api_wrapper_order_book
    stub_bitstamp_transactions
    stub_bitstamp_empty_user_transactions
  end

  let(:bot) { BitexBot::Robot.new }

  it 'orderbook formed from your base currency and another quote currency' do
    BitexBot::Settings.bitex.orderbook do |orderbook|
      BitexBot::Robot.orderbook.should be orderbook
      BitexBot::Robot.base_coin.should eq orderbook.to_s.split('_')[0].upcase
      BitexBot::Robot.quote_coin.should eq orderbook.to_s.split('_')[1].upcase
    end
  end

  it 'Starts out by creating opening flows that timeout' do
    stub_bitex_orders
    stub_bitstamp_api_wrapper_order_book

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
    Bitex::Trade.stub(all: [])
    bot.trade!

    BitexBot::BuyOpeningFlow.active.count.should == 1
    Timecop.travel 2.seconds.from_now
    bot.trade!

    BitexBot::BuyOpeningFlow.active.count.should == 1
    Timecop.travel 5.seconds.from_now
    bot.trade!

    BitexBot::BuyOpeningFlow.active.count.should == 2

    # When transactions appear, all opening flows should get old and die.
    # We stub our finder to make it so all orders have been successfully cancelled.
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
    end.to change { BitexBot::BuyClosingFlow.count }.by(1)

    Timecop.travel 15.seconds.from_now
    bot.trade!
    bot.trade!
    bot.should be_active_closing_flows
    bot.should_not be_active_opening_flows

    stub_bitstamp_orders_into_transactions
    expect do
      bot.trade!
      bot.should_not be_active_closing_flows
    end.to change { BitexBot::BuyOpeningFlow.count }.by(1)
  end

  it 'does not place new opening flows when ordered to hold' do
    other_bot = BitexBot::Robot.new
    other_bot.store.hold = true
    other_bot.store.save!
    expect do
      bot.trade!
    end.not_to change { BitexBot::BuyOpeningFlow.count }
  end

  it 'stops trading when btc stop is reached' do
    other_bot = BitexBot::Robot.new
    other_bot.store.usd_stop = 11000
    other_bot.store.save!
    expect do
      bot.trade!
    end.not_to change { BitexBot::BuyOpeningFlow.count }
  end

  it 'stops trading when usd stop is reached' do
    other_bot = BitexBot::Robot.new
    other_bot.store.btc_stop = 30
    other_bot.store.save!
    expect do
      bot.trade!
    end.not_to change { BitexBot::BuyOpeningFlow.count }
  end

  it 'warns every 30 minutes when usd warn is reached' do
    Bitex::Trade.stub(all: [])
    other_bot = BitexBot::Robot.new
    other_bot.store.usd_warning = 11000
    other_bot.store.save!
    expect do
      bot.trade!
    end.to change { Mail::TestMailer.deliveries.count }.by(1)
    Timecop.travel 1.minute.from_now
    stub_bitstamp_order_book # Re-stub so orderbook does not get old
    expect do
      bot.trade!
    end.not_to change { Mail::TestMailer.deliveries.count }
    Timecop.travel 31.minutes.from_now
    stub_bitstamp_order_book # Re-stub so orderbook does not get old
    expect do
      bot.trade!
    end.to change { Mail::TestMailer.deliveries.count }.by(1)
  end

  it 'warns every 30 minutes when btc warn is reached' do
    Bitex::Trade.stub(all: [])
    other_bot = BitexBot::Robot.new
    other_bot.store.btc_warning = 30
    other_bot.store.save!

    expect do
      bot.trade!
    end.to change { Mail::TestMailer.deliveries.count }.by(1)

    Timecop.travel(1.minute.from_now)
    stub_bitstamp_order_book # Re-stub so orderbook does not get old
    expect do
      bot.trade!
    end.not_to change { Mail::TestMailer.deliveries.count }

    Timecop.travel(31.minutes.from_now)
    stub_bitstamp_order_book # Re-stub so orderbook does not get old

    expect do
      bot.trade!
    end.to change { Mail::TestMailer.deliveries.count }.by(1)
  end

  it 'updates taker_usd and taker_btc' do
    bot.trade!
    bot.store.taker_usd.should_not be_nil
    bot.store.taker_btc.should_not be_nil
  end

  it 'notifies exceptions and sleeps' do
    BitstampApiWrapper.stub(:balance) { raise StandardError.new('oh moova') }

    expect do
      bot.trade!
    end.to change { Mail::TestMailer.deliveries.count }.by(1)
  end
end
