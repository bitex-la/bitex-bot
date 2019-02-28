shared_examples_for 'OpeningFlows' do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to validate_presence_of(:value_to_use) }
    it { is_expected.to validate_presence_of(:order_id) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[executing settling finalised]) }
  end

  describe '.scopes' do
    before(:each) { 3.times { described_class.create(price: 1, value_to_use: 1, order_id: 1) } }

    context 'active' do
      before(:each) { described_class.last.finalised! }

      subject(:active) { described_class.active }

      its(:count) { is_expected.to eq(2) }
    end

    context 'old active' do
      before(:each) do
        allow(BitexBot::Settings).to receive(:time_to_live).and_return(60 * 60 * 24 * 2) # 2 days ago
        described_class.find(1).finalised!
        described_class.find(2).update(created_at: old_date)
      end

      let(:old_date) { 3.days.ago }

      subject(:old_active) { described_class.old_active }

      its(:count) { is_expected.to eq(1) }
      its(:'take.created_at') { is_expected.to eq(old_date) }
    end
  end

  describe '.maker_plus' do
    before(:each) { allow(described_class).to receive(:value_to_use).and_return(20) }
    subject(:plus) { described_class.maker_plus(10) }

    it { is_expected.to eq(2) }
  end

  describe '.maker_price' do
    before(:each) do
      allow(described_class).to receive(:fx_rate).and_return(10)
      allow(described_class).to receive(:value_to_use).and_return(2)
      allow(described_class).to receive(:profit).and_return(1)
    end

    subject(:price) { described_class.maker_price(2) }

    it { is_expected.to eq(10) }
  end

  describe '.enough_funds?' do
    subject { described_class.enough_funds?(funds, amount) }

    context 'have funds' do
      let(:funds) { 100 }
      let(:amount) { 10 }

      it { is_expected.to be_truthy }
    end

    context 'have not funds' do
      let(:funds) { 10 }
      let(:amount) { 100 }

      it { is_expected.to be_falsey }
    end
  end

  describe '.calc_taker_amount' do
    before(:each) do
      allow(described_class).to receive(:value_to_use).and_return(10)
      allow(described_class).to receive(:maker_plus).and_return(20)
      allow(described_class).to receive(:safest_price).and_return(price)
      allow(described_class).to receive(:remote_value_to_use).and_return(amount)
      allow(described_class).to receive(:taker_specie_to_spend).and_return('SPECIE_TO_SPEND')
      allow(BitexBot::Robot).to receive_message_chain(:taker, :name).and_return('TAKER_NAME')
    end

    let(:order) { build_bitex_order(:dont_care_type, '111_111', 300, 10, :dont_care_orderbook) }
    let(:trade) { build_bitex_user_transaction(:dont_care, '7_891_011', 11, 11, 11, 11, :dont_care_orderbook) }
    let(:amount) { 100 }
    let(:price) { 30 }

    subject(:amount_and_price) { described_class.calc_taker_amount(1_000, 5, 10, [order], [trade]) }

    it { is_expected.to be_a(Array) }

    its(:first) { is_expected.to eq(amount) }
    its(:last) { is_expected.to eq(price) }

    context 'taker market not enough funds' do
      before(:each) { allow(described_class).to receive(:remote_value_to_use).and_return(100_000) }

      it 'cannot create flow' do
        expect { amount_and_price }
          .to raise_error(
            BitexBot::CannotCreateFlow,
            "Needed 100000.0 but you only have SPECIE_TO_SPEND 1000.0 on your taker market."
        )
      end
    end
  end

  describe 'create for market' do
    before(:each) do
      allow(described_class).to receive(:value_to_use).and_return(10_000.to_d)
      allow(described_class).to receive(:fx_rate).and_return(1.to_d)
      allow(described_class).to receive(:calc_taker_amount).and_return([100, closing_price])
      allow(described_class).to receive(:maker_price).and_return(minimun_price)
      allow(described_class).to receive(:trade_type).and_return(:dont_care_trade_type)

      # Don't care by another data fields.
      maker_order = ApiWrapper::Order.new(order_id, :dont_care_trade_type, 300, 10, Time.now.to_i, 'raw_order')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :send_order).and_return(maker_order)
    end

    let(:order_id) { '111111' }
    let(:minimun_price) { 300 }
    let(:closing_price) { 200 }

    let(:taker_orders) { [ApiWrapper::Order.new('123456', :sell, 1234, 1234, Time.now.to_i, 'raw_order')] }
    let(:taker_transactions) { [ApiWrapper::Transaction.new('7891011', 1234, 1234, Time.now.to_i, 'raw_transaction')] }
    let(:store) { BitexBot::Store.create }

    # args: taker_balance, maker_balance, taker_orders, taker_transactions, maker_fee, taker_fee, store
    subject(:open_market) { described_class.open_market(1000, 2000, taker_orders, taker_transactions, 0.25, 0.50, store) }

    context 'succesful' do
      before(:each) do
        allow(described_class).to receive(:enough_funds?).and_return(true)
        allow(described_class).to receive(:maker_specie_to_spend).and_return('SPECIE_TO_SPEND')
        allow(described_class).to receive(:maker_specie_to_obtain).and_return('SPECIE_TO_OBTAIN')
        allow(BitexBot::Robot).to receive_message_chain(:taker, :quote).and_return('TAKER_CRYPTO_SPECIE')
      end

      it { is_expected.to be_a(BitexBot::OpeningFlow) }

      its(:price) { is_expected.to eq(minimun_price) }
      its(:value_to_use) { is_expected.to eq(10_000) }
      its(:suggested_closing_price) { is_expected.to eq(closing_price) }
      its(:order_id) { is_expected.to eq(order_id.to_i) }
      its(:status) { is_expected.to eq('executing') }
    end

    context 'cannot create' do
      before(:each) do
        allow(described_class).to receive(:enough_funds?).and_return(true)
        allow(described_class).to receive(:create_flow!) { raise StandardError, 'any reason'}
      end

      context 'by some reason' do
        it { expect { open_market }.to raise_error(BitexBot::CannotCreateFlow, 'any reason') }
      end

      context 'by not enough funds' do
        before(:each) do
          allow(described_class).to receive(:enough_funds?).and_return(false)
          allow(described_class).to receive(:maker_specie_to_spend).and_return('SPECIE')
          allow(described_class).to receive(:order_type).and_return('ORDER_TYPE')
          allow(BitexBot::Robot).to receive_message_chain(:maker, :name).and_return('MAKER_NAME')
        end

        it do
          expect { open_market }
            .to raise_error(
              BitexBot::CannotCreateFlow,
              'Needed SPECIE 10000.0 on MAKER_NAME maker to place this ORDER_TYPE but you only have SPECIE 2000.0.'
          )
        end
      end
    end
  end

  describe '.expected_orderbook?' do
    before(:each) { allow(BitexBot::Robot).to receive_message_chain(:maker, :base_quote).and_return('crypto_fiat') }

    subject(:expected?) { described_class.expected_orderbook?(trade) }

    let(:trade) { build_bitex_user_transaction(:dont_care, '999_999', 10, 20, 100, 5, orderbook_code) }

    context 'expected' do
      let(:orderbook_code) { 'crypto_fiat' }

      it { is_expected.to be_truthy }
    end

    context 'unexpected' do
      let(:orderbook_code) { 'buu_shit' }

      it { is_expected.to be_falsey }
    end
  end

  describe '.active_trade?' do
    context 'without threshold' do
      # unless threshold present, we dont care about trade
      subject(:inactive) { described_class.active_trade?(double, nil) }

      it { is_expected.to be_falsey }
    end

    context 'with threshold' do
      subject(:active?) { Timecop.freeze(Time.now) { described_class.active_trade?(trade, Time.now) } }

      let(:trade) { build_bitex_user_transaction(:dont_care, 11, 11, 11, 111, 11, :dont_care, created_at) }

      context 'active' do
        let(:created_at) { 31.minutes.ago }

        it { is_expected.to be_truthy }
      end

      context 'inactive' do
        let(:created_at) { 30.minutes.ago.to_i }

        it { is_expected.to be_falsey }
      end
    end
  end

  describe '.create_flow!' do
    before(:each) do
      allow(described_class).to receive(:value_to_use).and_return(15)
      allow(described_class).to receive(:maker_specie_to_spend).and_return('SPECIE_TO_SPEND')
      allow(described_class).to receive(:maker_specie_to_obtain).and_return('SPECIE_TO_OBTAIN')
      allow(BitexBot::Robot).to receive_message_chain(:taker, :quote).and_return('taker_crypto_specie')
    end

    subject(:flow) { described_class.create_flow!(100, 200, 2, order) }

    let(:order) { build_bitex_order(:dont_care, 111, 111, :dont_care, :executing, Time.now.utc, '123456') }

    it { is_expected.to be_a(BitexBot::OpeningFlow) }

    its(:id) { is_expected.to be_present }
    its(:price) { is_expected.to eq(100) }
    its(:value_to_use) { is_expected.to eq(15) }
    its(:suggested_closing_price) { is_expected.to eq(200) }
    its(:status) { is_expected.to eq('executing') }
    its(:order_id) { is_expected.to eq(123456) }
  end

  describe '#finalise!' do
    before(:each) do
      allow_any_instance_of(described_class).to receive(:finalizable?).and_return(finalizable)
      allow_any_instance_of(described_class).to receive(:cancel!).and_return(:we_dont_care)
    end

    subject(:flow) do
      create(described_class.name.demodulize.underscore.to_sym).tap do |opening|
        opening.finalise!
      end
    end

    context 'finalizable' do
      let(:finalizable) { true }

      its(:finalised?) { is_expected.to be_truthy }
    end

    context 'non finalizable' do
      let(:finalizable) { false }

      its(:finalised?) { is_expected.to be_falsey }
    end
  end

  describe '#cancel!' do
    before(:each) do
      allow(BitexBot::Robot).to receive_message_chain(:maker, :cancel_order).and_return(:we_dont_care)
      allow_any_instance_of(described_class).to receive(:order).and_return(:we_dont_care)
    end

    subject(:flow) do
      create(described_class.name.demodulize.underscore.to_sym, status: status).tap do |opening|
        opening.send(:cancel!)
      end
    end

    # Allways flows will be setttled
    context 'if finalised' do
      let(:status) { :finalised }

      its(:settling?) { is_expected.to be_truthy }
    end

    context 'if executing' do
      let(:status) { :executing }

      its(:settling?) { is_expected.to be_truthy }
    end

    context 'if settling' do
      let(:status) { :settling }

      its(:settling?) { is_expected.to be_truthy }
    end
  end
end
