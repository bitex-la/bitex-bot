require 'spec_helper'

describe KrakenApiWrapper do
  let(:api_wrapper) { KrakenApiWrapper }
  let(:api_client) { api_wrapper.client }

  before(:each) do
    BitexBot::Robot.stub(taker: api_wrapper)
    BitexBot::Robot.setup
  end

  def stub_public_client
    api_client.stub(public: double)
  end

  def stub_private_client
    api_client.stub(private: double)
  end

  def stub_transactions
    api_client.public.stub(:trades).with('XBTUSD') do
      {
        XXBTZUSD: [
          ['202.51626', '0.01440000', 1_440_277_319.1_922, 'b', 'l', ''],
          ['202.54000', '0.10000000', 1_440_277_322.8_993, 'b', 'l', '']
        ]
      }
    end
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

  def stub_order_book
    api_client.public.stub(:order_book) do
      {
        'XXBTZUSD' => {
          'bids' => [['574.61', '0.14397', '1472506127.0']],
          'asks' => [['574.62', '19.1334', '1472506126.0']]
        }
      }.with_indifferent_access
    end
  end

  def stub_balance
    api_client.private.stub(account_info: [{ taker_fees: '89.2' }])
    api_client.private.stub(:balance) do
      { 'XXBT': '1433.0939', 'ZUSD': '1230.0233', 'XETH': '99.7497224800' }.with_indifferent_access
    end
  end

  def stub_trade_volume
    api_client.private.stub(:trade_volume).with(pair: 'XBTUSD') do
      {
        'currency' => 'ZUSD', 'volume' => '3878.8703',
        'fees' => {
          'XXBTZUSD' => {
            'fee' => '0.2600', 'minfee' => '0.1000', 'maxfee' => '0.2600', 'nextfee' => '0.2400',
            'nextvolume' => '10000.0000', 'tiervolume' => '0.0000'
          }
        },
        'fees_maker' => {
          'XETHZEUR' => {
            'fee' => '0.1600', 'minfee' => '0.0000', 'maxfee' => '0.1600', 'nextfee' => '0.1400',
            'nextvolume' => '10000.0000', 'tiervolume' => '0.0000'
          }
        }
      }.with_indifferent_access
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

  it '#balance' do
    stub_private_client
    stub_orders
    stub_balance
    stub_trade_volume

    balance = api_wrapper.balance
    balance.should be_a(ApiWrapper::BalanceSummary)
    balance.btc.should be_a(ApiWrapper::Balance)
    balance.usd.should be_a(ApiWrapper::Balance)

    btc = balance.btc
    btc.total.should be_a(BigDecimal)
    btc.reserved.should be_a(BigDecimal)
    btc.available.should be_a(BigDecimal)

    usd = balance.usd
    usd.total.should be_a(BigDecimal)
    usd.reserved.should be_a(BigDecimal)
    usd.available.should be_a(BigDecimal)

    balance.fee.should be_a(BigDecimal)
  end

  it '#user_transaction' do
    api_wrapper.user_transactions.should be_a(Array)
    api_wrapper.user_transactions.empty?.should be_truthy
  end
end
