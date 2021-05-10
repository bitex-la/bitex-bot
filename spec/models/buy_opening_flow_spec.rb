require 'spec_helper'

describe BitexBot::BuyOpeningFlow do
  it_behaves_like 'OpeningFlows'

  describe '.maker_price' do
    before(:each) do
      allow(described_class).to receive(:fx_rate).and_return(10.to_d)
      allow(described_class).to receive(:value_to_use).and_return(2.to_d)
      allow(described_class).to receive(:profit).and_return(1.to_d)
    end

    subject(:price) { described_class.maker_price(2.to_d) }

    it { is_expected.to eq(9.9) }
  end

  describe '.open_position_class' do
    subject { described_class.open_position_class }

    it { is_expected.to eq(BitexBot::OpenBuy) }
  end

  describe '.expected_kind_trade?' do
    subject { described_class.expected_kind_trade?(trade) }

    let(:trade) { build_bitex_user_transaction(type, 11, 11, 11, 11, 111, 11, :dont_care) }

    context 'expected' do
      let(:type) { :buy }

      it { is_expected.to be_truthy }
    end

    context 'non expected' do
      let(:type) { :sell }

      it { is_expected.to be_falsey }
    end
  end

  describe '.trade_type' do
    subject(:type) { described_class.trade_type }

    it { is_expected.to eq(:buy) }
  end

  describe '.profit' do
    subject(:profit) { described_class.profit }

    context 'with store' do
      before(:each) { described_class.store = create(:store, buying_profit: 10) }

      it { is_expected.to eq(10) }
    end

    context 'without store' do
      before(:each) do
        allow(described_class).to receive(:store).and_return(nil)
        allow(BitexBot::Settings).to receive_message_chain(:buying, :profit).and_return(20.to_d)
      end

      it { is_expected.to eq(20) }
    end
  end

  describe '.remote_value_to_use' do
    subject { described_class.remote_value_to_use(200.to_d, 100.to_d) }

    it { is_expected.to eq(2) }
  end

  describe '.safest_price' do
    before(:each) do
      allow(BitexBot::Settings).to receive(:time_to_live).and_return(30)
      allow(described_class).to receive(:fx_rate).and_return(0.5.to_d)
    end

    let(:transactions) { double }
    let(:orders) { double }

    it 'forward to OrderbookSimulator with nil quantity_target' do
      expect(BitexBot::OrderbookSimulator).to receive(:run).with(30, transactions, orders, 100, nil, 0.5)

      described_class.safest_price(transactions, orders, 100.to_d)
    end
  end

  describe '.value_to_use' do
    subject(:value) { described_class.value_to_use }

    context 'with store' do
      before(:each) { described_class.store = create(:store, buying_amount_to_spend_per_order: 10) }

      it { is_expected.to eq(10) }
    end

    context 'without store' do
      before(:each) do
        allow(described_class).to receive(:store).and_return(nil)
        allow(BitexBot::Settings).to receive_message_chain(:buying, :amount_to_spend_per_order).and_return(20.to_d)
      end

      it { is_expected.to eq(20) }
    end
  end

  describe '.fx_rate' do
    before(:each) { allow(BitexBot::Settings).to receive(:buying_fx_rate).and_return(100.to_d) }

    subject(:fx_rate) { described_class.fx_rate }

    it { is_expected.to eq(100) }
  end

  describe '.value_per_order' do
    before(:each) do
      allow(described_class).to receive(:value_to_use).and_return(100.to_d)
      allow(described_class).to receive(:fx_rate).and_return(5.to_d)
    end

    subject(:value) { described_class.value_per_order }

    it { is_expected.to eq(500) }
  end

  describe 'markets species' do
    before(:each) do
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('maker_crypto')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('maker_fiat')
      # On taker market, BuyOpeningFlow spend taker base specie
      allow(BitexBot::Robot).to receive_message_chain(:taker, :base).and_return('taker_crypto')
    end

    subject { described_class }

    its(:maker_specie_to_obtain) { is_expected.to eq('MAKER_CRYPTO') }
    its(:maker_specie_to_spend) { is_expected.to eq('MAKER_FIAT') }
    its(:taker_specie_to_spend) { is_expected.to eq('TAKER_CRYPTO') }
  end

  describe '.sought_transaction' do
    before(:each) do
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base_quote).and_return('fuck_yeah')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('FUCK')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('YEAH')
    end

    subject(:sought) { described_class.sought_transaction?(trade, threshold) }

    let(:trade) { build_bitex_user_transaction(type, trade_id, 999, 600, 2, 300, 0.05, orderbook_code, created_at) }

    let(:threshold) { 2.minutes.ago }

    let(:type) { :buy }                 # BuyOpeningFlow kind trade
    let(:created_at) { Time.now.utc }   # Recent trade
    let(:trade_id) { 999_999 }          # Non syncronized position
    let(:orderbook_code) { :fuck_yeah } # Expected orderbook

    it { is_expected.to be_truthy }

    context 'non threshold' do
      let(:threshold) { nil }

      it { is_expected.to be_truthy }
    end

    context 'non sought by' do
      context 'non expected kind trade' do
        let(:type) { :sell }

        it { is_expected.to be_falsey }
      end

      context 'is syncronized position' do
        before(:each) { create(:open_buy, transaction_id: trade_id) }

        it { is_expected.to be_falsey }
      end

      context 'non active' do
        let(:created_at) { 35.minutes.ago.to_i }

        it { is_expected.to be_falsey }
      end

      context 'non expected orderbook' do
        let(:orderbook_code) { :fuck_no }

        it { is_expected.to be_falsey }
      end
    end
  end

  describe '.syncronized?' do
    subject(:syncronized?) { described_class.syncronized?(trade) }

    let(:trade) { build_bitex_user_transaction(:dont_care, 999_999, 999, 11, 11, 111, 11, :dont_care) }

    context 'is syncronized' do
      before(:each) { create(:open_buy, transaction_id: trade.id) }

      it { is_expected.to be_truthy }
    end

    context 'non syncronized' do
      it { is_expected.to be_falsey }
    end
  end

  describe '.sync_positions' do
    subject(:sync) { described_class.sync_positions }

    context 'not have open positions' do
      before(:each) { allow(BitexBot::Robot).to receive_message_chain(:maker, :trades).and_return([]) }

      it 'nothing to sync' do
        expect do
          expect(sync).to be_empty
        end.to_not change { BitexBot::OpenBuy.count }
      end
    end

    context 'have open positions' do
      before(:each) do
        allow(BitexBot::Robot).to receive_message_chain(:maker, :base_quote).and_return('fuck_yeah')
        allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('fuck')
        allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('yeah')
        allow(BitexBot::Robot).to receive_message_chain(:maker, :trades).and_return([trade])
      end

      let(:trade) { build_bitex_user_transaction(:buy, 999, 246, 100, 2, 50, 0.05, :fuck_yeah, 2.minutes.ago) }

      context 'not sought, have syncronized open position' do
        # This trade is syncronized position
        before(:each) { create(:open_buy, transaction_id: 999) }

        it 'no syncs' do
          expect(BitexBot::OpenBuy.count).to eq(1)

          expect do
            expect(sync).to be_empty
          end.to_not change { BitexBot::OpenBuy.count }
        end
      end

      context 'is sought, have non syncronized open position' do
        # This trade not is syncronized position
        before(:each) { create(:open_buy) }

        it 'but this trade not belong to any buy opening flow, then no syncs' do
          expect(BitexBot::OpenBuy.count).to eq(1)

          expect do
            expect(sync).to be_empty
          end.to_not change { BitexBot::OpenBuy.count }
        end

        it 'belong to any buy opening flow then syncs' do
          flow = create(:buy_opening_flow, order_id: 246)

          expect(BitexBot::OpenBuy.count).to eq(1)

          expect do
            expect(sync.count).to eq(1)

            sync.find { |position| position.opening_flow == flow }.tap do |syncronized|
              expect(syncronized.transaction_id.to_s).to eq(trade.id)
              expect(syncronized.closing_flow_id).to be_nil
            end
          end.to change { BitexBot::OpenBuy.count }.by(1)
        end
      end
    end
  end

  describe '#finalise!'do 
    before(:each) { allow_any_instance_of(described_class).to receive(:order) { order } }

    let(:order) { BitexBot::ApiWrappers::Order.new('12', :fuck, 1, 1, Time.now.to_i, double(status: status)) }

    subject(:flow) { create(:buy_opening_flow) }

    context 'finalizable' do
      context 'order cancelled' do
        let(:status) { :cancelled }

        it do
          flow.finalise!

          expect(flow.finalised?).to be_truthy
        end
      end

      context 'order completed' do
        let(:status) { :completed }

        it do
          flow.finalise!

          expect(flow.finalised?).to be_truthy
        end
      end

      context 'order not found' do
        before(:each) { allow_any_instance_of(described_class).to receive(:order).and_raise(BitexBot::OrderNotFound) }

        it do
          flow.finalise!

          expect(flow.finalised?).to be_truthy
        end
      end
    end

    context 'non finalizable' do
      let(:status) { :another_status }

      it do
        expect(BitexBot::Robot).to receive_message_chain(:maker, :cancel_order).with(order)

        flow.finalise!

        expect(flow.finalised?).to be_falsey
        expect(flow.settling?).to be_truthy
      end
    end
  end
end
