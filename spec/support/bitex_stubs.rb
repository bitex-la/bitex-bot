module BitexStubs
  mattr_accessor(:order_ids) { '0' }
  mattr_accessor(:bids) { [] }
  mattr_accessor(:asks) { [] }
  mattr_accessor(:active_bids) { [] }
  mattr_accessor(:active_asks) { [] }

  def next_bitex_order_id
    self.order_ids = self.order_ids.next
  end

  def stub_bitex_active_orders
    allow_any_instance_of(BitexApiWrapper).to receive(:orders) do
      active_bids + active_asks
    end

    allow_any_instance_of(BitexApiWrapper).to receive(:order_by_id) do |type, id|
      { buy: bids, sell: asks }[type].find { |raw_order| raw_order.id == id.to_s }
    end

    allow_any_instance_of(BitexApiWrapper).to receive(:send_order) do |type, price, amount|
      type = type == :buy ? :bid : :ask
      orderbook_code = BitexBot::Robot.maker.base_quote.to_sym

      build_bitex_order(type, price, amount, orderbook_code).tap do |order|
        add_bitex_order(order)
      end
    end

    allow_any_instance_of(BitexApiWrapper).to receive(:cancel_order) do |order|
      if order.type == :bid
        [BitexStubs.bids, BitexStubs.active_bids]
      else
        [BitexStubs.asks, BitexStubs.active_asks]
      end.tap do |all_orders, active_orders|
        all_orders.find { |o| o.id == order.id  }.status = :cancelled
        active_orders.delete_if { |o| o.id == order.id }
      end
      []
    end
  end

  def add_bitex_order(order)
    if order.type == :bid
      [BitexStubs.bids, BitexStubs.active_bids]
    else
      [BitexStubs.asks, BitexStubs.active_asks]
    end.each { |orders| orders << order }
  end

  def stub_bitex_transactions(*extra_trades)
    orderbook_code = BitexBot::Robot.maker.base_quote.to_sym

    buy = build_bitex_user_transaction(:buy, 123, 600, 2, 300, 0.05, orderbook_code)
    sell = build_bitex_user_transaction(:sell, 246, 600, 2, 300, 0.05, orderbook_code)

    allow_any_instance_of(BitexApiWrapper).to receive(:trades).and_return(extra_trades + [buy, sell])
  end

  # @param [Hash] crypto. {:total, :availabe}
  # @param [Hash] fiat. {:total, :availabe}
  # @param [Numeric] trading_fee.
  #
  # return [BitexApiWrapper::BalanceSummary]
  def stub_bitex_balance(crypto: {}, fiat: {}, trading_fee: 0.05)
    allow_any_instance_of(BitexApiWrapper).to receive(:balance).and_return(build_bitex_balance_summary(crypto, fiat, trading_fee))
  end

  def build_bitex_balance_summary(crypto, fiat, trading_fee)
    BitexApiWrapper::BalanceSummary.new(
      build_bitex_balance(crypto),
      build_bitex_balance(fiat),
      trading_fee.to_d
    )
  end

  def build_bitex_balance(balance)
    BitexApiWrapper::Balance.new(
      balance[:total].to_d,
      (balance[:total] - balance[:available]).to_d,
      balance[:available].to_d
    )
  end

  # @param [Symbol] type. <:buy|:sell>
  # @param [Numeric] order_id.
  # @param [Numeric] coin_amount.
  # @param [Numeric] cash_amount.
  # @param [Numeric] price.
  # @param [Numeric] fee.
  # @param [Symbol] orderbook_code.
  # @param [Time] created_at. UTC
  #
  # return [ApiWrapper::UserTransaction]
  def build_bitex_user_transaction(type, order_id, cash_amount, coin_amount, price, fee, orderbook_code, created_at = Time.now.utc)
    trade_id = rand(1_000_000)
    raw = build_bitex_raw_trade(type, trade_id, order_id, cash_amount, coin_amount, price, fee, orderbook_code, created_at)
    ApiWrapper::UserTransaction.new(order_id.to_s, cash_amount.to_d, coin_amount.to_d, price, fee.to_d, raw.type, created_at.to_i, raw)
  end

  def build_bitex_raw_trade(type, id, order_id, cash_amount, coin_amount, price, fee, orderbook_code, created_at)
    Bitex::Resources::Trades::Trade.new(
      type: type.to_s.pluralize,
      id: id.to_s,
      cash_amount: cash_amount.to_d,
      coin_amount: coin_amount.to_d,
      price: price.to_d,
      fee: fee.to_d,
      fee_currency: :dont_care,
      fee_decimals: 8,
      orderbook_code: orderbook_code.to_s,
      created_at: created_at,
      relationships: {
        'order' => {
          'data' => {
            'id' => order_id.to_s,
            'type' => { buy: :bid, sell: :ask, dont_care: :dont_care }[type].to_s.pluralize
          }
        }
      }
    )
  end

  # @param [Symbol] type. <:bid|:ask>
  # @param [Numeric] price.
  # @param [Numeric] amount.
  # @param [Symbol] orderbook_code.
  # @param [Symbol] status. <:executing|:completed|:cancelled>
  # @param [Time] created_at. UTC.
  #
  # return [BitexApiWrapper::Order]
  def build_bitex_order(type, price, amount, orderbook_code, status = :executing, created_at = Time.now.utc, id = next_bitex_order_id)
    # TODO: add status member to order wrapper
    raw = double(
      type: type.to_s.pluralize,
      id: id,
      amount: amount.to_d,
      remaining_quantity: amount.to_d,
      price: price.to_d,
      status: status,
      orderbook_code: orderbook_code,
      created_at: created_at
    )

    BitexApiWrapper::Order.new(raw.id, type, price.to_d, amount.to_d, created_at.to_i, status, raw)
  end

  def stub_bitex_reset
    BitexStubs.order_ids = '0'
    BitexStubs.bids.clear
    BitexStubs.asks.clear
    BitexStubs.active_bids.clear
    BitexStubs.active_asks.clear
  end
end

RSpec.configuration.include BitexStubs
