require 'spec_helper'

describe BitexBot::Robot do
  before(:each) do
    allow(BitexBot::Settings)
      .to receive(:maker_settings)
      .and_return(double(api_key: 'key', sandbox: true, trading_fee: 0.05, orderbook_code: 'btc_usd'))

    allow(BitexBot::Settings)
      .to receive(:taker_settings)
      .and_return(double(api_key: 'key', secret: 'xxx', client_id: 'yyy', order_book: 'btcusd'))

    allow(BitexBot::Settings).to receive(:time_to_live).and_return(10)
    allow(BitexBot::Settings).to receive(:close_time_to_live).and_return(30)

    allow(BitexBot::Settings).to receive_message_chain(:buying, :amount_to_spend_per_order).and_return(50.to_d)
    allow(BitexBot::Settings).to receive_message_chain(:buying, :profit).and_return(0)

    allow(BitexBot::Settings).to receive_message_chain(:selling, :quantity_to_sell_per_order).and_return(1.to_d)
    allow(BitexBot::Settings).to receive_message_chain(:selling, :profit).and_return(0)

    allow(BitexBot::Settings)
      .to receive(:mailer)
      .and_return(
        double(
          from: 'test@test.com',
          to: 'test@test.com',
          delivery_method: :test,
          options: {}
        )
      )

    stub_bitex_balance(
      fiat: { total: 10_000, available: 8_000 },
      crypto: { total: 200, available: 150 },
      trading_fee: 0.5
    )
    stub_bitex_active_orders

    stub_bitstamp_active_orders
    stub_bitstamp_balance
    stub_bitstamp_market
    stub_bitstamp_transactions
    allow_any_instance_of(BitstampApiWrapper).to receive(:user_transactions).and_return([])

    BitexBot::Robot.setup
  end

  after(:each) do
    stub_bitex_reset
    stub_bitstamp_reset
  end

  let(:bot) { BitexBot::Robot.new }

  it 'Starts out by creating opening flows that timeout' do
    bot.trade!

    allow_any_instance_of(BitexApiWrapper).to receive(:trades) do
      [
        build_bitex_user_transaction(:buy, 1, 600, 2, 300, 0.05, :btc_usd),
        build_bitex_user_transaction(:sell, 2, 600, 2, 300, 0.05, :btc_usd)
      ]
    end
    buying = BitexBot::BuyOpeningFlow.last
    selling = BitexBot::SellOpeningFlow.last

    Timecop.travel(10.minutes.from_now)

    bot.trade!
    expect(buying.reload).to be_settling
    expect(selling.reload).to be_settling

    bot.trade!
    expect(buying.reload).to be_finalised
    expect(selling.reload).to be_finalised
  end

  it 'creates alternating opening flows' do
    allow_any_instance_of(BitexApiWrapper).to receive(:trades).and_return([])
    bot.trade!
    expect(BitexBot::BuyOpeningFlow.active.count).to eq(1)

    Timecop.travel(2.seconds.from_now)
    bot.trade!
    expect(BitexBot::BuyOpeningFlow.active.count).to eq(1)

    Timecop.travel(5.seconds.from_now)
    bot.trade!
    expect(BitexBot::BuyOpeningFlow.active.count).to eq(2)

    # When transactions appear, all opening flows should get old and die.
    # We stub our finder to make it so all orders have been successfully cancelled.
    allow_any_instance_of(BitexApiWrapper).to receive(:trades) do
      [
        build_bitex_user_transaction(:buy, 1, 600, 2, 300, 0.05, :btc_usd),
        build_bitex_user_transaction(:sell, 2, 600, 2, 300, 0.05, :btc_usd)
      ]
    end

    Timecop.travel(5.seconds.from_now)
    2.times { bot.trade! }
    expect(BitexBot::BuyOpeningFlow.active.count).to eq(1)

    Timecop.travel(5.seconds.from_now)
    2.times { bot.trade! }
    expect(BitexBot::BuyOpeningFlow.active.count).to eq(0)
  end

  it 'does not place new opening flows until all closing flows are done' do
    bot.trade!
    allow_any_instance_of(BitexApiWrapper).to receive(:trades) do
      [
        build_bitex_user_transaction(:buy, 1, 600, 2, 300, 0.05, :btc_usd),
        build_bitex_user_transaction(:sell, 2, 600, 2, 300, 0.05, :btc_usd)
      ]
    end

    expect { bot.trade! }.to change { BitexBot::BuyClosingFlow.count }.by(1)

    Timecop.travel(15.seconds.from_now)
    2.times { bot.trade! }
    expect(bot).to be_active_closing_flows
    expect(bot).not_to be_active_opening_flows

    stub_bitstamp_hit_orders_into_transactions
    expect do
      bot.trade!
      expect(bot).not_to be_active_closing_flows
    end.to change { BitexBot::BuyOpeningFlow.count }.by(1)
  end

  context 'stops trading when' do
    before(:each) do

      stub_bitex_balance(
        fiat: { total: 10, available: 10 },
        crypto: { total: 10, available: 10 },
        trading_fee: 0.5
      )

      stub_bitstamp_balance(10, 10, 0.05)
    end

    let(:other_bot) { described_class.new  }

    it 'does not place new opening flows when ordered to hold' do
      other_bot.store.update(hold: true)

      expect { bot.trade! }.not_to change { BitexBot::BuyOpeningFlow.count }
    end

    it 'crypto stop is reached' do
      other_bot.store.update(crypto_stop: 30)

      expect { bot.trade! }.not_to change { BitexBot::BuyOpeningFlow.count }
    end

    it 'fiat stop is reached' do
      other_bot.store.update(fiat_stop: 30)

      expect { bot.trade! }.not_to change { BitexBot::BuyOpeningFlow.count }
    end
  end

  context 'warns every 30 minutes when' do
    before(:each) do
      stub_bitex_balance(
        fiat: { total: 100, available: 100 },
        crypto: { total: 100, available: 100 },
        trading_fee: 0.5
      )

      allow_any_instance_of(BitexApiWrapper).to receive(:trades).and_return([])
      stub_bitstamp_balance(100, 100, 0.5)
      other_bot.store.update(crypto_warning: 0, fiat_warning: 0)
    end

    after(:each) do
      expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)

      Timecop.travel(1.minute.from_now)
      stub_bitstamp_market # Re-stub so order book does not get old
      expect { bot.trade! }.not_to change { Mail::TestMailer.deliveries.count }

      Timecop.travel(31.minutes.from_now)
      stub_bitstamp_market # Re-stub so order book does not get old
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

    expect(bot.store.taker_fiat).not_to be_nil
    expect(bot.store.taker_crypto).not_to be_nil
  end

  it 'notifies exceptions and sleeps' do
    allow_any_instance_of(BitstampApiWrapper).to receive(:balance) { raise StandardError.new('oh moova') }

    expect { bot.trade! }.to change { Mail::TestMailer.deliveries.count }.by(1)
  end
end
