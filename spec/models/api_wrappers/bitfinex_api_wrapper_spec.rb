require 'spec_helper'

describe 'BitfinexApiWrapper' do
  let(:api_wrapper) { BitfinexApiWrapper }
  let(:api_client) { Bitfinex::Client }

  before(:each) do
    BitexBot::Robot.stub(taker: api_wrapper)
    BitfinexApiWrapper.max_retries = 0
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    url = 'https://api.bitfinex.com/v1/orders'
    stub_stuff = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    BitfinexApiWrapper.orders rescue nil

    expect(stub_stuff).to have_been_requested
  end

  def stub_account_info
    api_client.any_instance.stub(:account_info) do
      [
        {
          maker_fees: '0.1',
          taker_fees: '0.2',
          fees: [
            { pairs: 'BTC', maker_fees: '0.1', taker_fees: '0.2' },
            { pairs: 'LTC', maker_fees: '0.1', taker_fees: '0.2' },
            { pairs: 'ETH', maker_fees: '0.1', taker_fees: '0.2' }
          ]
        }
      ]
    end
  end

  # [
  #   { type: 'exchange', currency: 'btc', amount: '0.0', available: '0.0' },
  #   { type: 'exchange', currency: 'usd', amount: '0.0', available: '0.0' },
  #   ...
  # ]
  def stub_balance(count: 2, amount: 1.5, available: 2.5, fee: 1.0)
    stub_account_info
    api_client.any_instance.stub(:balances).with(hash_including(type: 'exchange')) do
      count.times.map do |i|
        {
          type: 'exchange',
          currency: (i % 2).zero? ? 'usd' : 'btc',
          amount: (amount + i).to_s,
          available: (available + i).to_s
        }
      end
    end
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

  it '#cancel' do
    stub_orders
    expect(api_wrapper.orders.sample).to respond_to(:cancel!)
  end

  # [
  #   {
  #     id: 448411365, symbol: 'btcusd', exchange: 'bitfinex', price: '0.02', avg_execution_price: '0.0',  side: 'buy',
  #     type: 'exchange limit', timestamp: '1444276597.0', is_live: true, is_cancelled: false, is_hidden: false,
  #     was_forced: false, original_amount: '0.02', remaining_amount: '0.02', executed_amount: '0.0'
  #   }
  # ]
  def stub_orders(count: 1)
    api_client.any_instance.stub(:orders) do
      count.times.map do |i|
        {
          id: i,
          symbol: 'btcusd',
          exchange: 'bitfinex',
          price: '0.02',
          avg_execution_price: '0.0',
          side: 'buy',
          type: 'exchange limit',
          timestamp: 1.seconds.ago.to_f.to_s,
          is_live: true,
          is_cancelled: false,
          is_hidden: false,
          was_forced: false,
          original_amount: '0.02',
          remaining_amount: '0.02',
          executed_amount: '0.0'
        }
      end
    end
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

  # {
  #   bids: [{ price: '574.61', amount: '0.14397', timestamp: '1472506127.0' }],
  #   asks: [{ price: '574.62', amount: '19.1334', timestamp: '1472506126.0 '}]
  # }
  def stub_order_book(amount: 1.5, price: 2.5)
    api_client.any_instance.stub(:orderbook) do
      {
        bids: [{ price: price.to_s, amount: amount.to_s, timestamp: 1.seconds.ago.to_f.to_s }],
        asks: [{ price: price.to_s, amount: amount.to_s, timestamp: 1.seconds.ago.to_f.to_s }]
      }
    end
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

  # { tid: 15627111, price: 404.01, amount: '2.45116479', exchange: 'bitfinex', type: 'sell', timestamp: 1455526974 }
  def stub_transactions(count: 1, price: 1.5, amount: 2.5)
    api_client.any_instance.stub(:trades) do
      count.times.map do |i|
        {
          tid: i,
          price: price + 1,
          amount: (amount + i).to_s,
          exchange: 'bitfinex',
          type: (i % 2).zero? ? 'sell' : 'buy',
          timestamp: 1.seconds.ago.to_i
        }
      end
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

  it '#user_transaction' do
    api_wrapper.user_transactions.should be_a(Array)
    api_wrapper.user_transactions.empty?.should be_truthy
  end
end
