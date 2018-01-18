require 'spec_helper'

describe BitstampApiWrapper do
  def stub_bitstamp_balance(usd = nil, coin = nil, fee = nil)
    Bitstamp.stub(:balance) do
      {
        'btc_balance' => coin || '10.0', 'btc_reserved' => '0', 'btc_available' => coin || '10.0',
        'usd_balance' => usd || '100.0', 'usd_reserved' => '0', 'usd_available' => usd || '100.0',
        'fee' => fee || '0.5'
      }
    end
  end

  # [#<Bitstamp::Order @price="1.1", @amount="1.0", @type=0, @id=76, @datetime="2013-09-26 23:15:04">]
  def stub_bitstamp_orders
    Bitstamp.orders.stub(:all) do
      [double(id: 76, type: 0, amount: '1.23', price: '4.56', datetime:  '23:26:56.849475')]
    end
  end

  # [<Bitstamp::UserTransaction @id=76, @order_id=14, @usd="0.00", @btc="-3.078", @btc_usd="0.00",
  #   @fee="0.00", @type=1, @datetime="2013-09-26 13:46:59">]
  def stub_bitstamp_user_transactions
    Bitstamp.user_transactions.stub(:all) do
      [
        double(usd: '0.00', btc: '-3.00781124', btc_usd: '0.00', order_id: 14, fee: '0.00',
         type: 1, id: 14, datetime: '2013-09-26 13:46:59')
      ]
    end
  end

  before(:each) do
    BitexBot::Robot.stub(taker: BitstampApiWrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    stub_request(:post, 'https://www.bitstamp.net/api/v2/balance/btcusd/')
      .with(headers: { 'User-Agent': BitexBot.user_agent })
    BitstampApiWrapper.balance rescue nil # we don't care about the response
  end

  it '#transactions' do
    stub_bitstamp_transactions

    BitstampApiWrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = BitstampApiWrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  it '#order_book' do
    stub_bitstamp_order_book

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

  it '#balance' do
    stub_bitstamp_balance

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
    stub_bitstamp_orders
    Bitstamp::Order.any_instance.stub(:cancel!) do
      Bitstamp.orders.stub(all: [])
    end

    order = BitstampApiWrapper.orders.sample

    BitstampApiWrapper.orders.should include(order)
    BitstampApiWrapper.cancel(order)
    BitstampApiWrapper.orders.should_not include(order)
  end

  it '#orders' do
    stub_bitstamp_orders

    BitstampApiWrapper.orders.all? { |o| o.should be_a(ApiWrapper::Order) }

    order = BitstampApiWrapper.orders.sample
    order.id.should be_a(Integer)
    order.type.should be_a(Integer)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
  end

  it '#user_transaction' do
    stub_bitstamp_user_transactions
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

  context '#place_order' do
    it 'raises OrderNotFound error on bitstamp errors' do
      Bitstamp.orders.stub(:buy) do
        raise BitexBot::OrderNotFound
      end

      expect do
        BitstampApiWrapper.place_order(:buy, 10, 100)
      end.to raise_exception(BitexBot::OrderNotFound)
    end
  end
end
