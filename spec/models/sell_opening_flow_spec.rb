require 'spec_helper'

describe BitexBot::SellOpeningFlow do
  it { should validate_presence_of :status }
  it { should validate_presence_of :price }
  it { should validate_presence_of :value_to_use }
  it { should validate_presence_of :order_id }
  it { should(validate_inclusion_of(:status).in_array(BitexBot::SellOpeningFlow.statuses)) }

  before(:each) { Bitex.api_key = 'valid_key' }

  let(:order_id) { 12_345 }
  let(:time_to_live) { 3 }
  let(:orderbook) { bitstamp_api_wrapper_order_book }
  let(:transactions) { bitstamp_api_wrapper_transactions_stub }
  let(:maker_fee) { 0.5.to_d }
  let(:taker_fee) { 0.25.to_d }
  let(:store) { BitexBot::Store.create }

  describe 'when creating a selling flow' do
    before(:each) do
      BitexBot::Settings.stub(time_to_live: time_to_live)
      stub_bitex_orders
    end

    let(:flow) do
      BitexBot::SellOpeningFlow.create_for_market(usd_balance, orderbook.asks, transactions, maker_fee, taker_fee, store)
    end

    context 'with USD balance 1000' do
      let(:usd_balance) { 1_000.to_d }

      it 'sells 2 btc' do
        quantity_to_sell = 2.to_d
        suggested_closing_price = 20.to_d
        usd_price = '20.15_037_593_984_962'.to_d
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq quantity_to_sell
        flow.price.should >= suggested_closing_price
        flow.price.round(14).should eq usd_price
        flow.suggested_closing_price.should eq suggested_closing_price
      end

      context 'sells 4 btc' do
        before(:each) { BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0)) }

        let(:quantity_to_sell) { 4.to_d }
        let(:suggested_closing_price) { 25.to_d }
        let(:usd_price) { '25.18_796_992_481_203'.to_d }

        it 'with default fx_rate (1)' do
          flow.order_id.should eq order_id
          flow.value_to_use.should eq quantity_to_sell
          flow.price.should >= suggested_closing_price
          flow.price.should eq usd_price
          flow.suggested_closing_price.should eq suggested_closing_price
        end

        it 'with other fx_rate' do
          other_fx_rate = 10.to_d
          BitexBot::Settings.stub(fx_rate: other_fx_rate)

          flow.order_id.should eq order_id
          flow.value_to_use.should eq quantity_to_sell
          flow.price.should >= suggested_closing_price * other_fx_rate
          flow.price.truncate(13).should eq usd_price * other_fx_rate
          flow.suggested_closing_price.should eq suggested_closing_price
        end
      end

      it 'raises the price to charge on bitex to take a profit' do
        profit = 50.to_d
        quantity_to_sell = 4.to_d
        suggested_closing_price = 25.to_d
        usd_price = '37.78_195_488_721_804'.to_d
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: profit))

        flow.order_id.should eq order_id
        flow.value_to_use.should eq quantity_to_sell
        flow.price.should >= suggested_closing_price
        flow.price.truncate(14).should eq usd_price
        flow.suggested_closing_price.should eq suggested_closing_price
      end

      it 'fails when there is a problem placing the ask on bitex' do
        quantity_to_sell = 4.to_d
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0))
        Bitex::Ask.stub(:create!) { raise StandardError, 'Cannot Create' }

        expect do
          flow.should be_nil
          BitexBot::SellOpeningFlow.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow, 'Cannot Create')
      end

      context 'with preloaded store' do
        let(:store) { BitexBot::Store.new(selling_profit: 0.5) }

        it 'Prioritizes profit from it' do
          quantity_to_sell = 2.to_d
          usd_price = '20.25_112_781_954_887'.to_d
          BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0))

          flow.price.round(14).should eq usd_price
        end
      end

      it 'cancels the associated bitex ask' do
        quantity_to_sell = 2.to_d
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0))

        flow.finalise!.should be_truthy
        flow.should be_settling

        flow.finalise!.should be_truthy
        flow.should be_finalised
      end
    end

    context 'with USD balance 1' do
      let(:usd_balance) { 1.to_d }

      it 'fails when there are not enough USD to re-buy in the other exchange' do
        quantity_to_sell = 4.to_d
        BitexBot::Settings.stub(selling: double(quantity_to_sell_per_order: quantity_to_sell, profit: 0))

        expect do
          flow.should be_nil
          BitexBot::SellOpeningFlow.count.should be_zero
        end.to raise_exception(BitexBot::CannotCreateFlow, 'Needed 100.7518796992481203 but you only have 1.0')
      end
    end
  end

  describe 'when fetching open positions' do
    before(:each) { stub_bitex_transactions }

    let(:flow) { create(:sell_opening_flow) }
    let(:trades) { BitexBot::SellOpeningFlow.sync_open_positions }
    let(:trade_id) { 12_345_678 }

    it 'only gets sells' do
      flow.order_id.should eq order_id

      expect do
        trades.size.should eq 1
        trades.sample.tap do |t|
          t.opening_flow.should eq flow
          t.transaction_id.should eq trade_id
          t.price.should eq 300.0
          t.amount.should eq 600.0
          t.quantity.should eq 2
        end
      end.to change { BitexBot::OpenSell.count }.by(1)
    end

    it 'does not register the same buy twice' do
      flow.order_id.should eq order_id
      BitexBot::SellOpeningFlow.sync_open_positions

      BitexBot::OpenSell.count.should eq 1

      Timecop.travel(1.second.from_now)
      trade_id = 23_456
      stub_bitex_transactions(build(:bitex_sell, id: trade_id))

      expect do
        trades.size.should eq 1
        trades.sample.transaction_id.should eq trade_id
      end.to change { BitexBot::OpenSell.count }.by(1)
    end

    it 'does not register buys from another orderbook' do
      flow.order_id.should eq order_id

      trade_id = 23_456
      Bitex::Trade.stub(all: [build(:bitex_sell, id: trade_id, orderbook: :btc_ars)])

      expect do
        BitexBot::SellOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenSell.count }
      BitexBot::OpenSell.count.should be_zero
    end

    it 'does not register buys from unknown bids' do
      expect do
        BitexBot::SellOpeningFlow.sync_open_positions.should be_empty
      end.not_to change { BitexBot::OpenSell.count }
    end
  end
end
