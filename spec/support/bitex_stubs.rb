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

    allow_any_instance_of(BitexApiWrapper).to receive(:bid_by_id) do |id|
      bids.find { |bid| bid.id == id.to_s }
    end

    allow_any_instance_of(BitexApiWrapper).to receive(:ask_by_id) do |id|
      asks.find { |ask| ask.id == id.to_s }
    end

    allow_any_instance_of(BitexApiWrapper).to receive(:send_order) do |type, price, amount|
      type = type == :buy ? :bid : :ask
      orderbook_code = BitexBot::Robot.maker.base_quote.to_sym

      build_bitex_order(type, price, amount, orderbook_code).tap do |order|
        if type == :bid
          [BitexStubs.bids, BitexStubs.active_bids]
        else
          [BitexStubs.asks, BitexStubs.active_asks]
        end.each { |orders| orders << order }
      end
    end

    allow_any_instance_of(BitexApiWrapper).to receive(:cancel_order) do |order|
      if order.type == :bid
        BitexStubs.bids
      else
        BitexStubs.asks
      end.find { |o| o.id == order.id  }.status = :cancelled
      []
    end
  end

  def stub_bitex_transactions(*extra_trades)
    orderbook_code = BitexBot::Robot.maker.base_quote.to_sym

    buy = build_bitex_user_transaction(:buy, 123, 600, 2, 300, 0.05, orderbook_code)
    sell = build_bitex_user_transaction(:sell, 246, 600, 2, 300, 0.05, orderbook_code)

    allow_any_instance_of(BitexApiWrapper).to receive(:trades).and_return(extra_trades + [buy, sell])
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
    order_type = { buy: :bid, sell: :ask, dont_care: :dont_care }[type]
    raw = double(
      type: type.to_s.pluralize,
      id: rand(1_000_000).to_s,
      created_at: created_at,
      coin_amount: coin_amount.to_d,
      cash_amount: cash_amount.to_d,
      fee: fee.to_d,
      price: price.to_d,
      fee_currency: :dont_care_but_is_maker_base_currency,
      fee_decimals: 8,
      orderbook_code: orderbook_code,
      relationships: {
        'order' => {
          'data' => {
            'id' => order_id.to_s,
            'type' => order_type.to_s.pluralize
          }
        }
      }
    )

    ApiWrapper::UserTransaction.new(order_id.to_s, cash_amount.to_d, coin_amount.to_d, price, fee.to_d, raw.type, created_at.to_i, raw)
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

=begin
  # {
  #   usd_balance: 10000.0,
  #   usd_reserved: 2000.0,
  #   usd_available: 8000.0,
  #   btc_balance: 20.0,
  #   btc_reserved: 5.0,
  #   btc_available: 15.0,
  #   fee: 0.5,
  #   btc_deposit_address: "1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  # }
  def stub_bitex_balance
    Bitex::Profile.stub(:get) do
      {
        usd_balance: 10_000.to_d,
        usd_reserved: 2_000.to_d,
        usd_available: 8_000.to_d,
        btc_balance: 20.to_d,
        btc_reserved: 5.to_d,
        btc_available: 15.to_d,
        fee: 0.5.to_d,
        btc_deposit_address: '1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'
      }
    end
  end

  # <Bitex::Bid:0x007ff7efe1f228
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @orderbook=:btc_usd, @price=0.1e4, @status=:received,
  #   @reason=:not_cancelled, @issuer="User#1", @amount=0.1e3, @remaining_amount=0.1e3, @produced_quantity=0.1e2
  # >
  # <Bitex::Ask:0x007f94a2658f68
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @orderbook=:btc_usd, @price=0.1e4, @status=:received,
  #   @reason=:not_cancelled, @issuer="User#1", @quantity=0.1e3, @remaining_quantity=0.1e3, @produced_amount=0.1e2
  # >
  def stub_bitex_orders
    Bitex::Order.stub(all: [build(:bitex_bid), build(:bitex_ask)])
  end

  def stub_bitex_order_book
    Bitex::MarketData.stub(:order_book) do
      {
        bids: [[639.21, 1.95], [637.0, 0.47], [630.0, 1.58]],
        asks: [[642.4, 0.4], [643.3, 0.95], [644.3, 0.25]]
      }
    end
  end
=end
