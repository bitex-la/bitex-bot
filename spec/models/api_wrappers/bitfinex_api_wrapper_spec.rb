require 'spec_helper'

describe BitfinexApiWrapper do
  let(:api_wrapper) { BitfinexApiWrapper }
  let(:api_client) { Bitfinex::Client }

  before(:each) do
    BitexBot::Robot.stub(taker: api_wrapper)
    BitfinexApiWrapper.max_retries = 0
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_request(:post, 'https://api.bitfinex.com/v1/balances')
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    stub_request(:post, 'https://api.bitfinex.com/v1/account_infos')
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    BitfinexApiWrapper.balance rescue nil # we don't care about the response
  end

  def stub_transactions
    api_client.any_instance.stub(:trades) do
      [
        { tid: 15627111, price: 404.01, amount: '2.45116479', exchange: 'bitfinex', type: 'sell', timestamp: 1455526974 },
        { tid: 15627111, price: 404.01, amount: '2.45116479', exchange: 'bitfinex', type: 'sell', timestamp: 1455526974 }
      ]
    end
  end

  def stub_orders
    api_client.any_instance.stub(:orders) do
      [
        {
          id: 448411365, symbol: 'btcusd', exchange: 'bitfinex', price: '0.02', avg_execution_price: '0.0',  side: 'buy',
          type: 'exchange limit', timestamp: '1444276597.0', is_live: true, is_cancelled: false, is_hidden: false,
          was_forced: false, original_amount: '0.02', remaining_amount: '0.02', executed_amount: '0.0'
        }.stringify_keys
      ]
    end
  end

  def stub_order_book
    api_client.any_instance.stub(:orderbook) do
      {
        bids: [{ price: '574.61', amount: '0.14397', timestamp: '1472506127.0' }],
        asks: [{ price: '574.62', amount: '19.1334', timestamp: '1472506126.0 '}]
      }
    end
  end

  def stub_balance
    api_client.any_instance.stub(:account_info) { [{ taker_fees: '89.2' }] }
    api_client.any_instance.stub(:balances) do
      [
        { type: 'deposit', currency: 'btc', amount: '0.0', available: '0.0' },
        { type: 'deposit', currency: 'usd', amount: '1.0', available: '1.0' },
        { type: 'exchange', currency: 'btc', amount: '1', available: '1' }
      ]
    end
  end

  it '#transactions' do
    stub_transactions

    api_wrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = api_wrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
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

    expect(order).to respond_to(:cancel!)
  end

  it '#order_book' do
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
    stub_balance

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
