module BitstampStubs
  def stub_bitstamp_order_book
    Bitstamp.stub(:order_book) do
      {
        'timestamp' => Time.now.to_i.to_s,
        'bids' => [['30', '3'], ['25', '2'], ['20', '1.5'], ['15', '4'], ['10', '5']],
        'asks' => [['10', '2'], ['15', '3'], ['20', '1.5'], ['25', '3'], ['30', '3']]
      }
    end
  end

  # [<Bitstamp::Transactions @date="1380648951", @tid=14, @price="1.9", @amount="1.1">]
  def stub_bitstamp_transactions(price = 0.2, amount = 1 )
    Bitstamp.stub(:transactions) do
      5.times.collect do |i|
        double(tid: i, date: (i+1).seconds.ago.to_i.to_s, price: price.to_s, amount: amount.to_s)
      end
    end
  end

  # TODO It's only used into robot_spec buy/sell_closing_flow
  def stub_bitstamp_empty_user_transactions
    Bitstamp.stub(user_transactions: double(all: []))
  end

  # TODO It's only used into robot_spec buy/sell_closing_flow
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

  # TODO It's only used into robot_spec buy/sell_closing_flow_spec
  def stub_bitstamp_sell(remote_id = nil, orders = [])
    ensure_bitstamp_orders_stub
    Bitstamp.orders.stub(all: orders)
    Bitstamp.orders.stub(:sell) do |args|
      remote_id = Bitstamp.orders.all.size + 1 if remote_id.nil?
      ask = double(amount: args[:amount], price: args[:price], type: 1, id: remote_id,
        datetime: DateTime.now.to_s)
      ask.stub(:cancel!) do
        orders = Bitstamp.orders.all.reject { |o| o.id.to_s == ask.id.to_s && o.type == 1 }
        stub_bitstamp_sell(remote_id + 1, orders)
      end
      stub_bitstamp_sell(remote_id + 1, Bitstamp.orders.all + [ask])
      ask
    end
  end

  # TODO It's only used into robot_spec buy/sell_closing_flow_spec
  def stub_bitstamp_buy(remote_id = nil, orders = [])
    ensure_bitstamp_orders_stub
    Bitstamp.orders.stub(all: orders)
    Bitstamp.orders.stub(:buy) do |args|
      remote_id = Bitstamp.orders.all.size + 1 if remote_id.nil?
      bid = double(amount: args[:amount], price: args[:price], type: 0, id: remote_id,
        datetime: DateTime.now.to_s)
      bid.stub(:cancel!) do
        orders = Bitstamp.orders.all.reject { |o| o.id.to_s == bid.id.to_s && o.type == 0 }
        stub_bitstamp_buy(remote_id + 1, orders)
      end
      stub_bitstamp_buy(remote_id + 1, Bitstamp.orders.all + [bid])
      bid
    end
  end

  private

  # TODO It's only used into robot_spec buy/sell_closing_flow_spec
  def ensure_bitstamp_orders_stub
    Bitstamp.orders
  rescue Exception => e
    Bitstamp.stub(orders: double)
  end
end

RSpec.configuration.include BitstampStubs
