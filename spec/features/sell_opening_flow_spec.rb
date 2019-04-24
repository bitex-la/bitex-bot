require 'spec_helper'

# When maker is Bitex and taker is Bitstamp
describe BitexBot::SellOpeningFlow do
  before(:each) do
    stub_bitstamp_reset
    stub_bitex_reset

    allow(BitexBot::Robot)
      .to receive(:maker)
      .and_return(BitexBot::Exchanges::Bitex.new(double(api_key: 'key', sandbox: true, trading_fee: 0.05, orderbook_code: 'btc_usd')))

    allow(BitexBot::Robot)
      .to receive(:taker)
      .and_return(BitexBot::Exchanges::Bitstamp.new(double(api_key: 'key', secret: 'xxx', client_id: 'yyy', orderbook_code: 'btcusd')))

    allow(BitexBot::Robot).to receive(:logger).and_return(BitexBot::Logger.setup)

    allow(BitexBot::Robot).to receive(:store).and_return(create(:store))
  end

  after(:each) do
    stub_bitstamp_reset
    stub_bitex_reset
  end

  describe 'when creating a buying flow' do
    before(:each) do
      stub_bitstamp_market
      stub_bitstamp_transactions
      stub_bitex_active_orders

      allow(BitexBot::Settings).to receive(:time_to_live).and_return(3)
      allow(BitexBot::Settings).to receive(:selling_foreign_exchange_rate).and_return(1.to_d)
      allow(BitexBot::Settings).to receive_message_chain(:selling, :profit).and_return(0)
    end

    subject(:flow) do
      described_class.open_market(
        1_000.to_d,
        BitexBot::Robot.taker.market.asks,
        BitexBot::Robot.taker.transactions,
        0.5.to_d,
        0.25.to_d
      )
    end

    context 'sells 2 crypto' do
      before(:each) do
        allow(BitexBot::Settings)
          .to receive_message_chain(:selling, :quantity_to_sell_per_order)
          .and_return(2.to_d)
      end

      its(:value_to_use) { is_expected.to eq(2) }
      its(:suggested_closing_price) { is_expected.to eq(20) }
      its(:price) { is_expected.to be >= 20 }

      it 'rounded price' do
        expect(flow.price.round(14)).to eq('20.15037593984962'.to_d)
      end

      context 'finalising flow cancels associated ask' do
        subject(:flow) { create(:sell_opening_flow).tap { |opening_flow| opening_flow.place_orders } }

        its(:status) { is_expected.to eq('executing') }
        it { expect(flow.opening_orders.map(&:status)).to all(eq('executing')) }

        context 'cancel one time, but first time orders not be finalisables' do
          before(:each) { flow.finalise }

          its(:status) { is_expected.to eq('settling') }
          it { expect(flow.opening_orders.map(&:status)).to all(eq('settling')) }

          context 'cancels one more time' do
            before(:each) { flow.finalise }

            its(:status) { is_expected.to eq('finalised') }
            it { expect(flow.opening_orders.map(&:status)).to all(eq('finalised')) }
          end
        end
      end

      context 'prioritizes profit from store' do
        before(:each) do
          allow(BitexBot::Robot)
            .to receive(:store)
            .and_return(create(:store, selling_profit: 10))
        end

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

      context 'when there is a problem placing the asks on maker' do
        before(:each) do
          allow(BitexBot::Robot).to receive_message_chain(:maker, :send_order) do
            raise StandardError, 'boo shit'
          end
        end

        it 'not brokes flow creation, but no creates opening orders' do
          expect do
            is_expected.to be_a(described_class)
          end.not_to change { BitexBot::OpeningAsk.count }
        end
      end
    end
  end

  describe 'when fetching open positions' do
    before(:each) { stub_bitex_transactions }

    it 'does not register buys from unknown asks' do
      expect { described_class.sync_positions }.not_to change { BitexBot::OpenSell.count }
    end

    context 'with known ask' do
      before(:each) { create(:sell_opening_flow, orders: [{ order_id: 246 }]) }

      let(:flow) { described_class.first }

      it 'only gets sells' do
        expect(flow.opening_orders.take.order_id).to eq('246')
        expect(BitexBot::OpenSell.count).to be_zero

        expect do
          described_class.sync_positions
          expect(BitexBot::OpenSell.find_by(transaction_id: 246)).to be_present
        end.to change { BitexBot::OpenSell.count }.by(1)
      end

      it 'does not register the same sell twice' do
        expect { described_class.sync_positions }.to change { BitexBot::OpenSell.count }.by(1)

        Timecop.travel(1.second.from_now)

        other_flow = create(:sell_opening_flow, orders: [{ order_id: 789 }])
        trade = build_bitex_user_transaction(:sell, 789, 600, 2, 300, 0.05, BitexBot::Robot.maker.base_quote.to_sym)
        stub_bitex_transactions(trade)

        expect do
          described_class.sync_positions
          expect(BitexBot::OpenSell.find_by(transaction_id: 789)).to be_present
        end.to change { BitexBot::OpenSell.count }.by(1)
      end

      it 'does not register buys from another order book' do
        trade = build_bitex_user_transaction(:sell, 777, 600, 2, 300, 0.05, :boo_shit)
        allow_any_instance_of(BitexBot::Exchanges::Bitex).to receive(:trades).and_return([trade])

        expect { described_class.sync_positions }.not_to change { BitexBot::OpenSell.count }
      end
    end
  end
end
