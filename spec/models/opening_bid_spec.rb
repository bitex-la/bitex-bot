require 'spec_helper'

describe BitexBot::OpeningBid do
  it_behaves_like 'OpeningOrders'

  describe '#finalise' do
    context 'with finalised status' do
      subject(:opening_order) { create(:opening_bid, status: :finalised) }

      its(:finalise) { is_expected.to be_nil }
    end

    context 'with executing status' do
      before(:each) { allow_any_instance_of(described_class).to receive(:order).and_return(order) }

      subject(:opening_order) { create(:opening_bid, status: :executing, order_id: '1', role: role) }

      let(:order) { BitexApiWrapper::Order.new('1', :bid, 400, 2, Time.now.to_i, order_status, double) }

      context 'with order finalisable' do
        before(:each) { allow_any_instance_of(described_class).to receive(:order_finalisable?).and_return(true) }

        context 'with informant role' do
          let(:role) { :informant }

          context 'with order finalisable by completed status' do
            before(:each) { allow(BitexBot::Robot).to receive(:notify).with('OpeningBid informant with id 1 was hit') }

            let(:order_status) { :completed }

            it do
              expect(BitexBot::Robot)
                .to receive(:notify)
                .with("BitexBot::OpeningBid informant with id #{opening_order.id} was hit")

              opening_order.finalise

              expect(opening_order.status).to eq('finalised')
            end
          end

          context 'with order finalisable by cancelled status' do
            let(:order_status) { :cancelled }

            it do
              opening_order.finalise

              expect(opening_order.status).to eq('finalised')
            end
          end
        end

        context 'with not informant role' do
          let(:order_status) { :dont_care }
          let(:role) { described_class.roles.without(:informant).keys.sample }

          it do
            opening_order.finalise

            expect(opening_order.status).to eq('finalised')
          end
        end
      end

      context 'with order not finalisable and indifferent role' do
        before(:each) do
          allow_any_instance_of(described_class).to receive(:order_finalisable?).and_return(false)

          allow(BitexBot::Robot).to receive_message_chain(:maker, :cancel_order).with(order)
        end

        let(:order_status) { :dont_care }
        let(:role) { described_class.roles.keys.sample }

        it do
          expect(BitexBot::Robot).to receive_message_chain(:maker, :cancel_order).with(order)

          opening_order.finalise

          expect(opening_order.status).to eq('settling')
        end
      end
    end
  end

  describe '#resume' do
    before(:each) { allow_any_instance_of(BitexBot::BuyOpeningFlow).to receive(:fx_rate).and_return(10.to_d) }

    subject { create(:opening_bid, order_id: 'order#45', price: 300, amount: 3).resume }

    it { is_expected.to eq('buy: order#45, status: executing, price: 300.0, amount: 30.0') }
  end

  describe '#order' do
    before(:each) { allow(BitexBot::Robot).to receive_message_chain(:maker, :order_by_id).with(:buy, '1').and_return(order) }

    subject { create(:opening_bid, order_id: '1') }

    let(:order) { BitexApiWrapper::Order.new('1', :bid, 400, 2, Time.now.to_i, :status, double) }

    its(:order) { is_expected.to eq(order) }
  end
end
