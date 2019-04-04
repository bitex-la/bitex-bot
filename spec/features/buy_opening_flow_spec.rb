require 'spec_helper'

# When maker is Bitex and taker is Bitstamp
describe BitexBot::BuyOpeningFlow do
  before(:each) do
    stub_bitstamp_reset
    stub_bitex_reset

    allow(BitexBot::Robot)
      .to receive(:maker)
      .and_return(BitexApiWrapper.new(double(api_key: 'key', sandbox: true, trading_fee: 0.05, orderbook_code: 'btc_usd')))

    allow(BitexBot::Robot)
      .to receive(:taker)
      .and_return(BitstampApiWrapper.new(double(api_key: 'key', secret: 'xxx', client_id: 'yyy', order_book: 'btcusd')))

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
      allow(BitexBot::Settings).to receive(:buying_foreign_exchange_rate).and_return(1.to_d)
      allow(BitexBot::Settings).to receive_message_chain(:buying, :profit).and_return(0)
    end

    subject(:flow) do
      described_class.open_market(
        taker_balance,
        1_000.to_d,
        BitexBot::Robot.taker.market.bids,
        BitexBot::Robot.taker.transactions,
        0.5.to_d,
        0.25.to_d
      )
    end

    let(:taker_balance) { 1_000.to_d }

    context 'spends 50 fiat' do
      before(:each) do
        allow(BitexBot::Settings)
          .to receive_message_chain(:buying, :amount_to_spend_per_order)
          .and_return(50.to_d)
      end

      its(:value_to_use) { is_expected.to eq(50) }
      its(:suggested_closing_price) { is_expected.to eq(20) }
      its(:price) { is_expected.to be <= 20 }

      it 'rounded price' do
        expect(flow.price.round(14)).to eq('19.85074626865672'.to_d)
      end

      context 'finalising flow cancels associated bids' do
        subject(:flow) { create(:buy_opening_flow).tap { |opening_flow| opening_flow.place_orders } }

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
            .and_return(create(:store, buying_profit: 10))
        end

        it 'rounded price' do
          expect(flow.price.round(14)).to eq('17.86567164179105'.to_d)
        end
      end
    end

    context 'spends 100 fiat' do
      before(:each) { allow(BitexBot::Settings).to receive_message_chain(:buying, :amount_to_spend_per_order).and_return(100.to_d) }

      its(:value_to_use) { is_expected.to eq(100) }
      its(:suggested_closing_price) { is_expected.to eq(15) }
      its(:price) { is_expected.to be <= 15 }

      it 'rounded price' do
        expect(flow.price.round(14)).to eq('14.88805970149254'.to_d)
      end

      context 'with other fx_rate' do
        before(:each) { allow(BitexBot::Settings).to receive(:buying_foreign_exchange_rate).and_return(10.to_d) }

        its(:value_to_use) { is_expected.to eq(100) }
        its(:suggested_closing_price) { is_expected.to eq(15) }
        its(:price) { is_expected.to be <= 15 * 10 }

        it 'rounded price' do
          expect(flow.price.round(14)).to eq('148.88059701492537'.to_d)
        end
      end

      context 'lowers the price to pay on maker to take a profit' do
        before(:each) { allow(BitexBot::Settings).to receive_message_chain(:buying, :profit).and_return(50.to_d) }

        its(:value_to_use) { is_expected.to eq(100) }
        its(:suggested_closing_price) { is_expected.to eq(15) }
        its(:price) { is_expected.to be <= 15 }

        it 'rounded price' do
          expect(flow.price.round(14)).to eq('7.44402985074627'.to_d)
        end
      end

      context 'when there is a problem placing the bids on maker' do
        before(:each) do
          allow(BitexBot::Robot).to receive_message_chain(:maker, :send_order) do
            raise StandardError, 'boo shit'
          end
        end

        it 'not brokes flow creation, but no creates opening orders' do
          expect do
            is_expected.to be_a(described_class)
          end.not_to change { BitexBot::OpeningBid.count }
        end
      end

      context 'fails when taker not enough crypto to sell in the other exchange' do
        let(:taker_balance) { 1.to_d }

        it 'fails' do
          expect do
            expect(flow).to be_nil
            expect(described_class.count).to be_zero
          end.to raise_exception(
            BitexBot::CannotCreateFlow,
            'Needed BTC 6.71679197 on taker to close this buy position but you only have BTC 1.0.'
          )
        end
      end
    end
  end

  describe 'when fetching open positions' do
    before(:each) { stub_bitex_transactions }

    it 'does not register buys from unknown bids' do
      expect { described_class.sync_positions }.not_to change { BitexBot::OpenBuy.count }
    end

    context 'with known bid' do
      before(:each) { create(:buy_opening_flow, orders: [{ order_id: 123 }]) }

      let(:flow) { described_class.first }

      it 'only gets buys' do
        expect(flow.opening_orders.take.order_id).to eq('123')
        expect(BitexBot::OpenBuy.count).to be_zero

        expect do
          described_class.sync_positions
          expect(BitexBot::OpenBuy.find_by(transaction_id: 123)).to be_present
        end.to change { BitexBot::OpenBuy.count }.by(1)
      end

      it 'does not register the same buy twice' do
        expect { described_class.sync_positions }.to change { BitexBot::OpenBuy.count }.by(1)

        Timecop.travel(1.second.from_now)

        other_flow = create(:buy_opening_flow, orders: [{ order_id: 789 }])
        trade = build_bitex_user_transaction(:buy, 789, 600, 2, 300, 0.05, BitexBot::Robot.maker.base_quote.to_sym)
        stub_bitex_transactions(trade)

        expect do
          described_class.sync_positions
          expect(BitexBot::OpenBuy.find_by(transaction_id: 789)).to be_present
        end.to change { BitexBot::OpenBuy.count }.by(1)
      end

      it 'does not register buys from another orderbook' do
        trade = build_bitex_user_transaction(:buy, 777, 600, 2, 300, 0.05, :boo_shit)
        allow_any_instance_of(BitexApiWrapper).to receive(:trades).and_return([trade])

        expect { described_class.sync_positions }.not_to change { BitexBot::OpenBuy.count }
      end
    end
  end
end
