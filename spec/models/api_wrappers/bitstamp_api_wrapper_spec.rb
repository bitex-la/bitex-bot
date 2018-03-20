require 'spec_helper'

describe BitstampApiWrapper do

  before(:each) do
    BitexBot::Robot.stub(taker: BitstampApiWrapper)
    BitexBot::Robot.setup
  end

  it 'Sends User-Agent header' do
    url = 'https://www.bitstamp.net/api/v2/balance/btcusd/'
    stuff_stub = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    BitstampApiWrapper.balance rescue nil

    expect(stuff_stub).to have_been_requested
  end

  def balance_stub(balance: '0.5', reserved: '1.5', available: '2.0', fee: '0.2')
    Bitstamp.stub(:balance) do
      {
        'btc_balance' => balance,
        'btc_reserved' => reserved,
        'btc_available' => available,
        'usd_balance' => balance,
        'usd_reserved' => reserved,
        'usd_available' => balance,
        'fee' => fee
      }
    end
  end

  it '#balance' do
    balance_stub

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
    orders_stub
    Bitstamp::Order.any_instance.stub(:cancel!) do
      Bitstamp.orders.stub(all: [])
    end

    order = BitstampApiWrapper.orders.sample

    BitstampApiWrapper.orders.should include(order)
    expect(order).to respond_to(:cancel!)
    BitstampApiWrapper.cancel(order)
    BitstampApiWrapper.orders.should_not include(order)
  end

  def order_book_stub(count: 3, price: 1.5, amount: 2.5)
    Bitstamp.stub(:order_book) do
      {
        'timestamp' => Time.now.to_i.to_s,
        'bids' => count.times.map { |i| [(price + i).to_s, (amount + i).to_s] },
        'asks' => count.times.map { |i| [(price + i).to_s, (amount + i).to_s] }
      }
    end
  end

  it '#order_book' do
    order_book_stub

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

  # [<Bitstamp::Order @id=76, @type=0, @price='1.1', @amount='1.0', @datetime='2013-09-26 23:15:04'>]
  def orders_stub(count: 1, price: 1.5, amount: 2.5)
    Bitstamp.orders.stub(:all) do
      count.times.map do |i|
        double(
          id: i,
          type: (i % 2),
          price: (price + 1).to_s,
          amount: (amount + i).to_s,
          datetime: 1.seconds.ago.strftime('%Y-%m-%d %H:%m:%S')
        )
      end
    end
  end

  it '#orders' do
    orders_stub

    BitstampApiWrapper.orders.all? { |o| o.should be_a(ApiWrapper::Order) }

    order = BitstampApiWrapper.orders.sample
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
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

  # [<Bitstamp::Transactions @tid=14, @price='1.9', @amount='1.1', @date='1380648951'>]
  def transactions_stub(count: 1, price: 1.5, amount: 2.5)
    Bitstamp.stub(:transactions) do
      count.times.map do |i|
        double(
          tid: i,
          date: 1.seconds.ago.to_i,
          price: (price + i).to_s,
          amount: (amount + i).to_s
        )
      end
    end
  end

  it '#transactions' do
    transactions_stub

    BitstampApiWrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = BitstampApiWrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  # [<Bitstamp::UserTransaction @id=76, @order_id=14, @type=1, @usd='0.00', @btc='-3.078', @btc_usd='0.00', @fee='0.00', @datetime='2013-09-26 13:46:59'>]
  def user_transactions_stub(count: 1, usd: 1.5, btc: 2.5, btc_usd: 3.5, fee: 0.05)
    Bitstamp.user_transactions.stub(:all) do
      count.times.map do |i|
        double(
          id: i,
          order_id: i,
          type: (i % 2),
          usd: (usd + i).to_s,
          btc: (btc + i).to_s,
          btc_usd: (btc_usd + i).to_s,
          fee: fee.to_s,
          datetime: 1.seconds.ago.strftime('%Y-%m-%d %H:%m:%S')
        )
      end
    end
  end

  it '#user_transaction' do
    user_transactions_stub
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
