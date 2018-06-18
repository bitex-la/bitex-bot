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
      build(:bitex_bid, id: 12_345, order_book: order_book, status: :executing, amount: to_spend, remaining_amount: to_spend, price: price).tap do |bid|
        bid.stub(:cancel!) do
          bid.tap do
            bid.status = :cancelled
            BitexStubs.active_bids.delete(bid.id)
          end
        end
        BitexStubs.bids[bid.id] = bid
        BitexStubs.active_bids[bid.id] = bid
      end
    end

    Bitex::Ask.stub(:create!) do |order_book, to_sell, price|
      build(:bitex_ask, id: 12_345, order_book: order_book, quantity: to_sell, remaining_quantity: to_sell, price: price, status: :executing).tap do |ask|
        ask.stub(:cancel!) do
          ask.tap do
            ask.status = :cancelled
            BitexStubs.active_asks.delete(ask.id)
          end
        end
        BitexStubs.asks[ask.id] = ask
        BitexStubs.active_asks[ask.id] = ask
      end
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

  # <Bitex::Buy:0x007ff9a2979390
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @quantity=0.2e1, @amount=0.6e3, @fee=0.5e-1,
  #   @price=0.3e3, @bid_id=123
  # >
  # <Bitex::Sell:0x007ff9a2978710
  #   @id=12345678, @created_at=1999-12-31 21:10:00 -0300, @order_book=:btc_usd, @quantity=0.2e1, @amount=0.6e3, @fee=0.5e-1,
  #   @price=0.3e3, @ask_id=456i
  # >
  def stub_bitex_trades
    Bitex::Trade.stub(all: [build(:bitex_buy), build(:bitex_sell)])
  end
end

RSpec.configuration.include BitexStubs
