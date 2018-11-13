require 'spec_helper'

describe KrakenApiWrapper do
  let(:api_wrapper) { described_class }
  let(:api_client) { api_wrapper.client }
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      kraken: { api_key: 'your_api_key', api_secret: 'your_api_secret', currency_pair: :xbtusd }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  def stub_request_helper(method:, path: '', status: 200, result: {}, error: [], header_params: {})
    stub_request(method, "https://api.kraken.com/0#{path}")
      .with(headers: { 'User-Agent': BitexBot.user_agent }.merge(header_params))
      .to_return(
        status: status,
        body: { error: error, result: result }.to_json,
        headers: { 'Content-Type': 'application/json' }
      )
  end

  def stub_assets
    stub_request_helper(
      method: :get,
      path: '/public/AssetPairs',
      result: {
        XXBTZUSD:  {
          altname: 'XBTUSD',
          aclass_base: 'currency',
          base: 'XXBT',
          aclass_quote: 'currency',
          quote: 'ZUSD',
          lot: 'unit',
          pair_decimals: 1,
          lot_decimals: 8,
          lot_multiplier: 1,
          leverage_buy: [2, 3, 4, 5],
          leverage_sell: [2, 3, 4, 5],
          fees: [
            [0, 0.26],
            [50_000, 0.24],
            [100_000, 0.22],
            [250_000, 0.2],
            [500_000, 0.18],
            [1_000_000, 0.16],
            [2_500_000, 0.14],
            [5_000_000, 0.12],
            [10_000_000, 0.1]
          ],
          fees_maker: [
            [0, 0.16],
            [50_000, 0.14],
            [100_000, 0.12],
            [250_000, 0.1],
            [500_000, 0.08],
            [1_000_000, 0.06],
            [2_500_000, 0.04],
            [5_000_000, 0.02],
            [10_000_000, 0]
          ],
          fee_volume_currency: 'ZUSD',
          margin_call: 80,
          margin_stop: 40
        }
      }
    )
  end

  it 'Sends User-Agent header' do
    stub_assets
    stub_stuff = stub_order_book

    # We don't care about the response
    api_wrapper.order_book

    stub_stuff.should have_been_requested
  end

  def stub_balance
    stub_request_helper(
      method: :post,
      path: '/private/Balance',
      header_params: { 'Api-Key': api_wrapper.settings.api_key },
      result: { XXBT: '1433.0939', ZUSD: '1230.0233', ETH: '99.7497224800' }
    )
  end

  def stub_trade_volume
    stub_request_helper(
      method: :post,
      path: '/private/TradeVolume',
      header_params: { 'Api-Key': api_wrapper.settings.api_key },
      result: {
        currency: 'ZUSD',
        volume: '3878.8703',
        fees: {
          XXBTZUSD: {
            fee: '0.2600',
            minfee: '0.1000',
            maxfee: '0.2600',
            nextfee: '0.2400',
            nextvolume: '10000.0000',
            tiervolume: '0.0000'
          }
        },
        fees_maker: {
          XETHZEUR: {
            fee: '0.1600',
            minfee: '0.0000',
            maxfee: '0.1600',
            nextfee: '0.1400',
            nextvolume: '10000.0000',
            tiervolume: '0.0000'
          }
        }
      }
    )
  end

  it '#balance' do
    stub_assets
    stub_balance
    stub_orders
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
    stub_orders

    api_wrapper.orders.sample.should respond_to(:cancel!)
  end

  def stub_order_book(count: 3, price: 1.5, amount: 2.5)
    stub_request_helper(
      method: :get,
      path: '/public/Depth?pair=XBTUSD',
      result: {
        XXBTZUSD: {
          bids: count.times.map { |i| [(price + i).to_d, (amount + i).to_d, 1.seconds.ago.to_i.to_s] },
          asks: count.times.map { |i| [(price + i).to_d, (amount + i).to_d, 1.seconds.ago.to_i.to_s] }
        }
      }
    )
  end

  it '#order_book' do
    stub_assets
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
    stub_request_helper(
      method: :post,
      path: '/private/OpenOrders',
      header_params: { 'Api-Key': api_wrapper.settings.api_key },
      result: {
        open: {
          'O5TDV2-WDYB2-6OGJRD': {
            refid: nil, userref: nil, status: 'open', opentm: 1_440_292_821.839, starttm: 0, expiretm: 0,
            descr: {
              pair: 'ETHEUR', type: 'buy', ordertype: 'limit', price: '1.19000', price2: '0',
              leverage: 'none', order: 'buy 1204.00000000 ETHEUR @ limit 1.19000'
            },
            vol: '1204.00000000', vol_exec: '0.00000000', cost: '0.00000', fee: '0.00000',
            price: '0.00008', misc: '', oflags: 'fciq'
          },
          'OGAEYL-LVSPL-BYGGRR': {
            refid: nil, userref: nil, status: 'open', opentm: 1_440_254_004.621, starttm: 0, expiretm: 0,
            descr: {
              pair: 'ETHEUR', type: 'sell', ordertype: 'limit', price: '1.29000', price2: '0',
              leverage: 'none', order: 'sell 99.74972000 ETHEUR @ limit 1.29000'
            },
            vol: '99.74972000', vol_exec: '0.00000000', cost: '0.00000', fee: '0.00000',
            price: '0.00009', misc: '', oflags: 'fciq'
          }
        }
      }
    )
  end

  it '#orders' do
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
    stub_request_helper(
      method: :get,
      path: '/public/Trades?pair=XBTUSD',
      result: {
        XXBTZUSD: [
          ['202.51626', '0.01440000', 1_440_277_319.1_922, 'b', 'l', ''],
          ['202.54000', '0.10000000', 1_440_277_322.8_993, 'b', 'l', '']
        ]
      }
    )
  end

  it '#transactions' do
    stub_assets
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
    stub_orders

    api_wrapper.orders.all? { |o| api_wrapper.find_lost(o.type, o.price, o.amount).present? }
  end

  it '#currency_pair' do
    stub_assets
    BitexBot::Settings.taker.kraken.currency_pair.should eq taker_settings.kraken.currency_pair

    api_wrapper.currency_pair.should be_a(HashWithIndifferentAccess)
    api_wrapper.currency_pair.keys.should include(*%w[altname base quote raw_name])
  end

  it '#settings correctly mapped to wrapper settings' do
    api_wrapper.settings do |settings|
      settings.should be_a(BitexBot::SettingsClass)
      settings.keys.should contain_exactly(*%i[api_key api_secret])
      settings.api_key.should eq BitexBot::Settings.taker.kraken.api_key
      settings.api_secret.should eq BitexBot::Settings.taker.kraken.api_secret
    end
  end
end
