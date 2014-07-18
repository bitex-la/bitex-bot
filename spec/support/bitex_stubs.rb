module BitexStubs
  def ensure_bitex_orders_stub
    begin
      Bitex::Order.active
    rescue Exception => e
      Bitex::Order.stub(active: [])
    end
  end

  def stub_bitex_bid_create
    ensure_bitex_orders_stub
    Bitex::Bid.stub(:create!) do |specie, to_spend, price|
      bid = Bitex::Bid.new
      bid.id = 12345
      bid.created_at = Time.now
      bid.price = price
      bid.amount = to_spend
      bid.remaining_amount = to_spend
      bid.status = :executing 
      bid.specie = specie
      bid.stub(cancel!: true) do
        bid.status = :cancelling
        bid
      end
      Bitex::Order.stub(active: Bitex::Order.active + [bid])
      bid
    end
  end

  def stub_bitex_ask_create
    ensure_bitex_orders_stub
    Bitex::Ask.stub(:create!) do |specie, to_sell, price|
      ask = Bitex::Ask.new
      ask.id = 12345
      ask.created_at = Time.now
      ask.price = price
      ask.quantity = to_sell
      ask.remaining_quantity = to_sell
      ask.status = :executing 
      ask.specie = specie
      ask.stub(cancel!: true) do
        ask.status = :cancelling
        ask
      end
      Bitex::Order.stub(active: Bitex::Order.active + [ask])
      ask
    end
  end
  
  
  def stub_bitex_transactions(*extra_transactions)
    Bitex::Transaction.stub(all: extra_transactions + [
      build(:bitex_buy),
      build(:bitex_sell),
      Bitex::SpecieWithdrawal
        .from_json([6,Time.now.to_i,946685400,1,100.00000000,1,0]),
      Bitex::UsdWithdrawal
        .from_json([8,Time.now.to_i,946685400,100.00000000,1,0]),
      Bitex::UsdDeposit
        .from_json([7,Time.now.to_i,946685400,1000.00000000,1,1,0]),
      Bitex::SpecieDeposit
        .from_json([5,Time.now.to_i,946685400,1,100.00000000]),
    ])
  end
end
RSpec.configuration.include BitexStubs
