shared_examples_for 'CloseableTrades' do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:order_id) }
  end

  describe 'has a valid factory' do
    its(:valid?) { is_expected.to be_truthy }
    its(:order_id) { is_expected.to eq('1') }
    its(:quantity) { is_expected.to eq(2) }
    its(:amount) { is_expected.to eq(220) }
  end

  describe '#sync' do
    before(:each) do
      allow(BitexBot::Robot)
        .to receive_message_chain(:taker, :amount_and_quantity)
        .with('1')
        .and_return([10.to_d, 20.to_d])
    end

    it do
      expect { subject.sync }
        .to change(subject, :amount).from(220).to(10)
        .and change(subject, :quantity).from(2).to(20)
    end
  end

  describe '#cancellable?' do
    context 'with exectuded order dont care about order expiration' do
      before(:each) { allow_any_instance_of(described_class).to receive(:executed?).and_return(true) }

      its(:cancellable?) { is_expected.to be_falsey }
    end

    context 'with no executed order' do
      before(:each) { allow_any_instance_of(described_class).to receive(:executed?).and_return(false) }

      context 'with not expired order' do
        before(:each) { allow_any_instance_of(described_class).to receive(:expired?).and_return(false) }

        its(:cancellable?) { is_expected.to be_falsey }
      end

      context 'with expired order' do
        before(:each) { allow_any_instance_of(described_class).to receive(:expired?).and_return(true) }

        its(:cancellable?) { is_expected.to be_truthy }
      end
    end
  end

  describe '#executed?' do
    context 'yes' do
      before(:each) { allow_any_instance_of(described_class).to receive(:order).and_return(nil) }

      its(:executed?) { is_expected.to be_truthy }
    end

    context 'no' do
      before(:each) { allow_any_instance_of(described_class).to receive(:order).and_return(double) }

      its(:executed?) { is_expected.to be_falsey }
    end
  end

  describe '#order' do
    before(:each) do
      allow(BitexBot::Robot)
        .to receive_message_chain(:taker, :orders)
        .and_return([taker_order])
    end

    let(:taker_order) { build_bitex_order(:dont_care, 10, 20, :dont_care, :executing, Time.now.utc, '1') }

    its(:order) { is_expected.to eq(taker_order) }
  end

  describe '#expired?' do
    before(:each) { allow(BitexBot::Settings).to receive(:close_time_to_live).and_return(close_time) }

    subject { Timecop.travel(creation_time) { close_trade} }

    context 'yes' do
      let(:close_time) { 10 }
      let(:creation_time) { (close_time + 10).seconds.ago }

      its(:expired?) { is_expected.to be_truthy }
    end

    context 'no' do
      let(:close_time) { 10 }
      let(:creation_time) { (close_time + 10).seconds.from_now }

      its(:expired?) { is_expected.to be_falsey }
    end
  end

  describe '#summary' do
    its(:summary) do
      is_expected.to eq(
        "#{subject.closing_flow.class} ##{subject.closing_flow.id}: "\
        'order_id: 1, '\
        'desired_price: MAKER_QUOTE 110.0, '\
        'amount: MAKER_BASE 220.0, '\
        'quantity: MAKER_QUOTE 2.0.'
      )
    end
  end
end
