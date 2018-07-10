require 'spec_helper'

describe BitexApiWrapper do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitex: {
        api_key: 'taker_api_key', ssl_version: nil, debug: false, sandbox: false
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  let(:api_wrapper) { BitexBot::Robot.taker }

  it 'Sends User-Agent header' do
    url = "https://bitex.la/api-v1/rest/private/profile?api_key=#{BitexBot::Robot.taker.api_key}"
    stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    api_wrapper.balance rescue nil

    expect(stub_stuff).to have_been_requested
  end

  it '#balance' do
    stub_bitex_balance

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
    stub_bitex_orders

    expect(api_wrapper.orders.sample).to respond_to(:cancel!)
  end

  it '#order_book' do
    stub_bitex_order_book

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

  it '#orders' do
    stub_bitex_orders

    api_wrapper.orders.all? { |o| o.should be_a(ApiWrapper::Order) }

    order = api_wrapper.orders.sample
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
  end

  context '#place_order' do
    it 'raises OrderNotFound error on Bitex errors' do
      Bitex::Bid.stub(create!: nil)
      Bitex::Ask.stub(create!: nil)
      api_wrapper.stub(find_lost: nil)

      expect { api_wrapper.place_order(:buy, 10, 100) }.to raise_exception(OrderNotFound)
      expect { api_wrapper.place_order(:sell, 10, 100) }.to raise_exception(OrderNotFound)
    end
  end

  it '#transactions' do
    stub_bitex_transactions

    api_wrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = api_wrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  it '#user_transaction' do
    stub_bitex_trades

    api_wrapper.user_transactions.should be_a(Array)
    api_wrapper.user_transactions.all? { |o| o.should be_a(ApiWrapper::UserTransaction) }

    user_transaction = api_wrapper.user_transactions.sample
    user_transaction.order_id.should be_a(Integer)
    user_transaction.usd.should be_a(BigDecimal)
    user_transaction.btc.should be_a(BigDecimal)
    user_transaction.btc_usd.should be_a(BigDecimal)
    user_transaction.fee.should be_a(BigDecimal)
    user_transaction.type.should be_a(Integer)
    user_transaction.timestamp.should be_a(Integer)
  end

  it '#find_lost' do
    stub_bitex_orders

    api_wrapper.orders.all? { |o| api_wrapper.find_lost(o.type, o.price, o.amount).present? }
  end
end
