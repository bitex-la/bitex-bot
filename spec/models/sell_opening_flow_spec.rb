require 'spec_helper'

describe BitexBot::SellOpeningFlow do
  it_behaves_like 'OpeningFlows'

  describe '.open_position_class' do
    subject { described_class.open_position_class }

    it { is_expected.to eq(BitexBot::OpenSell) }
  end

  describe '.expected_kind_trade?' do
    subject { described_class.expected_kind_trade?(trade) }

    let(:trade) { build_bitex_user_transaction(type, 11, 11, 11, 111, 11, :dont_care) }

    context 'expected' do
      let(:type) { :sell }

      it { is_expected.to be_truthy }
    end

    context 'non expected' do
      let(:type) { :buy }

      it { is_expected.to be_falsey }
    end
  end

  describe '.trade_type' do
    subject(:type) { described_class.trade_type }

    it { is_expected.to eq(:sell) }
  end

  describe '.order_type' do
    subject(:type) { described_class.order_type }

    it { is_expected.to eq(:ask) }
  end

  describe '.profit' do
    subject(:profit) { described_class.profit }

    context 'with store' do
      before(:each) { described_class.store = create(:store, selling_profit: 10) }

      it { is_expected.to eq(10) }
    end

    context 'without store' do
      before(:each) do
        allow(described_class).to receive(:store).and_return(nil)
        allow(BitexBot::Settings).to receive_message_chain(:selling, :profit).and_return(20)
      end

      it { is_expected.to eq(20) }
    end
  end

  describe '.remote_value_to_use' do
    subject { described_class.remote_value_to_use(200, 100) }

    it { is_expected.to eq(20_000) }
  end

  describe '.safest_price' do
    before(:each) do
      allow(BitexBot::Settings).to receive(:time_to_live).and_return(30)
      # Here no need fx_rate
    end

    after(:each) { described_class.safest_price(transactions, orders, quantity_target) }

    let(:quantity_target) { 100 }
    let(:transactions) { double }
    let(:orders) { double }

    it 'forward to OrderBookSimulator with nil quantity_target' do
      expect(BitexBot::OrderBookSimulator).to receive(:run).with(30, transactions, orders, nil, quantity_target, nil)
    end
  end

  describe '.value_to_use' do
    subject(:value) { described_class.value_to_use }

    context 'with store' do
      before(:each) { described_class.store = create(:store, selling_quantity_to_sell_per_order: 10) }

      it { is_expected.to eq(10) }
    end

    context 'without store' do
      before(:each) do
        allow(described_class).to receive(:store).and_return(nil)
        allow(BitexBot::Settings).to receive_message_chain(:selling, :quantity_to_sell_per_order).and_return(20)
      end

      it { is_expected.to eq(20) }
    end
  end

  describe '.fx_rate' do
    before(:each) { allow(BitexBot::Settings).to receive(:selling_fx_rate).and_return(100) }

    subject(:fx_rate) { described_class.fx_rate }

    it { is_expected.to eq(100) }
  end

  describe '.value_per_order' do
    before(:each) do
      allow(described_class).to receive(:value_to_use).and_return(100)
      # Here no need fx_rate
    end

    subject(:value) { described_class.value_per_order }

    it { is_expected.to eq(100) }
  end

  describe 'markets species' do
    before(:each) do
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('maker_crypto')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('maker_fiat')
      # On taker market, SellOpeningFlow spend taker quote specie
      allow(BitexBot::Robot).to receive_message_chain(:taker, :quote).and_return('taker_quote')
    end

    subject { described_class }

    its(:maker_specie_to_obtain) { is_expected.to eq('MAKER_FIAT') }
    its(:maker_specie_to_spend) { is_expected.to eq('MAKER_CRYPTO') }
    its(:taker_specie_to_spend) { is_expected.to eq('TAKER_QUOTE') }
  end

  describe '.sought_transaction' do
    before(:each) do
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base_quote).and_return('fuck_yeah')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('FUCK')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('YEAH')
    end

    subject(:sought) { described_class.sought_transaction?(trade, threshold) }

    let(:trade) { build_bitex_user_transaction(type, order_id, 600, 2, 300, 0.05, orderbook_code, created_at) }

    let(:threshold) { 2.minutes.ago }

    let(:type) { :sell }                # SellOpeningFlow kind trade
    let(:created_at) { Time.now.utc }   # Recent trade
    let(:order_id) { 999_999 }          # Non syncronized position
    let(:orderbook_code) { :fuck_yeah } # Expected orderbook

    it { is_expected.to be_truthy }

    context 'non threshold' do
      let(:threshold) { nil }

      it { is_expected.to be_truthy }
    end

    context 'non sought by' do
      context 'non expected kind trade' do
        let(:type) { :buy }

        it { is_expected.to be_falsey }
      end

      context 'is syncronized position' do
        before(:each) { create(:open_sell, transaction_id: order_id) }

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

  describe '.create_open_position' do
    before(:each) do
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return(:fuck)
      allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return(:yeah)
    end

    let(:flow) { create(:sell_opening_flow, order_id: 999) }
    let(:trade) { build_bitex_user_transaction(:sell, '999', 100, 2, 50, 0.05, :dont_care) }

    subject(:open_position) { described_class.create_open_position!(trade, flow) }

    context 'logs' do
      after(:each) { open_position }

      it 'on creation' do
        expect(BitexBot::Robot).to receive(:log).with(:info, 'Opening: #1 was hit for FUCK 2.0 @ YEAH 50.0. Creating OpenSell...')
      end
    end

    its(:transaction_id) { is_expected.to eq(trade.order_id.to_i) }
    its(:price) { is_expected.to eq(trade.price) }
    its(:amount) { is_expected.to eq(trade.fiat) }
    its(:quantity) { is_expected.to eq(trade.crypto) }
    its(:opening_flow) { is_expected.to be(flow) }
  end

  describe '.sync_open_positions' do
    subject(:sync) { described_class.sync_open_positions }

    context 'not have open positions' do
      before(:each) { allow(BitexBot::Robot).to receive_message_chain(:maker, :trades).and_return([]) }

      it 'nothing to sync' do
        expect do
          expect(sync).to be_empty
        end.to_not change { BitexBot::OpenSell.count }
      end
    end

    context 'have open positions' do
      before(:each) do
        allow(BitexBot::Robot).to receive_message_chain(:maker, :base_quote).and_return('fuck_yeah')
        allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('fuck')
        allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('yeah')
        allow(BitexBot::Robot).to receive_message_chain(:maker, :trades).and_return([trade])
      end

      let(:trade) { build_bitex_user_transaction(:sell, 999, 100, 2, 50, 0.05, :fuck_yeah, 2.minutes.ago) }

      context 'not sought, have syncronized open position' do
        # This trade is syncronized position
        before(:each) { create(:open_sell, transaction_id: 999) }

        it 'no syncs' do
          expect(BitexBot::OpenSell.count).to eq(1)

          expect do
            expect(sync).to be_empty
          end.to_not change { BitexBot::OpenSell.count }
        end
      end

      context 'is sought, have non syncronized open position' do
        # This trade not is syncronized position
        before(:each) { create(:open_sell) }

        it 'but this trade not belong to any sell opening flow, then no syncs' do
          expect(BitexBot::OpenSell.count).to eq(1)

          expect do
            expect(sync).to be_empty
          end.to_not change { BitexBot::OpenSell.count }
        end

        it 'belong to any sell opening flow then syncs' do
          flow = create(:sell_opening_flow, order_id: 999)

          expect(BitexBot::OpenSell.count).to eq(1)

          expect do
            expect(sync.count).to eq(1)

            sync.find { |position| position.opening_flow == flow }.tap do |syncronized|
              expect(syncronized.transaction_id.to_s).to eq(trade.order_id)
              expect(syncronized.closing_flow_id).to be_nil
            end
          end.to change { BitexBot::OpenSell.count }.by(1)
        end
      end
    end
  end
end
