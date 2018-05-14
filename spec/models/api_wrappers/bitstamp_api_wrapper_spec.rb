require 'spec_helper'

describe BitstampApiWrapper do
  before(:each) do
    BitexBot::Robot.stub(taker: BitstampApiWrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    url = 'https://www.bitstamp.net/api/v2/balance/btcusd/'
    stub_stuff = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    BitstampApiWrapper.balance rescue nil

    expect(stub_stuff).to have_been_requested
  end

  it '#balance' do
    stub_balance

    balance = BitstampApiWrapper.balance
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
    Bitstamp::Order.any_instance.stub(:cancel!) do
      Bitstamp.orders.stub(all: [])
    end

    order = BitstampApiWrapper.orders.sample

    BitstampApiWrapper.orders.map(&:id).should include(order.id)
    expect(order).to respond_to(:cancel!)
    BitstampApiWrapper.cancel(order)
    BitstampApiWrapper.orders.map(&:id).should_not include(order.id)
  end

  it '#order_book' do
    stub_order_book

    order_book = BitstampApiWrapper.order_book
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

  it '#orders' do
    stub_orders

    BitstampApiWrapper.orders.all? { |o| o.should be_a(ApiWrapper::Order) }

    order = BitstampApiWrapper.orders.sample
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)

    expect(order).to respond_to(:cancel!)
  end

  context '#place_order' do
    it 'raises OrderNotFound error on bitstamp errors' do
      Bitstamp.orders.stub(:buy) do
        raise OrderNotFound
      end

      expect do
        BitstampApiWrapper.place_order(:buy, 10, 100)
      end.to raise_exception(OrderNotFound)
    end
  end

  it '#transactions' do
    stub_transactions

    BitstampApiWrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = BitstampApiWrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  it '#user_transaction' do
    stub_user_transactions
    BitstampApiWrapper.user_transactions.all? { |ut| ut.should be_a(ApiWrapper::UserTransaction) }

    user_transaction = BitstampApiWrapper.user_transactions.sample
    user_transaction.usd.should be_a(BigDecimal)
    user_transaction.btc.should be_a(BigDecimal)
    user_transaction.btc_usd.should be_a(BigDecimal)
    user_transaction.order_id.should be_a(Integer)
    user_transaction.fee.should be_a(BigDecimal)
    user_transaction.type.should be_a(Integer)
    user_transaction.timestamp.should be_a(Integer)
  end
end
