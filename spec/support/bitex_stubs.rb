module BitexStubs
  mattr_accessor(:bids) { {} }
  mattr_accessor(:asks) { {} }
  mattr_accessor(:active_bids) { {} }
  mattr_accessor(:active_asks) { {} }

  def stub_bitex_active_orders
    Bitex::Order.stub(:all) do
      BitexStubs.active_bids.merge(BitexStubs.active_asks)
    end

    Bitex::Bid.stub(:find) do |id|
      BitexStubs.bids[id]
    end

    Bitex::Ask.stub(:find) do |id|
      BitexStubs.asks[id]
    end

    Bitex::Bid.stub(:create!) do |order_book, to_spend, price|
      bid = Bitex::Bid.new
      bid.id = 12345
      bid.created_at = Time.now
      bid.price = price
      bid.amount = to_spend
      bid.remaining_amount = to_spend
      bid.status = :executing
      bid.order_book = order_book
      bid.stub(:cancel!) do
        bid.status = :cancelled
        BitexStubs.active_bids.delete(bid.id)
        bid
      end
      BitexStubs.bids[bid.id] = bid
      BitexStubs.active_bids[bid.id] = bid
      bid
    end

    Bitex::Ask.stub(:create!) do |order_book, to_sell, price|
      ask = Bitex::Ask.new
      ask.id = 12345
      ask.created_at = Time.now
      ask.price = price
      ask.quantity = to_sell
      ask.remaining_quantity = to_sell
      ask.status = :executing
      ask.order_book = order_book
      ask.stub(:cancel!) do
        ask.status = :cancelled
        BitexStubs.active_asks.delete(ask.id)
        ask
      end
      BitexStubs.asks[ask.id] = ask
      BitexStubs.active_asks[ask.id] = ask
      ask
    end
  end

  def stub_bitex_transactions(*extra_transactions)
    Bitex::Trade.stub(all: extra_transactions + [build(:bitex_buy), build(:bitex_sell)])
  end

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
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @price=0.1e4, @status=:received,
  #   @reason=:not_cancelled, @issuer="User#1", @amount=0.1e3, @remaining_amount=0.1e3, @produced_quantity=0.1e2
  # >
  # <Bitex::Ask:0x007f94a2658f68
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @price=0.1e4, @status=:received,
  #   @reason=:not_cancelled, @issuer="User#1", @quantity=0.1e3, @remaining_quantity=0.1e3, @produced_amount=0.1e2
  # >
  def stub_bitex_orders
    Bitex::Order.stub(:all) do
      [
        Bitex::Bid.new.tap do |bid|
          bid.id = 12_345_678
          bid.created_at = Time.now
          bid.order_book = BitexBot::Settings.maker.order_book
          bid.price = 1_000.to_d
          bid.status = :executing
          bid.amount = 100.to_d
          bid.remaining_amount = 100.to_d
          bid.stub(:cancel!) do
            bid.tap { bid.status = :cancelled }
          end
        end,

        Bitex::Ask.new.tap do |ask|
          ask.id = 12345679
          ask.created_at = Time.now
          ask.order_book = BitexBot::Settings.maker.order_book
          ask.price = 1_000.to_d
          ask.status = :executing
          ask.quantity = 100.to_d
          ask.remaining_quantity = 100.to_d
          ask.stub(:cancel!) do
            ask.tap { ask.status = :cancelled }
          end
        end
      ]
    end
  end

  def stub_bitex_order_book
    Bitex::MarketData.stub(:order_book) do
      {
        bids: [[639.21, 1.95], [637.0, 0.47], [630.0, 1.58]],
        asks: [[642.4, 0.4], [643.3, 0.95], [644.3, 0.25]]
      }
    end
  end

  # <Bitex::Buy:0x007ff9a2979390
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @quantity=0.2e1, @amount=0.6e3, @fee=0.5e-1,
  #   @price=0.3e3, @bid_id=123
  # >
  #
  # <Bitex::Sell:0x007ff9a2978710
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @quantity=0.2e1, @amount=0.6e3, @fee=0.5e-1,
  #   @price=0.3e3, @ask_id=456i
  # >
  def stub_bitex_user_transactions
    Bitex::Trade.stub(all: [build(:bitex_buy), build(:bitex_sell)])
  end
end

RSpec.configuration.include BitexStubs
