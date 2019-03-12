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
    before(:each) { allow(described_class).to receive(:value_to_use).and_return(20.to_d) }

    subject(:plus) { described_class.maker_plus(10.to_d) }

    it { is_expected.to eq(2) }
  end

  describe '.enough_funds?' do
    subject { described_class.enough_funds?(funds, amount) }

    context 'have funds' do
      let(:funds) { 100.to_d }
      let(:amount) { 10.to_d }

      it { is_expected.to be_truthy }
    end

    context 'have not funds' do
      let(:funds) { 10.to_d }
      let(:amount) { 100.to_d }

      it { is_expected.to be_falsey }
    end
  end

  describe '.calc_taker_amount' do
    before(:each) do
      allow(described_class).to receive(:value_to_use).and_return(10.to_d)
      allow(described_class).to receive(:maker_plus).and_return(20.to_d)
      allow(described_class).to receive(:safest_price).and_return(30.to_d)
      allow(described_class).to receive(:remote_value_to_use).and_return(100.to_d)
      allow(described_class).to receive(:taker_specie_to_spend).and_return('SPECIE_TO_SPEND')
      allow(described_class).to receive(:trade_type).and_return('TRADE_TYPE')
    end

    let(:order) { build_bitex_order(:dont_care_type, '111_111', 300, 10, :dont_care_orderbook) }
    let(:trade) { build_bitex_user_transaction(:dont_care, '7_891_011', 11, 11, 11, 11, :dont_care_orderbook) }

    subject(:amount_and_price) { described_class.calc_taker_amount(1_000.to_d, 5.to_d, 10.to_d, [order], [trade]) }

    it { is_expected.to be_a(Array) }

    its(:first) { is_expected.to eq(100) }
    its(:last) { is_expected.to eq(30) }

    context 'taker market not enough funds' do
      before(:each) { allow(described_class).to receive(:remote_value_to_use).and_return(100_000) }

      it 'cannot create flow' do
        expect { amount_and_price }
          .to raise_error(
            BitexBot::CannotCreateFlow,
            "Needed SPECIE_TO_SPEND 100000.0 on taker to close this TRADE_TYPE position but you only have SPECIE_TO_SPEND 1000.0."
        )
      end
    end
  end

  describe 'open market' do
    before(:each) do
      allow(described_class).to receive(:value_to_use).and_return(10_000.to_d)
      allow(described_class).to receive(:fx_rate).and_return(1.to_d)
      allow(described_class).to receive(:calc_taker_amount).and_return([100.to_d, closing_price])
      allow(described_class).to receive(:maker_price).and_return(minimun_price)
      allow(described_class).to receive(:trade_type).and_return(:dont_care_trade_type)

      # Don't care by another data fields.
      maker_order = ApiWrapper::Order.new(order_id, :dont_care_trade_type, 300, 10, Time.now.to_i, 'raw_order')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :send_order).and_return(maker_order)
    end

    let(:order_id) { '111111' }
    let(:minimun_price) { 300.to_d }
    let(:closing_price) { 200.to_d }

    let(:taker_orders) { [ApiWrapper::Order.new('123456', :sell, 1234, 1234, Time.now.to_i, 'raw_order')] }
    let(:taker_transactions) { [ApiWrapper::Transaction.new('7891011', 1234, 1234, Time.now.to_i, 'raw_transaction')] }
    let(:store) { BitexBot::Store.create }

    subject(:open_market) do
      described_class.open_market(1_000.to_d, 2_000.to_d, taker_orders, taker_transactions, 0.25.to_d, 0.50.to_d)
    end

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
        allow(described_class).to receive(:maker_specie_to_spend).and_return('MAKER_SPECIE_TO_SPEND')
        allow(described_class).to receive(:maker_specie_to_obtain).and_return('MAKER_SPECIE_TO_OBTAIN')
        allow(described_class).to receive(:enough_funds?).with(2_000, 10_000).and_return(true)
        allow(described_class).to receive(:create!) { raise StandardError, 'any reason'}
      end

      context 'by some reason' do
        it { expect { open_market }.to raise_error(StandardError, 'any reason') }
      end

      context 'by not enough funds' do
        before(:each) do
          allow(described_class).to receive(:enough_funds?).and_return(false)
          allow(described_class).to receive(:maker_specie_to_spend).and_return('SPECIE')
          allow(described_class).to receive(:trade_type).and_return('TRADE_TYPE')
        end

        it do
          expect { open_market }
            .to raise_error(
              BitexBot::CannotCreateFlow,
              'Needed SPECIE 10000.0 on maker to place this TRADE_TYPE but you only have SPECIE 2000.0.'
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
end
