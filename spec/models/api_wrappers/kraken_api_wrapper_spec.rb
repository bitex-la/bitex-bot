require 'spec_helper'

describe KrakenApiWrapper do
  let(:api_wrapper) { described_class }
  let(:api_client) { api_wrapper.client }
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      kraken: {
        api_key: 'your_api_key', api_secret: 'your_api_secret'
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  def stub_public_client
    api_client.stub(public: double)
  end

  def stub_private_client
    api_client.stub(private: double)
  end

  it 'Sends User-Agent header' do
    url = 'https://api.kraken.com/0/public/Depth?pair=XBTUSD'
    stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # We don't care about the response
    KrakenApiWrapper.order_book rescue nil

    expect(stub_stuff).to have_been_requested
  end

  def stub_balance
    api_client.private.stub(account_info: [{ taker_fees: '89.2' }])
    api_client.private.stub(:balance) do
      { 'XXBT': '1433.0939', 'ZUSD': '1230.0233', 'XETH': '99.7497224800' }.with_indifferent_access
    end
  end

  def stub_trade_volume
    api_client.private.stub(:trade_volume).with(hash_including(pair: 'XBTUSD')) do
      {
        'currency' => 'ZUSD', 'volume' => '3878.8703',
        'fees' => {
          'XXBTZUSD' => {
            'fee' => '0.2600',
            'minfee' => '0.1000',
            'maxfee' => '0.2600',
            'nextfee' => '0.2400',
            'nextvolume' => '10000.0000',
            'tiervolume' => '0.0000'
          }
        },
        'fees_maker' => {
          'XETHZEUR' => {
            'fee' => '0.1600',
            'minfee' => '0.0000',
            'maxfee' => '0.1600',
            'nextfee' => '0.1400',
            'nextvolume' => '10000.0000',
            'tiervolume' => '0.0000'
          }
        }
      }.with_indifferent_access
    end
  end

  it '#balance' do
    stub_private_client
    stub_orders
    stub_balance
    stub_trade_volume

    balance = api_wrapper.balance
    balance.should be_a(ApiWrapper::BalanceSummary)
    balance.crypto.should be_a(ApiWrapper::Balance)
    balance.fiat.should be_a(ApiWrapper::Balance)

    crypto = balance.crypto
    crypto.total.should be_a(BigDecimal)
    crypto.reserved.should be_a(BigDecimal)
    crypto.available.should be_a(BigDecimal)

    fiat = balance.fiat
    fiat.total.should be_a(BigDecimal)
    fiat.reserved.should be_a(BigDecimal)
    fiat.available.should be_a(BigDecimal)

    balance.fee.should be_a(BigDecimal)
  end

  it '#cancel' do
    stub_private_client
    stub_orders

    expect(api_wrapper.orders.sample).to respond_to(:cancel!)
  end

  def stub_order_book(count: 3, price: 1.5, amount: 2.5)
    api_client.public.stub(:order_book) do
      {
        'XXBTZUSD' => {
          'bids' => count.times.map { |i| [(price + i).to_d, (amount + i).to_d, 1.seconds.ago.to_i.to_s] },
          'asks' => count.times.map { |i| [(price + i).to_d, (amount + i).to_d, 1.seconds.ago.to_i.to_s] }
        }
      }.with_indifferent_access
    end
  end

  it '#order_book' do
    stub_public_client
    stub_order_book

    order_book = api_wrapper.order_book
    order_book.should be_a(ApiWrapper::OrderBook)
    order_book.bids.all? { |bid| bid.should be_a(ApiWrapper::OrderSummary) }
    order_book.asks.all? { |ask| ask.should be_a(ApiWrapper::OrderSummary) }
    order_book.timestamp.should be_a(Integer)

    bid = order_book.bids.sample
    bid.price.should be_a(BigDecimal)
    bid.quantity.should be_a(BigDecimal)

    ask = order_book.asks.sample
    ask.price.should be_a(BigDecimal)
    ask.quantity.should be_a(BigDecimal)
  end

  def stub_orders
    api_client.private.stub(:open_orders) do
      {
        'open' => {
          'O5TDV2-WDYB2-6OGJRD' => {
            'refid' => nil, 'userref' => nil, 'status' => 'open', 'opentm' => 1_440_292_821.839, 'starttm' => 0, 'expiretm' => 0,
            'descr' => {
              'pair' => 'ETHEUR', 'type' => 'buy', 'ordertype' => 'limit', 'price' => '1.19000', 'price2' => '0',
              'leverage' => 'none', 'order' => 'buy 1204.00000000 ETHEUR @ limit 1.19000'
            },
            'vol' => '1204.00000000', 'vol_exec' => '0.00000000', 'cost' => '0.00000', 'fee' => '0.00000',
            'price' => '0.00008', 'misc' => '', 'oflags' => 'fciq'
          },
          'OGAEYL-LVSPL-BYGGRR' => {
            'refid' => nil, 'userref' => nil, 'status' => 'open', 'opentm' => 1_440_254_004.621, 'starttm' => 0, 'expiretm' => 0,
            'descr' => {
              'pair' => 'ETHEUR', 'type' => 'sell', 'ordertype' => 'limit', 'price' => '1.29000', 'price2' => '0',
              'leverage' => 'none', 'order' => 'sell 99.74972000 ETHEUR @ limit 1.29000'
            },
            'vol' => '99.74972000', 'vol_exec' => '0.00000000', 'cost' => '0.00000', 'fee' => '0.00000',
            'price' => '0.00009', 'misc' => '', 'oflags' => 'fciq'
          }
        }
      }.with_indifferent_access
    end
  end

  it '#orders' do
    stub_private_client
    stub_orders

    api_wrapper.orders.all? { |o| o.should be_a(ApiWrapper::Order) }

    order = api_wrapper.orders.sample
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
  end

  def stub_transactions(count: 1, price: 1.5, amount: 2.5)
    api_client.public.stub(:trades).with('XBTUSD') do
      {
        XXBTZUSD: [
          ['202.51626', '0.01440000', 1_440_277_319.1_922, 'b', 'l', ''],
          ['202.54000', '0.10000000', 1_440_277_322.8_993, 'b', 'l', '']
        ]
      }
    end
  end

  it '#transactions' do
    stub_public_client
    stub_transactions

    api_wrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = api_wrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  it '#user_transaction' do
    api_wrapper.user_transactions.should be_a(Array)
    api_wrapper.user_transactions.empty?.should be_truthy
  end

  it '#find_lost' do
    stub_private_client
    stub_orders

    described_class.orders.all? { |o| described_class.find_lost(o.type, o.price, o.amount).present? }
  end
end
