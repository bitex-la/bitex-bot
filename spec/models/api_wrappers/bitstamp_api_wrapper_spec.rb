require 'spec_helper'

describe BitstampApiWrapper do
  let(:api_wrapper) { subject.class }

  before(:each) do
    BitexBot::Robot.stub(taker: api_wrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_stuff =
      stub_request(:post, 'https://www.bitstamp.net/api/v2/balance/btcusd/')
      .with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    api_wrapper.balance rescue nil

    stub_stuff.should have_been_requested
  end

  it '#balance' do
    stub_bitstamp_balance

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
    stub_bitstamp_orders
    Bitstamp::Order.any_instance.stub(cancel!: nil)

    api_wrapper.orders.sample.should respond_to(:cancel!)
  end

  it '#order_book' do
    stub_bitstamp_order_book

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
    stub_bitstamp_orders

    order = api_wrapper.orders.sample
    order.should be_a(ApiWrapper::Order)
    order.members.should contain_exactly(*%i[id type price amount timestamp raw_order])
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
    order.raw_order.should be_a(Bitstamp::Order)
  end

  context '#place_order' do
    it 'raises OrderNotFound error on bitstamp errors' do
      Bitstamp.orders.stub(:buy) { raise OrderNotFound }

      expect do
        api_wrapper.place_order(:buy, 10, 100)
      end.to raise_exception(OrderNotFound)
    end
  end

  it '#transactions' do
    stub_bitstamp_transactions

    transaction = api_wrapper.transactions.sample
    transaction.should be_a(ApiWrapper::Transaction)
    transaction.members.should contain_exactly(*%i[id price amount timestamp])
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  it '#user_transaction' do
    stub_bitstamp_user_transactions

    user_transaction = api_wrapper.user_transactions.sample
    user_transaction.should be_a(ApiWrapper::UserTransaction)
    user_transaction.members.should contain_exactly(*%i[order_id usd btc btc_usd fee type timestamp])
    user_transaction.usd.should be_a(BigDecimal)
    user_transaction.btc.should be_a(BigDecimal)
    user_transaction.btc_usd.should be_a(BigDecimal)
    user_transaction.order_id.should be_a(Integer)
    user_transaction.fee.should be_a(BigDecimal)
    user_transaction.type.should be_a(Integer)
    user_transaction.timestamp.should be_a(Integer)
  end
end
