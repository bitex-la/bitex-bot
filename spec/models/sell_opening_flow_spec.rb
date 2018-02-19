require 'spec_helper'

describe BitexBot::SellOpeningFlow do
  before(:each) { Bitex.api_key = 'valid_key' }

  let(:store) { BitexBot::Store.create }

  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(BitexBot::SellOpeningFlow.statuses)) }

  describe 'when creating a selling flow' do
    it 'sells 2 bitcoin' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        selling: double(quantity_to_sell_per_order: 2, profit: 0))

      flow = BitexBot::SellOpeningFlow.create_for_market(1000,
        bitstamp_api_wrapper_order_book.asks, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
        store)

      flow.order_id.should == 12345
      flow.value_to_use.should == 2
      flow.price.should >= flow.suggested_closing_price
      flow.price.should == '20.15037593984962'.to_d
      flow.suggested_closing_price.should == 20
    end

    it 'sells 4 bitcoin' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        selling: double(quantity_to_sell_per_order: 4, profit: 0))

      flow = BitexBot::SellOpeningFlow.create_for_market(1000,
        bitstamp_api_wrapper_order_book.asks, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
        store)

      flow.order_id.should == 12345
      flow.value_to_use.should == 4
      flow.price.should >= flow.suggested_closing_price
      flow.price.round(14).should == '25.18796992481203'.to_d
      flow.suggested_closing_price.should == 25
    end

    it 'raises the price to charge on bitex to take a profit' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        selling: double(quantity_to_sell_per_order: 4, profit: 50))

      flow = BitexBot::SellOpeningFlow.create_for_market(1000,
        bitstamp_api_wrapper_order_book.asks, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
        store)

      flow.order_id.should == 12345
      flow.value_to_use.should == 4
      flow.price.should >= flow.suggested_closing_price
      flow.price.round(14).should == '37.78195488721804'.to_d
      flow.suggested_closing_price.should == 25
    end

    it 'fails when there is a problem placing the ask on bitex' do
      Bitex::Ask.stub(:create!) { raise StandardError.new('Cannot Create') }
      BitexBot::Settings.stub(time_to_live: 3,
        selling: double(quantity_to_sell_per_order: 4, profit: 50))

      expect do
        flow = BitexBot::SellOpeningFlow.create_for_market(100000,
          bitstamp_api_wrapper_order_book.asks, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
          store)

        flow.should be_nil
        BitexBot::SellOpeningFlow.count.should == 0
      end.to raise_exception(BitexBot::CannotCreateFlow)
    end

    it 'fails when there are not enough USD to re-buy in the other exchange' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        selling: double(quantity_to_sell_per_order: 4, profit: 50))

      expect do
        flow = BitexBot::SellOpeningFlow.create_for_market(1,
          bitstamp_api_wrapper_order_book.asks, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
          store)

        flow.should be_nil
        BitexBot::SellOpeningFlow.count.should == 0
      end.to raise_exception(BitexBot::CannotCreateFlow)
    end

    it 'Prioritizes profit from store' do
      stub_bitex_orders
      BitexBot::Settings.stub(time_to_live: 3,
        selling: double(quantity_to_sell_per_order: 2, profit: 0))

      store = BitexBot::Store.new(selling_profit: 0.5)
      flow = BitexBot::SellOpeningFlow.create_for_market(1000,
        bitstamp_api_wrapper_order_book.asks, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
        store)

      flow.price.round(14).should == '20.25112781954887'.to_d
    end
  end

  describe 'when fetching open positions' do
    let(:flow) { create(:sell_opening_flow) }

    it 'only gets sells' do
      stub_bitex_transactions

      flow.order_id.should == 12345
      expect do
        all = BitexBot::SellOpeningFlow.sync_open_positions

        all.size.should == 1
        all.first.tap do |o|
          o.price.should == 300.0
          o.amount.should == 600.0
          o.quantity.should == 2
          o.transaction_id.should == 12345678
          o.opening_flow.should == flow
        end
      end.to change { BitexBot::OpenSell.count }.by(1)
    end

    it 'does not register the same buy twice' do
      stub_bitex_transactions

      flow.order_id.should == 12345
      BitexBot::SellOpeningFlow.sync_open_positions
      BitexBot::OpenSell.count.should == 1

      Timecop.travel 1.second.from_now
      stub_bitex_transactions(build(:bitex_sell, id: 23456))

      expect do
        news = BitexBot::SellOpeningFlow.sync_open_positions
        news.first.transaction_id.should == 23456
      end.to change { BitexBot::OpenSell.count }.by(1)
    end

    it 'does not register litecoin buys' do
      Bitex::Trade.stub(all: [build(:bitex_sell, id: 23456, specie: :ltc)])

      flow.order_id.should == 12345
      expect do
        BitexBot::SellOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenSell.count }
      BitexBot::OpenSell.count.should == 0
    end

    it 'does not register buys from unknown bids' do
      stub_bitex_transactions

      expect do
        BitexBot::SellOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenSell.count }
    end
  end

  it 'cancels the associated bitex bid' do
    stub_bitex_orders
    BitexBot::Settings.stub(time_to_live: 3,
      selling: double(quantity_to_sell_per_order: 4, profit: 50))

    flow = BitexBot::SellOpeningFlow.create_for_market(1000,
      bitstamp_api_wrapper_order_book.asks, bitstamp_api_wrapper_transactions_stub, 0.5, 0.25,
      store)

    flow.finalise!
    flow.should be_settling
    flow.finalise!
    flow.should be_finalised
  end
end
