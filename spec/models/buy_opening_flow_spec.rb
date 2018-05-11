require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  before(:each) { Bitex.api_key = 'valid_key' }

  let(:store) { BitexBot::Store.create }

  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(BitexBot::BuyOpeningFlow.statuses)) }

  let(:order_id) { 12_345 }
  let(:time_to_live) { 3 }
  let(:orderbook) { bitstamp_api_wrapper_order_book.bids }
  let(:transactions) { bitstamp_api_wrapper_transactions_stub }
  let(:bitex_fee) { 0.5.to_d }
  let(:other_fee) { 0.25.to_d }

  describe 'when creating a buying flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: time_to_live)
      stub_bitex_orders
    end

    let(:flow) { BitexBot::BuyOpeningFlow.create_for_market(btc_balance, orderbook, transactions, bitex_fee, other_fee, store) }

    context 'with BTC balance 100' do
      let(:btc_balance) { 100.to_d }

      it 'spends 50 usd' do
        amount_to_spend = 50.to_d
        suggested_closing_price = 20.to_d
        usd_price = '19.85074626865672'.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq amount_to_spend
        flow.price.should <= suggested_closing_price
        flow.price.round(14).should eq usd_price
        flow.suggested_closing_price.should eq suggested_closing_price
      end

      it 'spends 100 usd' do
        amount_to_spend = 100.to_d
        suggested_closing_price = 15.to_d
        usd_price = '14.888_059_701_492'.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq amount_to_spend
        flow.price.should.should <= suggested_closing_price
        flow.price.truncate(12).should eq usd_price
        flow.suggested_closing_price.should eq suggested_closing_price
      end

      it 'spends 100 usd with other fx_rate' do
        other_fx_rate = 10.to_d
        amount_to_spend = 100.to_d
        suggested_closing_price = 15.to_d
        usd_price = '14.888_059_701_492'.to_d

        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0), fx_rate: other_fx_rate)

        flow.order_id.should eq order_id
        flow.value_to_use.should eq amount_to_spend
        flow.price.should <= suggested_closing_price * other_fx_rate
        flow.price.truncate(11).should eq usd_price * other_fx_rate
        flow.suggested_closing_price.should eq suggested_closing_price
      end

      it 'lowers the price to pay on bitex to take a profit' do
        profit = 50.to_d
        amount_to_spend = 100.to_d
        suggested_closing_price = 15.to_d
        usd_price = '7.44_402_985_074_627'.to_d

        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: profit))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq amount_to_spend
        flow.price.should <= suggested_closing_price
        flow.price.round(14).should eq usd_price
        flow.suggested_closing_price.should eq suggested_closing_price
      end

      it 'fails when there is a problem placing the bid on bitex' do
        amount_to_spend = 100.to_d

        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0))
        Bitex::Bid.stub(:create!) { raise StandardError.new('Cannot Create') }

        expect do
          flow.should be_nil
          BitexBot::BuyOpeningFlow.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow)
      end

      context 'with preloaded store' do
        let(:store) { BitexBot::Store.new(buying_profit: 0.5) }

        it 'prioritizes profit from store' do
          amount_to_spend = 50.to_d
          usd_price = '19.7514925373134'.to_d
          BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0))

          flow.price.round(13).should eq usd_price
        end
      end

      it 'cancels the associated bitex bid' do
        amount_to_spend = 50.to_d
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0))

        flow.finalise!.should be_truthy
        flow.should be_settling

        flow.finalise!.should be_truthy
        flow.should be_finalised
      end
    end

    context 'with BTC balance 1' do
      let(:btc_balance) { 1.to_d }

      it 'fails when there are not enough bitcoin to sell in the other exchange' do
        amount_to_spend = 100.to_d
        profit = 0
        BitexBot::Settings.stub(buying: double(amount_to_spend_per_order: amount_to_spend, profit: 0))

        expect do
          flow.should be_nil
          BitexBot::BuyOpeningFlow.count.should eq 0
        end.to raise_exception(BitexBot::CannotCreateFlow)
      end
    end
  end

  describe 'when fetching open positions' do
    before(:each) { stub_bitex_transactions }

    let(:flow) { create(:buy_opening_flow) }
    let(:trades) { BitexBot::BuyOpeningFlow.sync_open_positions }
    let(:transaction_id) { 12_345_678 }

    it 'only gets buys' do
      flow.order_id.should eq order_id

      expect do
        trades.size.should eq 1
        trades.sample.tap do |t|
          t.opening_flow.should eq flow
          t.transaction_id.should eq transaction_id
          t.price.should eq 300.0
          t.amount.should eq 600.0
          t.quantity.should eq 2
        end
      end.to change { BitexBot::OpenBuy.count }.by(1)
    end

    it 'does not register the same buy twice' do
      flow.order_id.should eq order_id

      BitexBot::BuyOpeningFlow.sync_open_positions
      BitexBot::OpenBuy.count.should eq 1

      Timecop.travel 1.second.from_now
      transaction_id = 23_456
      stub_bitex_transactions(build(:bitex_buy, id: transaction_id))

      expect do
        trades.size.should eq 1
        trades.sample.transaction_id.should eq transaction_id 
      end.to change { BitexBot::OpenBuy.count }.by(1)
    end

    it 'does not register buys from another orderbook' do
      flow.order_id.should eq order_id 

      transaction_id = 23_456
      Bitex::Trade.stub(all: [build(:bitex_buy, id: transaction_id, orderbook: :btc_ars)])

      expect do
        BitexBot::BuyOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenBuy.count }
      BitexBot::OpenBuy.count.should be_zero
    end

    it 'does not register buys from unknown bids' do
      expect do
        BitexBot::BuyOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenBuy.count }
    end
  end
end
