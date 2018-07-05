require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  before(:each) { Bitex.api_key = 'valid_key' }

  let(:store) { BitexBot::Store.create }

  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(BitexBot::BuyOpeningFlow.statuses)) }

  describe 'when creating a buying flow' do
    it 'spends 50 usd' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        buying: double(amount_to_spend_per_order: 50, profit: 0))

      flow = BitexBot::BuyOpeningFlow.create_for_market(100,
        bitstamp_api_wrapper_order_book.bids, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
        store)

      flow.order_id.should == 12345
      flow.value_to_use.should == 50
      flow.price.should <= flow.suggested_closing_price
      flow.price.round(14).should == '19.85074626865672'.to_d
      flow.suggested_closing_price.should == 20
    end

    let(:order_id) { 12_345 }
    let(:amount_to_spend) { 100.to_d }
    let(:btc_balance) { 100_000.to_d }
    let(:maker_fee) { 0.5.to_d }
    let(:taker_fee) { 0.25.to_d }
    let(:order_book) { bitstamp_api_wrapper_order_book.bids }
    let(:transactions) { bitstamp_api_wrapper_transactions_stub }

    it 'spends 100 usd' do
      suggested_closing_price = 15.to_d

      BitexBot::Settings.stub(
        time_to_live: 3,
        buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0)
      )
      stub_bitex_orders

      flow =
        BitexBot::BuyOpeningFlow.create_for_market(
          btc_balance,
          order_book,
          transactions,
          maker_fee,
          taker_fee,
          store
        )

      flow.order_id.should eq order_id
      flow.value_to_use.should eq amount_to_spend
      flow.price.should <= suggested_closing_price
      flow.suggested_closing_price.should eq suggested_closing_price
    end

    let(:other_fx_rate) { 10.to_d }

    it 'spends 100 usd with other fx_rate' do
      suggested_closing_price = 25.to_d

      BitexBot::Settings.stub(
        buying_foreign_exchange_rate: other_fx_rate,
        time_to_live: 3,
        buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0)
      )
      stub_bitex_orders

      flow =
        BitexBot::BuyOpeningFlow.create_for_market(
          btc_balance,
          order_book,
          transactions,
          maker_fee,
          taker_fee,
          store
        )

      flow.order_id.should eq order_id
      flow.value_to_use.should eq amount_to_spend
      flow.price.should <= suggested_closing_price * other_fx_rate
      flow.suggested_closing_price.should eq suggested_closing_price
    end

    it 'lowers the price to pay on bitex to take a profit' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        buying: double(amount_to_spend_per_order: 100, profit: 50.to_d))

      flow = BitexBot::BuyOpeningFlow.create_for_market(100000,
        bitstamp_api_wrapper_order_book.bids, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
        store)

      flow.order_id.should == 12345
      flow.value_to_use.should == 100
      flow.price.should <= flow.suggested_closing_price
      flow.price.should == '7.44402985074627'.to_d
      flow.suggested_closing_price.should == 15
    end

    it 'fails when there is a problem placing the bid on bitex' do
      Bitex::Bid.stub(:create!) { raise StandardError.new('Cannot Create') }

      BitexBot::Settings.stub(time_to_live: 3,
        buying: double(amount_to_spend_per_order: 100, profit: 0))

      expect do
        flow = BitexBot::BuyOpeningFlow.create_for_market(100000,
          bitstamp_api_wrapper_order_book.bids, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
          store)

        flow.should be_nil
        BitexBot::BuyOpeningFlow.count.should == 0
      end.to raise_exception(BitexBot::CannotCreateFlow)
    end

    it 'fails when there are not enough bitcoin to sell in the other exchange' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        buying: double(amount_to_spend_per_order: 100, profit: 0))

      expect do
        flow = BitexBot::BuyOpeningFlow.create_for_market(1,
          bitstamp_api_wrapper_order_book.bids, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
          store)

        flow.should be_nil
        BitexBot::BuyOpeningFlow.count.should == 0
      end.to raise_exception(BitexBot::CannotCreateFlow)
    end

    it 'prioritizes profit from store' do
      store = BitexBot::Store.new(buying_profit: 0.5)
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        buying: double(amount_to_spend_per_order: 50, profit: 0))

      flow = BitexBot::BuyOpeningFlow.create_for_market(100,
        bitstamp_api_wrapper_order_book.bids, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
        store)

      flow.price.round(13).should == '19.7514925373134'.to_d
    end
  end

  describe 'when fetching open positions' do
    let(:flow) { create(:buy_opening_flow) }

    it 'only gets buys' do
      flow.order_id.should == 12345
      stub_bitex_transactions

      expect do
        all = BitexBot::BuyOpeningFlow.sync_open_positions

        all.size.should == 1
        all.first.tap do |o|
          o.price == 300.0
          o.amount == 600.0
          o.quantity == 2
          o.transaction_id.should == 12345678
          o.opening_flow.should == flow
        end
      end.to change { BitexBot::OpenBuy.count }.by(1)
    end

    it 'does not register the same buy twice' do
      flow.order_id.should == 12345
      stub_bitex_transactions
      BitexBot::BuyOpeningFlow.sync_open_positions
      BitexBot::OpenBuy.count.should == 1
      Timecop.travel 1.second.from_now
      stub_bitex_transactions(build(:bitex_buy, id: 23456))

      expect do
        news = BitexBot::BuyOpeningFlow.sync_open_positions
        news.first.transaction_id.should == 23456
      end.to change { BitexBot::OpenBuy.count }.by(1)
    end

    it 'does not register buys from another order book' do
      flow.order_id.should == 12345
      Bitex::Trade.stub(all: [build(:bitex_buy, id: 23456, order_book: :btc_ars)])

      expect do
        BitexBot::BuyOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenBuy.count }
      BitexBot::OpenBuy.count.should == 0
    end

    it 'does not register buys from unknown bids' do
      stub_bitex_transactions

      expect do
        BitexBot::BuyOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenBuy.count }
    end
  end

  it 'cancels the associated bitex bid' do
    stub_bitex_orders
    BitexBot::Settings.stub(time_to_live: 3,
      buying: double(amount_to_spend_per_order: 50, profit: 0))

    flow = BitexBot::BuyOpeningFlow.create_for_market(100,
      bitstamp_api_wrapper_order_book.bids, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
      store)

    flow.finalise!
    flow.should be_settling
    flow.finalise!
    flow.should be_finalised
  end

  it 'order has expected order book' do
    stub_bitex_orders
    BitexBot::Settings.stub(time_to_live: 3,
      buying: double(amount_to_spend_per_order: 50, profit: 0))

    flow = subject.class.create_for_market(100,
      bitstamp_api_wrapper_order_book.bids, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
      store)

    order = subject.class.order_class.find(flow.order_id)
    order.order_book.should eq BitexBot::Settings.maker_settings.order_book
  end
end
