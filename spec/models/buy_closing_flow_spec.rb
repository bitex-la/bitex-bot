require 'spec_helper'

describe BitexBot::BuyClosingFlow do
  before(:each) do
    allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('MAKER_BASE')
    allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('MAKER_QUOTE')
  end

  describe '.active' do
    before(:each) do
      create(:buy_closing_flow, id: 1, done: true)
      create(:buy_closing_flow, id: 2, done: false)
    end

    subject(:active) { described_class.active }

    its(:count) { is_expected.to eq(1) }
    its(:'take.id') { is_expected.to eq(2) }
  end

  describe '.open_position_class' do
    subject(:klass) { described_class.open_position_class }

    it { is_expected.to eq(BitexBot::OpenBuy) }
  end

  describe '.fx_rate' do
    before(:each) { allow(BitexBot::Settings).to receive(:buying_fx_rate).and_return(10.to_d) }

    subject(:rate) { described_class.fx_rate }

    it { is_expected.to eq(10) }
    it { is_expected.to be_a(BigDecimal) }
  end

  describe '.trade_type' do
    subject(:type) { described_class.trade_type }

    it { is_expected.to eq(:sell) }
  end

  describe '.close_market' do
    subject { described_class.close_market }

    it 'not new closing flows' do
      expect { described_class.close_market }.not_to change { described_class.count }
    end

    context 'with open positions' do
      before(:each) do
        create(:open_buy, id: 800, quantity: 4, amount: 11)
        create(:open_buy, id: 900, quantity: 6, amount: 89)

        allow(described_class).to receive(:suggested_amount).and_return(20.to_d)

        allow(BitexBot::Robot).to receive_message_chain(:taker, :enough_order_size?).with(10, 2, :sell).and_return(enough_order_size)
      end

      context 'not enough order size for taker' do
        let(:enough_order_size) { false }

        it 'not new closing flows' do
          expect { described_class.close_market }.not_to change { described_class.count }
        end
      end

      context 'enough order size for taker' do
        let(:enough_order_size) { true }

        before(:each) do
          allow(described_class).to receive(:fx_rate).and_return(2.to_d)
          allow(BitexBot::Robot).to receive_message_chain(:taker, :place_order).with(:sell, 2, 10).and_return(ApiWrapper::Order.new('65'))

          allow(BitexBot::Robot).to receive(:logger).and_return(logger)
        end

        let(:logger) { BitexBot::Logger.setup }
        let(:flow) { described_class.last }
        let(:positions) { BitexBot::OpenBuy.where(id: [800, 900]) }

        it 'creates a new closing flow with open positions data' do
          expect { described_class.close_market }.to change { described_class.count }.by(1)

          expect(flow.desired_price).to eq(2)
          expect(flow.quantity).to eq(10)
          expect(flow.amount).to eq(50)

          expect(flow.open_positions).to eq(positions)
          expect(flow.close_positions.map(&:closing_flow)).to all(eq(flow))
          expect(flow.close_positions.map(&:order_id)).to all(eq('65'))
        end
      end
    end
  end

  describe '#sync_positions' do
    context 'without active flows' do
      before(:each) { create(:buy_closing_flow, id: 17, done: true) }

      let(:flow) { described_class.last }

      it 'active flow wasnt change'do
        expect { described_class.sync_positions }.not_to change(flow, :updated_at)
      end
    end

    context 'with active flows' do
      before(:each) { create(:buy_closing_flow, id: 123, crypto_profit: 0, fiat_profit: 0, fx_rate: 0, done: false) }

      context 'with close positions' do
        before(:each) do
          create(:close_buy, id: 128, amount: 0, quantity: 0, order_id: '245', closing_flow: described_class.find(123))
        end

        let(:order) { ApiWrapper::Order.new('245') }

        context 'and cancellable position' do
          before(:each) do
            allow_any_instance_of(BitexBot::CloseBuy).to receive(:cancellable?).and_return(true)

            allow_any_instance_of(BitexBot::CloseBuy).to receive(:order).and_return(order)
            allow(BitexBot::Robot).to receive_message_chain(:taker, :cancel_order).with(order).and_return([])
          end

          it 'cancel order was sent' do
            expect(BitexBot::Robot).to receive_message_chain(:taker, :cancel_order).with(order).and_return([])

            described_class.sync_positions
          end
        end

        context 'and active position' do
          before(:each) do
            allow_any_instance_of(BitexBot::CloseBuy).to receive(:cancellable?).and_return(false)
            allow_any_instance_of(described_class).to receive(:next_quantity_and_price).and_return([10.to_d, 20.to_d])
          end

          context 'and not enough order size' do
            before(:each) do
              allow(BitexBot::Robot).to receive_message_chain(:taker, :enough_order_size?).with(10, 20, :sell).and_return(false)

              allow_any_instance_of(described_class).to receive(:estimate_crypto_profit).and_return(1_000.to_d)
              allow_any_instance_of(described_class).to receive(:estimate_fiat_profit).and_return(2_000.to_d)
              allow_any_instance_of(described_class).to receive(:fx_rate).and_return(28.to_d)
            end

            context 'with executed order' do
              before(:each) do
                allow_any_instance_of(BitexBot::CloseBuy).to receive(:order).and_return(nil)
                allow(BitexBot::Robot)
                  .to receive_message_chain(:taker, :amount_and_quantity)
                  .with('245')
                  .and_return([123.to_d, 345.to_d])

                allow(BitexBot::Robot).to receive(:logger).and_return(logger)
              end

              let(:logger) { BitexBot::Logger.setup }

              it 'finalized flow, syncronized position, not new close position' do
                expect { described_class.sync_positions }.not_to change { BitexBot::CloseBuy.count }

                described_class.find(123).tap do |flow|
                  expect(flow.crypto_profit).to eq(1_000)
                  expect(flow.fiat_profit).to eq(2_000)
                  expect(flow.fx_rate).to eq(28)
                  expect(flow.done).to be_truthy
                end

                BitexBot::CloseBuy.find(128).tap do |position|
                  expect(position.amount).to eq(123)
                  expect(position.quantity).to eq(345)
                end
              end
            end

            context 'with active order' do
              before(:each) { allow_any_instance_of(BitexBot::CloseBuy).to receive(:order).and_return(order) }

              it 'not finalized flow, nothing to sync, not new close position' do
                expect { described_class.sync_positions }.not_to change { BitexBot::CloseBuy.count }

                described_class.find(123).tap do |flow|
                  expect(flow.crypto_profit).to be_zero
                  expect(flow.fiat_profit).to be_zero
                  expect(flow.fx_rate).to eq(28)
                  expect(flow.done).to be_falsey
                end

                BitexBot::CloseBuy.find(128).tap do |position|
                  expect(position.amount).to be_zero
                  expect(position.quantity).to be_zero
                end
              end
            end
          end

          context 'and enough order size' do
            before(:each) do
              allow(BitexBot::Robot).to receive_message_chain(:taker, :enough_order_size?).with(10, 20, :sell).and_return(true)

              allow(BitexBot::Robot)
                .to receive_message_chain(:taker, :place_order)
                .with(:sell, 20, 10)
                .and_return(ApiWrapper::Order.new('8787'))
            end

            context 'with executed order' do
              before(:each) do
                allow_any_instance_of(BitexBot::CloseBuy).to receive(:order).and_return(nil)
                allow(BitexBot::Robot)
                  .to receive_message_chain(:taker, :amount_and_quantity)
                  .with('245')
                  .and_return([123.to_d, 345.to_d])

                allow(BitexBot::Robot).to receive(:logger).and_return(logger)
              end

              let(:logger) { BitexBot::Logger.setup }

              it 'not finalized flow, sync with trade#245, and not new close position' do
                expect { described_class.sync_positions }.not_to change { BitexBot::CloseSell.count }

                flow = described_class.find(123)
                expect(flow.crypto_profit).to be_zero
                expect(flow.fiat_profit).to be_zero
                expect(flow.done).to be_falsey

                close_trade = flow.close_positions.find(128)
                expect(close_trade.amount).to eq(123)
                expect(close_trade.quantity).to eq(345)
                expect(close_trade.order_id).to eq('245')
              end
            end

            context 'with active order' do
              before(:each) { allow_any_instance_of(BitexBot::CloseBuy).to receive(:order).and_return(order) }

              it 'not finalized flow, nothing to sync, and not new close position' do
                expect { described_class.sync_positions }.not_to change { BitexBot::CloseBuy.count }

                flow = described_class.find(123)
                expect(flow.crypto_profit).to be_zero
                expect(flow.fiat_profit).to be_zero
                expect(flow.done).to be_falsey
              end
            end
          end
        end
      end
    end
  end

  describe '.suggested_amount' do
    before(:each) do
      opening_flow = create(:buy_opening_flow, suggested_closing_price: 10)
      create(:open_buy, id: 77, quantity: 10, opening_flow: opening_flow)

      opening_flow = create(:buy_opening_flow, suggested_closing_price: 100)
      create(:open_buy, id: 78, quantity: 100, opening_flow: opening_flow)
    end

    subject(:amount) { described_class.send(:suggested_amount, BitexBot::OpenBuy.where(id: [77, 78])) }

    it { is_expected.to eq(10100) }
    it { is_expected.to be_a(BigDecimal) }
  end

  describe '#finalise!' do
    before(:each) do
      allow(BitexBot::Robot).to receive(:logger).and_return(logger)

      allow_any_instance_of(described_class).to receive(:estimate_crypto_profit).and_return(200.to_d)
      allow_any_instance_of(described_class).to receive(:estimate_fiat_profit).and_return(100.to_d)
      allow_any_instance_of(described_class).to receive(:fx_rate).and_return(5.to_d)

      create(:buy_closing_flow, id: 20, fiat_profit: 4, crypto_profit: 2)
    end

    let(:logger) { BitexBot::Logger.setup }

    subject(:flow) { described_class.find(20).tap { |closing| closing.send(:finalise!) } }

    its(:id) { is_expected.to eq(20) }
    its(:fiat_profit) { is_expected.to eq(100) }
    its(:crypto_profit) { is_expected.to eq(200) }
    its(:fx_rate) { is_expected.to eq(5) }
    its(:done) { is_expected.to be_truthy }
  end

  describe '#positions_balance_amount' do
    before(:each) do
      allow(described_class).to receive(:fx_rate).and_return(10.to_d)

      create(:close_buy, amount: 10, closing_flow: flow)
      create(:close_buy, amount: 20, closing_flow: flow)
    end

    let(:flow) { create(:buy_closing_flow) }

    subject(:amount_balance) { flow.send(:positions_balance_amount ) }

    it { is_expected.to eq(300) }
    it { is_expected.to be_a(BigDecimal) }
  end

  describe '#price_variation' do
    before(:each) { create_list(:close_buy, 10, closing_flow: flow) }
    subject { flow.send(:price_variation) }

    let(:flow) { create(:buy_closing_flow) }

    it { is_expected.to eq(3) }
    it { is_expected.to be_a(BigDecimal) }
  end

  describe '#estimate_cryto_profit' do
    before(:each) do
      create(:close_buy, quantity: 10, closing_flow: flow)
      create(:close_buy, quantity: 20, closing_flow: flow)
    end

    let(:flow) { create(:buy_closing_flow, quantity: 100) }

    subject(:profit) { flow.send(:estimate_crypto_profit) }

    it { is_expected.to eq(70) }
    it { is_expected.to be_a(BigDecimal) }
  end

  describe '#estimate_fiat_profit' do
    before(:each) do
      allow_any_instance_of(described_class).to receive(:positions_balance_amount).and_return(100)

      create(:open_buy, amount: 10, closing_flow: flow)
      create(:open_buy, amount: 20, closing_flow: flow)
    end

    let(:flow) { create(:buy_closing_flow) }

    subject(:profit) { flow.send(:estimate_fiat_profit) }

    it { is_expected.to eq(70) }
    it { is_expected.to be_a(BigDecimal) }
  end

  describe '#next_quantity_and_price' do
    before(:each) do
      allow_any_instance_of(described_class).to receive(:price_variation).and_return(1.to_d)

      create(:close_buy, quantity: 10, closing_flow: flow)
      create(:close_buy, quantity: 20, closing_flow: flow)
    end

    let(:flow) { create(:buy_closing_flow, quantity: 100, desired_price: 200) }

    subject(:price_quantity) { flow.send(:next_quantity_and_price) }

    it { is_expected.to eq([70, 199]) }
    it { is_expected.to all(be_a(BigDecimal)) }
  end
end
