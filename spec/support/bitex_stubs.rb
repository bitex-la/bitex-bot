module BitexStubs
  mattr_accessor(:bids) { {} }
  mattr_accessor(:asks) { {} }
  mattr_accessor(:active_bids) { {} }
  mattr_accessor(:active_asks) { {} }

  def stub_bitex_orders
    Bitex::Order.stub(:all) { BitexStubs.active_bids + BitexStubs.active_asks }

    Bitex::Bid.stub(:find) { |id| BitexStubs.bids[id] }

    Bitex::Ask.stub(:find) { |id| BitexStubs.asks[id] }

    Bitex::Bid.stub(:create!) do |orderbook, to_spend, price|
      orderbook.should eq BitexBot::Robot.orderbook

      Bitex::Bid.new.tap do |bid|
        bid.id = 12345
        bid.created_at = Time.now
        bid.price = price
        bid.amount = to_spend
        bid.remaining_amount = to_spend
        bid.status = :executing
        bid.orderbook = orderbook
        bid.stub(:cancel!) do
          bid.status = :cancelled
          BitexStubs.active_bids.delete(bid.id)
          bid
        end
        BitexStubs.bids[bid.id] = bid
        BitexStubs.active_bids[bid.id] = bid
      end
    end

    Bitex::Ask.stub(:create!) do |orderbook, to_sell, price|
      orderbook.should eq BitexBot::Robot.orderbook

      Bitex::Ask.new.tap do |ask|
        ask.id = 12345
        ask.created_at = Time.now
        ask.price = price
        ask.quantity = to_sell
        ask.remaining_quantity = to_sell
        ask.status = :executing
        ask.orderbook = orderbook
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
  end

  def stub_bitex_transactions(*extra_transactions)
    Bitex::Trade.stub(all: extra_transactions + [build(:bitex_buy), build(:bitex_sell)])
  end
end

RSpec.configuration.include BitexStubs
