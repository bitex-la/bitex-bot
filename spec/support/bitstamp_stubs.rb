module BitstampStubs
  def stub_bitstamp_balance(usd = nil, coin = nil, fee = nil)
    Bitstamp.stub(balance: bitstamp_balance(usd, coin, fee))
  end

  def stub_bitstamp_order_book
    Bitstamp.stub(order_book: bitstamp_order_book_stub)
  end

  # [#<Bitstamp::Order @price="1.1", @amount="1.0", @type=0, @id=76, @datetime="2013-09-26 23:15:04">]
  def stub_bitstamp_orders
    Bitstamp.orders.stub(:all) do
      [double(id: 76, type: 0, amount: '1.23', price: '4.56', datetime:  '23:26:56.849475')]
    end
  end

  def bitstamp_order_book_stub
    {
      'timestamp' => Time.now.to_i.to_s,
      'bids' =>
        [['30', '3'], ['25', '2'], ['20', '1.5'], ['15', '4'], ['10', '5']],
      'asks' =>
        [['10', '2'], ['15', '3'], ['20', '1.5'], ['25', '3'], ['30', '3']]
    }
  end

  def stub_bitstamp_transactions(volume = 0.2)
    Bitstamp.stub(transactions: bitstamp_transactions_stub(volume))
  end

  # [<Bitstamp::Transactions @date="1380648951", @tid=14, @price="1.9", @amount="1.1">]
  def bitstamp_transactions_stub(price = 30, amount = 1)
    transactions = 5.times.collect do |i|
      double(tid:i, date: (i+1).seconds.ago.to_i.to_s, price: price.to_s, amount: amount.to_s)
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

  def stub_bitstamp_user_transactions_empty
    Bitstamp.stub(user_transactions: double(all: []))
  end

  # Takes all active orders and mockes them as executed in a single transaction.
  # If a ratio is provided then each order is only partially executed and added
  # as a transaction and the order itself is kept in the order list.
  def stub_bitstamp_orders_into_transactions(options = {})
    ratio = options[:ratio] || 1
    orders = Bitstamp.orders.all
    transactions = orders.collect do |o|
      usd = o.amount * o.price
      usd, btc = o.type == 0 ? [-usd, o.amount] : [usd, -o.amount]
      double(usd: (usd * ratio).to_s, btc: (btc * ratio).to_s,
        btc_usd: o.price.to_s, order_id: o.id, fee: '0.5', type: 2,
        datetime: DateTime.now.to_s)
    end
    Bitstamp.stub(user_transactions: double(all: transactions))

    return unless ratio == 1
    stub_bitstamp_sell
    stub_bitstamp_buy
  end

  def ensure_bitstamp_orders_stub
    Bitstamp.orders
  rescue Exception => e
    Bitstamp.stub(orders: double)
  end

  def stub_bitstamp_sell(remote_id = nil, orders = [])
    ensure_bitstamp_orders_stub
    Bitstamp.orders.stub(all: orders)
    Bitstamp.orders.stub(:sell) do |args|
      remote_id = Bitstamp.orders.all.size + 1 if remote_id.nil?
      ask = double(amount: args[:amount], price: args[:price],
        type: 1, id: remote_id, datetime: DateTime.now.to_s)
      ask.stub(:cancel!) do
        orders = Bitstamp.orders.all.reject do |x|
          x.id.to_s == ask.id.to_s && x.type == 1
        end
        stub_bitstamp_sell(remote_id + 1, orders)
      end
      stub_bitstamp_sell(remote_id + 1, Bitstamp.orders.all + [ask])
      ask
    end
  end

  def stub_bitstamp_buy(remote_id = nil, orders = [])
    ensure_bitstamp_orders_stub
    Bitstamp.orders.stub(all: orders)
    Bitstamp.orders.stub(:buy) do |args|
      remote_id = Bitstamp.orders.all.size + 1 if remote_id.nil?
      bid = double(amount: args[:amount], price: args[:price],
        type: 0, id: remote_id, datetime: DateTime.now.to_s)
      bid.stub(:cancel!) do
        orders = Bitstamp.orders.all.reject do |x|
          x.id.to_s == bid.id.to_s && x.type == 0
        end
        stub_bitstamp_buy(remote_id + 1, orders)
      end
      stub_bitstamp_buy(remote_id + 1, Bitstamp.orders.all + [bid])
      bid
    end
  end

  private

  def bitstamp_balance(usd = nil, coin = nil, fee = nil)
    {
      'btc_balance' => coin || '10.0', 'btc_reserved' => '0', 'btc_available' => coin || '10.0',
      'usd_balance' => usd || '100.0', 'usd_reserved' => '0', 'usd_available' => usd || '100.0',
      'fee' => fee || '0.5'
    }
  end
end

RSpec.configuration.include BitstampStubs
