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
    stuff_stub = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    BitfinexApiWrapper.orders rescue nil

    expect(stuff_stub).to have_been_requested
  end

  it '#balance' do
    stub_bitfinex_balance

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
    stub_bitfinex_orders

    expect(api_wrapper.orders.sample).to respond_to(:cancel!)
  end


  it '#orders' do
    stub_bitfinex_orders

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
    stub_bitfinex_order_book

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

  it '#transactions' do
    stub_bitfinex_transactions

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
