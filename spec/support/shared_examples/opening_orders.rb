shared_examples_for 'OpeningOrders' do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:order_id) }
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to define_enum_for(:role).with_values(%i[no_role first_tip second_tip support informant final]) }
    it { is_expected.to define_enum_for(:status).with_values(%i[executing settling finalised]) }
  end

  describe '#order_finalisable?' do
    before(:each) { allow_any_instance_of(described_class).to receive(:order).and_return(order) }

    let(:order) { BitexBot::Exchanges::Order.new('dontcare', :type, 400, 2, Time.now.to_i, status, 'client_order_id', double) }

    context 'with cancelled order status' do
      let(:status) { :cancelled }

      its(:order_finalisable?) { is_expected.to be_truthy }
    end

    context 'with completed order status' do
      let(:status) { :completed }

      its(:order_finalisable?) { is_expected.to be_truthy }
    end

    context 'with any other order status' do
      let(:status) { :any_other}

      its(:order_finalisable?) { is_expected.to be_falsey }
    end
  end
end
