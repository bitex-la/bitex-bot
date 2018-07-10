require 'spec_helper'

describe BitexBot::Robot do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitstamp: {
        api_key: 'YOUR_API_KEY', secret: 'YOUR_API_SECRET', client_id: 'YOUR_BITSTAMP_USERNAME'
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
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
    Bitex::Profile.stub(get: {
      fee: 0.5,
      usd_balance:       10000.00,   # Total USD balance
      usd_reserved:       2000.00,   # USD reserved in open orders
      usd_available:      8000.00,   # USD available for trading
      btc_balance:    20.00000000,   # Total BTC balance
      btc_reserved:    5.00000000,   # BTC reserved in open orders
      btc_available:  15.00000000,   # BTC available for trading
      ltc_balance:   250.00000000,   # Total LTC balance
      ltc_reserved:  100.00000000,   # LTC reserved in open orders
      ltc_available: 150.00000000    # LTC available for trading
    })
    stub_bitex_active_orders
    stub_bitstamp_sell
    stub_bitstamp_buy
    stub_bitstamp_api_wrapper_balance
    stub_bitstamp_api_wrapper_order_book
    stub_bitstamp_transactions
    stub_bitstamp_empty_user_transactions
  end

  let(:bot) { BitexBot::Robot.new }

  it 'Starts out by creating opening flows that timeout' do
    stub_bitex_active_orders
    stub_bitstamp_api_wrapper_order_book
    bot.trade!

    stub_bitex_transactions
    buying = BitexBot::BuyOpeningFlow.last
    selling = BitexBot::SellOpeningFlow.last

    Timecop.travel(10.minutes.from_now)
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
    BitexBot::BuyOpeningFlow.active.count.should eq 1

    Timecop.travel(2.seconds.from_now)
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should eq 1

    Timecop.travel(5.seconds.from_now)
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should eq 2

    # When transactions appear, all opening flows should get old and die.
    # We stub our finder to make it so all orders have been successfully cancelled.
    stub_bitex_transactions

    Timecop.travel 5.seconds.from_now
    2.times { bot.trade! }
    BitexBot::BuyOpeningFlow.active.count.should eq 1

    Timecop.travel 5.seconds.from_now
    bot.trade!
    BitexBot::BuyOpeningFlow.active.count.should eq 0
  end

  it 'does not place new opening flows until all closing flows are done' do
    bot.trade!
    stub_bitex_transactions
    expect { bot.trade! }.to change { BitexBot::BuyClosingFlow.count }.by(1)

    Timecop.travel 15.seconds.from_now
    2.times { bot.trade! }
    bot.should be_active_closing_flows
    bot.should_not be_active_opening_flows

    stub_bitstamp_orders_into_transactions
    expect do
      bot.trade!
      bot.should_not be_active_closing_flows
    end.to change { BitexBot::BuyOpeningFlow.count }.by(1)
  end

  context 'stops trading when' do
    before(:each) do
      Bitex::Profile.stub(get: {
        fee: 0.5,
        usd_balance:   10.00,
        usd_reserved:  10.00,
        usd_available: 10.00,
        btc_balance:   10.00,
        btc_reserved:  10.00,
        btc_available: 10.00
      })

      stub_bitstamp_api_wrapper_balance(10, 10, 0.05)
    end

    after(:each) { expect { bot.trade! }.not_to change { BitexBot::BuyOpeningFlow.count } }

    let(:other_bot) { described_class.new  }

    it 'does not place new opening flows when ordered to hold' do
      other_bot.store.update(hold: true)
    end

    it 'crypto stop is reached' do
      other_bot.store.update(crypto_stop: 30)
    end

    it 'fiat stop is reached' do
      other_bot.store.update(fiat_stop: 30)
    end
  end

  context 'warns every 30 minutes when' do
    before(:each) do
      Bitex::Profile.stub(get: {
        fee: 0.5,
        usd_balance:   10.00,
        usd_reserved:   1.00,
        usd_available:  9.00,
        btc_balance:   10.00,
        btc_reserved:   1.00,
        btc_available:  9.00
      })
      Bitex::Trade.stub(all: [])
      stub_bitstamp_api_wrapper_balance(100, 100)
      other_bot.store.update(crypto_warning: 0, fiat_warning: 0)
    end

    after(:each) do
      expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)

      Timecop.travel 1.minute.from_now
      stub_bitstamp_order_book # Re-stub so order book does not get old
      expect { bot.trade! }.not_to change { Mail::TestMailer.deliveries.count }

      Timecop.travel 31.minutes.from_now
      stub_bitstamp_order_book # Re-stub so order book does not get old
      expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)
    end

    let(:other_bot) { described_class.new }

    it 'crypto warning is reached' do
      other_bot.store.update(crypto_warning: 1_000)
    end

    it 'fiat warning is reached' do
      other_bot.store.update(fiat_warning: 1_000)
    end
  end

  it 'updates taker_fiat and taker_crypto' do
    bot.trade!
    bot.store.taker_fiat.should_not be_nil
    bot.store.taker_crypto.should_not be_nil
  end

  it 'notifies exceptions and sleeps' do
    BitstampApiWrapper.any_instance.stub(:balance) { raise StandardError.new('oh moova') }

    expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)
  end
end
