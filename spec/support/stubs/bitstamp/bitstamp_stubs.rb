module BitstampStubs
  # Robot stubs
  def stub_bitstamp_order_book
    Bitstamp.stub(:order_book) do
      {
        'timestamp' => Time.now.to_i.to_s,
        'bids' => [%w[30 3], %w[25 2], %w[20 1.5], %w[15 4], %w[10 5]],
        'asks' => [%w[10 2], %w[15 3], %w[20 1.5], %w[25 3], %w[30 3]]
      }
    end
  end

  # [<Bitstamp::Transactions @date="1380648951", @tid=14, @price="1.9", @amount="1.1">]
  def stub_bitstamp_transactions(price = 0.2, amount = 1)
    Bitstamp.stub(:transactions) do
      5.times.map { |i| double(tid: i, date: (i+1).seconds.ago.to_i.to_s, price: price.to_s, amount: amount.to_s) }
    end
  end

  # ApiWrapper stubs
  def stub_bitstamp_balance(balance: '0.5', reserved: '1.5', available: '2.0', fee: '0.2')
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

  # [<Bitstamp::Order @id=76, @type=0, @price='1.1', @amount='1.0', @datetime='2013-09-26 23:15:04'>]
  def stub_bitstamp_orders(count: 1, price: 1.5, amount: 2.5)
    Bitstamp.orders.stub(:all) do
      count.times.map do |i|
        double(
          id: i + 1,
          type: i % 2,
          price: (price + 1).to_s,
          amount: (amount + i).to_s,
          datetime: 1.seconds.ago.strftime('%Y-%m-%d %H:%m:%S')
        )
      end
    end
  end

  def stub_bitstamp_order_book(count: 3, price: 1.5, amount: 2.5)
    Bitstamp.stub(:order_book) do
      {
        'timestamp' => Time.now.to_i.to_s,
        'bids' => count.times.map { |i| [(price + i).to_s, (amount + i).to_s] },
        'asks' => count.times.map { |i| [(price + i).to_s, (amount + i).to_s] }
      }
    end
  end

  # [<Bitstamp::UserTransaction @id=76, @order_id=14, @type=1, @usd='0.00', @btc='-3.078', @btc_usd='0.00', @fee='0.00', @datetime='2013-09-26 13:46:59'>]
  def stub_bitstamp_user_transactions(count: 1, usd: 1.5, btc: 2.5, btc_usd: 3.5, fee: 0.05)
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

  # Buy/SellClosingFlow stubs
  def stub_bitstamp_empty_user_transactions
    Bitstamp.stub(user_transactions: double(all: []))
  end

  # Takes all active orders and mockes them as executed in a single transaction.
  # If a ratio is provided then each order is only partially executed and added as a transaction and the order itself is kept in
  # the order list.
  def stub_bitstamp_orders_into_transactions(options = {})
    ratio = options[:ratio] || 1
    transactions = Bitstamp.orders.all.map { |o| transaction(o, *usd_and_btc(o), ratio) }
    Bitstamp.stub(user_transactions: double(all: transactions))

    return unless ratio == 1
    stub_bitstamp_trade(:sell)
    stub_bitstamp_trade(:buy)
  end

  def stub_bitstamp_trade(trade_type, remote_id = nil, orders = [])
    ensure_bitstamp_orders_stub
    Bitstamp.orders.stub(all: orders)
    Bitstamp.orders.stub(trade_type) do |o|
      remote_id = Bitstamp.orders.all.size + 1 if remote_id.nil?
      order(order_type(trade_type), remote_id, o[:amount], o[:price]).tap do |thing|
        thing.stub(:cancel!) do
          orders = Bitstamp.orders.all.reject { |o| o.id == thing.id && send(:"#{trade_type}?", o) }
          stub_bitstamp_trade(trade_type, remote_id + 1, orders)
        end
        stub_bitstamp_trade(trade_type, remote_id + 1, Bitstamp.orders.all + [thing])
      end
    end
  end

  private

  def ensure_bitstamp_orders_stub
    Bitstamp.orders
  rescue Exception => e
    Bitstamp.stub(orders: double)
  end

  def order(order_type, remote_id, amount, price)
    double(id: remote_id, type: types[:orders][order_type], amount: amount, price: price, datetime: DateTime.now.to_s)
  end

  def transaction(order, usd, btc, ratio)
    double(
      usd: (usd * ratio).to_s,
      btc: (btc * ratio).to_s,
      btc_usd: order.price.to_s,
      order_id: order.id,
      fee: '0.5',
      type: 2,
      datetime: DateTime.now.to_s
    )
  end

  def usd_and_btc(order)
    usd = order.amount * order.price
    buy?(order) ? [-usd, order.amount] : [usd, -order.amount]
  end

  def order_type(type)
    types[:trades][type]
  end

  %i[buy sell].each do |trade_type|
    define_method("#{trade_type}?") { |order| types[:operations][order.type] == trade_type }
  end

  def types
    {
      orders: { bid: 0, ask: 1 },
      operations: { 0 => :buy, 1 => :sell },
      trades: { buy: :bid, sell: :ask }
    }
  end
end
