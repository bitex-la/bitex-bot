require 'spec_helper'

describe BitfinexApiWrapper do
  let(:api_wrapper) { subject.class }

  before(:each) do
    BitexBot::Robot.stub(taker: api_wrapper)
    BitexBot::Robot.setup
    api_wrapper.max_retries = 0
  end

  it 'Sends User-Agent header' do
    stuff_stub =
      stub_request(:post, 'https://api.bitfinex.com/v1/orders')
      .with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    api_wrapper.orders rescue nil

    stuff_stub.should have_been_requested
  end

  it '#balance' do
    stub_bitfinex_balance

    balance = api_wrapper.balance
    balance.should be_a(ApiWrapper::BalanceSummary)
    balance.members.should contain_exactly(*%i[btc usd fee])

    balance.fee.should be_a(BigDecimal)

    btc = balance.btc
    btc.should be_a(ApiWrapper::Balance)
    btc.members.should contain_exactly(*%i[total reserved available])
    btc.total.should be_a(BigDecimal)
    btc.reserved.should be_a(BigDecimal)
    btc.available.should be_a(BigDecimal)

    usd = balance.usd
    usd.should be_a(ApiWrapper::Balance)
    usd.members.should contain_exactly(*%i[total reserved available])
    usd.total.should be_a(BigDecimal)
    usd.reserved.should be_a(BigDecimal)
    usd.available.should be_a(BigDecimal)
  end

  it '#cancel' do
    stub_bitfinex_orders

    api_wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_bitfinex_order_book

    order_book = api_wrapper.order_book

    order_book.should be_a(ApiWrapper::OrderBook)
    order_book.members.should contain_exactly(*%i[timestamp asks bids])

    order_book.timestamp.should be_a(Integer)

    bid = order_book.bids.sample
    bid.should be_a(ApiWrapper::OrderSummary)
    bid.members.should contain_exactly(*%i[price quantity])
    bid.price.should be_a(BigDecimal)
    bid.quantity.should be_a(BigDecimal)

    ask = order_book.asks.sample
    ask.should be_a(ApiWrapper::OrderSummary)
    ask.members.should contain_exactly(*%i[price quantity])
    ask.price.should be_a(BigDecimal)
    ask.quantity.should be_a(BigDecimal)
  end

  it '#orders' do
    stub_bitfinex_orders

    order = api_wrapper.orders.sample
    order.should be_a(ApiWrapper::Order)
    order.members.should contain_exactly(*%i[id type price amount timestamp raw_order])
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
    order.raw_order.should be_present
  end

  it '#transactions' do
    stub_bitfinex_transactions

    transaction = api_wrapper.transactions.sample
    transaction.should be_a(ApiWrapper::Transaction)
    transaction.members.should contain_exactly(*%i[id price amount timestamp])
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
