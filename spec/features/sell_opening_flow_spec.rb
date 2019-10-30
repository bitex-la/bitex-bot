require 'spec_helper'

# When maker is Bitex and taker is Bitstamp
describe BitexBot::SellOpeningFlow do
  before(:each) do
    allow(BitexBot::Robot)
      .to receive(:maker)
      .and_return(BitexBot::ApiWrappers::Bitex.new(double(api_key: 'key', sandbox: true, trading_fee: 0.05, orderbook_code: 'btc_usd')))

    allow(BitexBot::Robot)
      .to receive(:taker)
      .and_return(BitexBot::ApiWrappers::Bitstamp.new(double(api_key: 'key', secret: 'xxx', client_id: 'yyy', order_book: 'btcusd')))

    described_class.store = store
  end

  let(:store) { create(:store) }

  let(:maker) { BitexBot::Robot.maker }
  let(:taker) { BitexBot::Robot.taker }

  describe 'when creating a buying flow' do
    before(:each) do
      stub_bitstamp_market
      stub_bitstamp_transactions
      stub_bitex_active_orders

      allow(BitexBot::Settings).to receive(:time_to_live).and_return(3)
      allow(BitexBot::Settings).to receive(:selling_foreign_exchange_rate).and_return(1.to_d)
      allow(BitexBot::Settings).to receive_message_chain(:selling, :profit).and_return(0)
    end

    subject(:flow) { described_class.open_market(taker_balance, taker.market.asks, taker.transactions, 0.5.to_d, 0.25.to_d) }

    let(:taker_balance) { 1_000.to_d }
    let(:maker_balance) { 1_000.to_d }

    context 'sells 2 crypto' do
      before(:each) do
        allow(BitexBot::Settings).to(
          receive_message_chain(:selling, :quantity_to_sell_per_order)
            .and_return(2.to_d)
        )
      end

      its(:value_to_use) { is_expected.to eq(2) }
      its(:suggested_closing_price) { is_expected.to eq(20) }
      its(:price) { is_expected.to be >= 20 }

      it 'rounded price' do
        expect(flow.price.round(14)).to eq('20.15037593984962'.to_d)
      end

      context 'finalising flow cancels associated ask' do
        subject(:flow) { create(:sell_opening_flow, order_id: order.id) }

        let(:order) { maker.send_order(:sell, 20, 50) }

        it { expect(order.status).to eq(:executing) }
        it { is_expected.to be_executing }

        context 'cancel one time' do
          before(:each) { 
            BitexBot::Notifier.logger.debug("Finalise #64")
            flow.finalise!
          }

          it { expect(order.status).to eq(:cancelled) }
          it { is_expected.to be_settling }

          context 'cancels one more time' do
            before(:each) {
              BitexBot::Notifier.logger.debug("Finalise #73")
              flow.finalise!
            }

            it { is_expected.to be_finalised }
          end
        end
      end

      context 'prioritizes profit from store' do
        let(:store) { create(:store, selling_profit: 10.to_d) }

        it 'rounded price' do
          expect(flow.price.round(14)).to eq('22.16541353383459'.to_d)
        end
      end
    end

    context 'spends 4 crypto' do
      before(:each) { allow(BitexBot::Settings).to receive_message_chain(:selling, :quantity_to_sell_per_order).and_return(4.to_d) }

      its(:value_to_use) { is_expected.to eq(4) }
      its(:suggested_closing_price) { is_expected.to eq(25) }
      its(:price) { is_expected.to be >= 25 }

      it 'rounded price' do
        expect(flow.price.round(14)).to eq('25.18796992481203'.to_d)
      end

      context 'with other fx_rate' do
        before(:each) { allow(BitexBot::Settings).to receive(:selling_foreign_exchange_rate).and_return(10.to_d) }

        its(:value_to_use) { is_expected.to eq(4) }
        its(:suggested_closing_price) { is_expected.to eq(25) }
        its(:price) { is_expected.to be >= 25 * 10 }

        it 'rounded price' do
          expect(flow.price.round(14)).to eq('251.8796992481203'.to_d)
        end
      end

      context 'raises the price to charge on maker to take a profit' do
        before(:each) { allow(BitexBot::Settings).to receive_message_chain(:selling, :profit).and_return(50.to_d) }

        its(:value_to_use) { is_expected.to eq(4) }
        its(:suggested_closing_price) { is_expected.to eq(25) }
        its(:price) { is_expected.to be >= 25 }

        it 'rounded price' do
          expect(flow.price.round(14)).to eq('37.78195488721805'.to_d)
        end
      end

      context 'when there is a problem placing the ask on maker' do
        before(:each) do
          allow(BitexBot::Robot).to receive_message_chain(:maker, :send_order) do
            raise StandardError, 'boo'
          end
        end

        it 'fails' do
          expect do
            expect(flow).to be_nil
            expect(described_class.count).to be_zero
          end.to raise_error(BitexBot::CannotCreateFlow, 'boo')
        end
      end

      context 'fails when taker not enough fiat to spend in the other exchange' do
        let(:taker_balance) { 1.to_d }

        it 'fails' do
          expect do
            expect(flow).to be_nil
            expect(described_class.count).to be_zero
          end.to raise_exception(
            BitexBot::CannotCreateFlow,
            'Needed USD 100.75187969 on taker to close this sell position but you only have USD 1.0.'
          )
        end
      end
    end
  end

  describe 'when fetching open positions' do
    before(:each) { stub_bitex_transactions }

    it 'does not register buys from unknown asks' do
      expect { described_class.sync_positions.should be_empty }.not_to change { BitexBot::OpenSell.count }
    end

    context 'with known ask' do
      before(:each) { create(:sell_opening_flow) }

      let(:flow) { described_class.first }

      it { expect(flow.order_id).to eq(246) }
      it { expect(BitexBot::OpenSell.count).to be_zero }

      it 'only gets sells' do
        expect do
          described_class.sync_positions.first.tap do |open_trade|
            expect(open_trade.transaction_id).to eq(2)
            expect(open_trade.amount).to eq(600)
            expect(open_trade.quantity).to eq(2)
            expect(open_trade.price).to eq(300)
            expect(open_trade.opening_flow).to eq(flow)
          end
        end.to change { BitexBot::OpenSell.count }.by(1)
      end

      it 'does not register the same sell twice' do
        expect { described_class.sync_positions }.to change { BitexBot::OpenSell.count }.by(1)

        Timecop.travel(1.second.from_now)

        other_flow = create(:sell_opening_flow, order_id: 901)
        trade = build_bitex_user_transaction(:sell, 789, 901, 600, 2, 300, 0.05, BitexBot::Robot.maker.base_quote.to_sym)
        stub_bitex_transactions(trade)

        expect do
          described_class.sync_positions.first do |new_open_trade|
            expect(new_open_trade.transaction_id).to eq(789)
          end
        end.to change { BitexBot::OpenSell.count }.by(1)
      end

      it 'does not register buys from another order book' do
        trade = build_bitex_user_transaction(:sell, 777, 888, 600, 2, 300, 0.05, :boo)
        allow_any_instance_of(BitexBot::ApiWrappers::Bitex).to receive(:trades).and_return([trade])

        expect { expect(described_class.sync_positions).to be_empty }.not_to change { BitexBot::OpenSell.count }
      end
    end
  end
end
