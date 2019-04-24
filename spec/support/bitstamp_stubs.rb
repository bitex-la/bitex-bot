module BitstampStubs
  mattr_accessor(:order_ids) { '0' }
  mattr_accessor(:bids) { [] }
  mattr_accessor(:asks) { [] }
  mattr_accessor(:active_bids) { [] }
  mattr_accessor(:active_asks) { [] }
  mattr_accessor(:user_transactions) { [] }

  def next_bitstamp_order_id
    self.order_ids = self.order_ids.next
  end

  def stub_bitstamp_active_orders
    allow_any_instance_of(BitexBot::Exchanges::Bitstamp).to receive(:orders) do
      BitstampStubs.active_bids + BitstampStubs.active_asks
    end

    allow_any_instance_of(BitexBot::Exchanges::Bitstamp).to receive(:send_order) do |type, price, amount|
      type = type == :buy ? :bid : :ask
      # TODO asumes that this stub acts as taker

      build_bitstamp_order(type, price, amount).tap do |order|
        if type == :bid
          [BitstampStubs.bids, BitstampStubs.active_bids]
        else
          [BitstampStubs.asks, BitstampStubs.active_asks]
        end.each { |orders| orders << order }
      end
    end

    allow_any_instance_of(BitexBot::Exchanges::Bitstamp).to receive(:cancel_order) do |order|
      if order.type == :bid
        BitstampStubs.active_bids
      else
        BitstampStubs.active_asks
      end.delete_if { |o| o.id == order.id  }
      []
    end
  end

  def stub_bitstamp_transactions(price: 0.2, amount: 1, count: 5)
    allow_any_instance_of(BitexBot::Exchanges::Bitstamp).to receive(:transactions) do
      count.times.map { |i| build_bitstamp_transaction(i, price, amount, (i+1).seconds.ago) }
    end
  end

  # Takes all active orders and mockes them as executed in a single transaction.
  # If a ratio is provided then each order is only partially executed and added
  # as a transaction and the order itself is kept in the order list.
  def stub_bitstamp_hit_orders_into_transactions(options = {})
    ratio = (options[:ratio] || 1).to_d
    (BitstampStubs.active_bids + BitstampStubs.active_asks).each do |order|
      fiat = order.amount * order.price
      fiat, crypto, trade_type = order.type == :bid ? [-fiat, order.amount, 'buys'] : [fiat, -order.amount, 'sells']

      BitstampStubs.user_transactions << BitexBot::Exchanges::UserTransaction.new(
        order.id, fiat * ratio, crypto * ratio, order.price, 0.5.to_d, trade_type, Time.now.strftime('%F %T'), double
      )
    end

    [BitstampStubs.active_bids, BitstampStubs.active_asks].each(&:clear) if ratio == 1
    allow_any_instance_of(BitexBot::Exchanges::Bitstamp).to receive(:user_transactions).and_return(BitstampStubs.user_transactions)
  end

   def stub_bitstamp_balance(fiat = nil, crypto = nil, fee = nil)
     allow_any_instance_of(BitexBot::Exchanges::Bitstamp).to receive(:balance) do
      BitexBot::Exchanges::BalanceSummary.new(
        BitexBot::Exchanges::Balance.new((crypto || 10).to_d, 0, (crypto || 10).to_d),
        BitexBot::Exchanges::Balance.new((fiat || 100).to_d, 0, (fiat || 100).to_d),
        (fee || 0.5).to_d
      )
    end
  end

  def stub_bitstamp_market
    allow_any_instance_of(BitexBot::Exchanges::Bitstamp).to receive(:market) do
      BitexBot::Exchanges::Orderbook.new(
        Time.now.to_i,
        [[30, 3], [25, 2], [20, 1.5], [15, 4], [10, 5]].map do |price, amount|
          BitexBot::Exchanges::OrderSummary.new(price.to_d, amount.to_d)
        end,
        [[10, 2], [15, 3], [20, 1.5], [25, 3], [30, 3]].map do |price, amount|
          BitexBot::Exchanges::OrderSummary.new(price.to_d, amount.to_d)
        end
      )
    end
  end

  # @param [Symbol] type. <:bid|:ask>
  # @param [Numeric] price.
  # @param [Numeric] amount.
  # @param [Symbol] orderbook_code.
  # @param [Symbol] status. <:executing|:completed|:cancelled>
  # @param [Time] created_at. UTC.
  #
  # return [BitexBot::Exchanges::Order]
  def build_bitstamp_order(type, price, amount, created_at = Time.now.utc, id = next_bitex_order_id)
    raw_type = type == :buy ? 0 : 1 # { 0: buy/bid, 1: sell/ask }
    raw = double(
      id: id,
      type: raw_type,
      amount: amount.to_s,
      price: price.to_s,
      datetime: created_at.strftime('%F %T')
    )

    order_type = type == :buy ? :bid : :ask
    BitexBot::Exchanges::Order.new(raw.id, type, price.to_d, amount.to_d, created_at.to_i, :executing, 'client_order_id', raw)
  end

  # @param [Numeric] id. IDs trade.
  # @param [Numeric] price.
  # @param [Numeric] amount.
  # @param [Time] created_at. UTC.
  #
  # return [BitexBot::Exchanges::Order]
  def build_bitstamp_transaction(id, price, amount, created_at = Time.now.utc)
    BitexBot::Exchanges::Transaction.new(id.to_s, price.to_d, amount.to_d, created_at.to_i, double)
  end

  def stub_bitstamp_reset
    BitstampStubs.order_ids = '0'
    BitstampStubs.bids.clear
    BitstampStubs.asks.clear
    BitstampStubs.active_bids.clear
    BitstampStubs.active_asks.clear
    BitstampStubs.user_transactions.clear
  end
end
RSpec.configuration.include BitstampStubs
