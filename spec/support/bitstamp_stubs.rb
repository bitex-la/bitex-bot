module BitstampStubs
  def stub_bitstamp_balance(usd = nil, coin = nil, fee = nil)
    Bitstamp.stub(balance: bitstamp_balance_stub(usd, coin, fee))
  end
  
  def bitstamp_balance_stub(usd = nil, coin = nil, fee = nil)
    {"btc_balance"=> coin || "10.0", "btc_reserved"=> "0", "btc_available"=> coin || "10.0",
     "usd_balance"=> usd || "100.0", "usd_reserved"=>"0", "usd_available"=> usd || "100.0",
     "fee"=> fee || "0.5000"}
  end

  def stub_bitstamp_order_book
    Bitstamp.stub(order_book: bitstamp_order_book_stub)
  end
  
  def bitstamp_order_book_stub
    { 'timestamp' => Time.now.to_i.to_s,
      'bids' =>
        [['30', '3'], ['25', '2'], ['20', '1.5'], ['15', '4'], ['10', '5']],
      'asks' =>
        [['10', '2'], ['15', '3'], ['20', '1.5'], ['25', '3'], ['30', '3']]
    }
  end
  
  def stub_bitstamp_transactions(volume = 0.2)
    Bitstamp.stub(transactions: bitstamp_transactions_stub(volume))
  end
  
  def bitstamp_transactions_stub(price = 30, amount = 1)
    transactions = 5.times.collect do |i|
      double(
        tid:i,
        date: (i+1).seconds.ago.to_i.to_s,
        price: price.to_s,
        amount: amount.to_s
      )
    end
  end

  def stub_bitstamp_user_transactions
    Bitstamp.stub(user_transactions: double(all: []))
  end
  
  # Takes all active orders and mockes them as executed in a single transaction.
  # If a ratio is provided then each order is only partially executed and added
  # as a transaction and the order itself is kept in the order list.
  def stub_bitstamp_orders_into_transactions(options={})
    ratio = options[:ratio] || 1
    orders = Bitstamp.orders.all
    transactions = orders.collect do |o|
      usd = o.amount * o.price
      usd, btc = o.type == 0 ? [-usd, o.amount] : [usd, -o.amount]
      double(usd: (usd * ratio).to_s, btc: (btc * ratio).to_s,
        btc_usd: o.price.to_s, order_id: o.id, fee: "0.5", type: 2,
        datetime: DateTime.now.to_s)
    end
    Bitstamp.stub(user_transactions: double(all: transactions))

    if ratio == 1
      stub_bitstamp_sell
      stub_bitstamp_buy
    end
  end
  
  def ensure_bitstamp_orders_stub
    begin
      Bitstamp.orders
    rescue Exception => e
      Bitstamp.stub(orders: double) 
    end
  end
  
  def stub_bitstamp_sell(remote_id=nil, orders = [])
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

  def stub_bitstamp_buy(remote_id=nil, orders = [])
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
end

RSpec.configuration.include BitstampStubs
