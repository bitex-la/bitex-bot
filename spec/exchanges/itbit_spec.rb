require 'spec_helper'

describe BitexBot::Exchanges::Itbit do
  let(:exchange) do
    settings = BitexBot::SettingsClass.new(
     client_key: 'apikey',
     secret: 'secret',
     user_id: 'USER-ID',
     default_wallet_id: '7118de95-4bdd-4196-b674-f267154906d8',
     orderbook_code: 'xbtusd'
    )

    described_class.new(settings)
  end

  describe 'Sends User-Agent header' do
    let(:url) { "https://api.itbit.com/v1/markets/#{exchange.currency_pair.code.upcase}/order_book" }

    it do
      stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

      # We don't care about the response
      exchange.market rescue nil

      expect(stub_stuff).to have_been_requested
    end
  end

  describe '#asset_pairs' do
    describe '#currency_pair' do
      subject(:currency_pair) { exchange.currency_pair }

      it { is_expected.to be_a(Hashie::Mash) }

      its(:base) { is_expected.to eq('xbt') }
      its(:quote) { is_expected.to eq('usd') }
      its(:code) { is_expected.to eq('xbtusd') }
    end

    describe '#base' do
      subject(:base) { exchange.base }

      it { is_expected.to eq('XBT') }
    end

    describe '#quote' do
      subject(:quote) { exchange.quote }

      it { is_expected.to eq('USD') }
    end

    describe '#base_quote' do
      subject(:base_quote) { exchange.base_quote }

      it { is_expected.to eq('XBT_USD') }
    end
  end

  describe '#balance', vcr: { cassette_name: 'itbit/balance' } do
    subject(:balance) { exchange.balance }

    it { is_expected.to be_a(BitexBot::Exchanges::BalanceSummary) }

    describe '#wallet' do
      subject(:raw_wallet) { exchange.send(:wallet) }

      its([:id]) { is_expected.to eq('7118de95-4bdd-4196-b674-f267154906d8') }
      its([:user_id]) { is_expected.to eq('B2365BBE-6EF8-42D1-BED5-5CB0F51AD56F'.downcase) }
      its([:name]) { is_expected.to eq('Wallet') }
      its([:balances]) { is_expected.to all(be_a(Hash)) }

      describe '#balance_summary_parser' do
        subject(:summary) { exchange.send(:balance_summary_parser, raw_wallet[:balances]) }

        it { is_expected.to be_a(BitexBot::Exchanges::BalanceSummary) }

        its(:crypto) { is_expected.to be_a(BitexBot::Exchanges::Balance)  }
        its(:fiat) { is_expected.to be_a(BitexBot::Exchanges::Balance)  }
        its(:fee) { is_expected.to be_a(BigDecimal).and eq(0.5) }
      end

      describe '#balance_parser' do
        subject(:balance) { exchange.send(:balance_parser, raw_wallet[:balances], :usd) }

        it { is_expected.to be_a(BitexBot::Exchanges::Balance) }

        its(:total) { is_expected.to be_a(BigDecimal).and eq(199.05_017_669) }
        its(:reserved) { is_expected.to be_a(BigDecimal).and eq(0) }
        its(:available) { is_expected.to be_a(BigDecimal).and eq(199.05_017_669) }
      end
    end
  end

  describe '#market', vcr: { cassette_name: 'itbit/market' } do
    subject(:market) { exchange.market }

    it { is_expected.to be_a(BitexBot::Exchanges::Orderbook) }

    describe '#market_accessor' do
      subject(:accessor) { exchange.send(:market_accessor) }

      it { is_expected.to eq(::Itbit::XBTUSDMarketData) }

      describe '#orderbook_parser' do
        let(:raw_orderbook) { accessor.orders }

        subject(:orderbook) { exchange.send(:orderbook_parser, raw_orderbook) }

        it { is_expected.to be_a(BitexBot::Exchanges::Orderbook) }

        its(:timestamp) { is_expected.to be_a(Integer) }
        its(:asks) { is_expected.to all(be_a(BitexBot::Exchanges::OrderSummary)) }
        its(:bids) { is_expected.to all(be_a(BitexBot::Exchanges::OrderSummary)) }

        describe '#order_summary_parser' do
          let(:raw_orders) { raw_orderbook[:bids] }

          subject(:order_summaries) { exchange.send(:order_summary_parser, raw_orders) }

          it { is_expected.to all(be_a(BitexBot::Exchanges::OrderSummary)) }

          context 'taking a sample' do
            subject(:order_summary) { order_summaries.first }

            its(:price) { is_expected.to be_a(BigDecimal).and eq(5_224.26) }
            its(:amount) { is_expected.to be_a(BigDecimal).and eq(1.00_966_747) }
          end
        end
      end
    end
  end

  describe '#orders', vcr: { cassette_name: 'itbit/orders' } do
    subject(:orders) { exchange.orders }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Order)) }

    context 'with raw order' do
      let(:raw_order) { ::Itbit::Order.all(instrument: :xbtusd, status: :open).first }

      describe '#order_parser' do
        before(:each) { allow_any_instance_of(described_class).to receive(:client_order_id).and_return('UStni6kW4bt36') }
        subject(:order) { exchange.send(:order_parser, raw_order) }

        it { is_expected.to be_a(BitexBot::Exchanges::Order) }

        its(:id) { is_expected.to eq('c1b338c8-2d30-4c66-b198-0b96bf1ee8d3') }
        its(:type) { is_expected.to eq(:bid) }
        its(:price) { is_expected.to be_a(BigDecimal).and eq(1_000) }
        its(:amount) { is_expected.to be_a(BigDecimal).and eq(0.003) }
        its(:timestamp) { is_expected.to be_a(Integer).and eq(1_554_821_976) }
        its(:status) { is_expected.to eq(:executing) }
        its(:client_order_id) { is_expected.to be_nil }
        its(:raw) { is_expected.to be_a(::Itbit::Order) }
      end

      describe '#order_statuses' do
        subject(:statuses) { exchange.send(:order_statuses) }

        it { is_expected.to eq(open: :executing, filled: :completed, cancelled: :cancelled, rejected: :cancelled) }
      end

      describe '#order_types' do
        subject(:order_types) { exchange.send(:order_types) }

        it { is_expected.to eq(buy: :bid, sell: :ask) }
      end
    end
  end

  describe '#enough_order_size?' do
    it { expect(described_class::MIN_AMOUNT).to be_a(BigDecimal).and eq(10) }

    context 'enough' do
      it { expect(exchange.enough_order_size?(1, 10, nil)).to be_truthy }
      it { expect(exchange.enough_order_size?(10, 1, nil)).to be_truthy }
    end

    context 'not enough' do
      it { expect(exchange.enough_order_size?(0.99, 10, nil)).to be_falsey }
      it { expect(exchange.enough_order_size?(10, 0.99, nil)).to be_falsey }
    end
  end

  describe '#place_order' do
    subject(:place_order) { exchange.place_order(:buy, 3_500, 2) }

    let(:order) { BitexBot::Exchanges::Order.new('order_id') }

    context 'succesfull' do
      before(:each) { allow_any_instance_of(described_class).to receive(:send_order).and_return(order) }

      its(:id) { is_expected.to eq('order_id') }
    end

    context 'lost' do
      before(:each) { allow_any_instance_of(described_class).to receive(:send_order).and_return(nil) }

      context 'and retrieved' do
        before(:each) { allow_any_instance_of(described_class).to receive(:find_lost).and_return(order) }

        its(:id) { is_expected.to eq('order_id') }
      end

      context 'and not retrieved' do
        before(:each) { allow_any_instance_of(described_class).to receive(:find_lost).and_return(nil) }

        it { expect { subject }.to raise_error(BitexBot::Exchanges::OrderNotFound, 'Not found buy order for XBT 2 @ USD 3500.') }
      end
    end
  end

  describe '#send_order', vcr: { cassette_name: 'itbit/send_order' } do
    before(:each) { allow_any_instance_of(described_class).to receive(:client_order_id).and_return('USmrZej4UQuhY') }

    subject(:order) { exchange.send(:send_order, :buy, 100, 0.2) }

    it { is_expected.to be_a(BitexBot::Exchanges::Order) }

    its(:id) { is_expected.to be_present }
    its(:type) { is_expected.to eq(:bid) }
    its(:price) { is_expected.to eq(100) }
    its(:amount) { is_expected.to eq(0.2) }
    its(:timestamp) { is_expected.to be_present }
    its(:status) { is_expected.to eq(:executing) }
    its(:client_order_id) { is_expected.to eq('my_beta_identifier') }
    its(:raw) { is_expected.to be_a(::Itbit::Order) }
  end

  describe '#find_lost', vcr: { cassette_name: 'itbit/find_lost' } do
    before(:each) { allow_any_instance_of(described_class).to receive(:client_order_id).and_return('B2sL5T806Y3wU') }

    subject(:lost) { exchange.send(:find_lost, :buy, 1_000.to_d, 0.1.to_d, 1.minutes.ago.utc) }

    it { is_expected.to be_a(BitexBot::Exchanges::Order) }

    its(:'raw.client_order_identifier') { is_expected.to eq('B2sL5T806Y3wU') }
    its(:'raw.side') { is_expected.to eq(:buy) }
    its(:price) { is_expected.to be_a(BigDecimal).and eq(1000) }
    its(:amount) { is_expected.to be_a(BigDecimal).and eq(0.1) }
  end

  describe '#rounded_price' do
    context 'between 0 and 0.25' do
      let(:price) { 1.07.to_d }

      it { expect(exchange.send(:rounded_price, :buy, price)).to be_a(BigDecimal).and eq(1) }
      it { expect(exchange.send(:rounded_price, :sell, price)).to be_a(BigDecimal).and eq(1.25) }
    end

    context 'between 0.25 and 0.5' do
      let(:price) { 1.27.to_d }

      it { expect(exchange.send(:rounded_price, :buy, price)).to be_a(BigDecimal).and eq(1.25) }
      it { expect(exchange.send(:rounded_price, :sell, price)).to be_a(BigDecimal).and eq(1.5) }
    end

    context 'between 0.5 and 0.75' do
      let(:price) { 1.57.to_d }

      it { expect(exchange.send(:rounded_price, :buy, price)).to be_a(BigDecimal).and eq(1.5) }
      it { expect(exchange.send(:rounded_price, :sell, price)).to be_a(BigDecimal).and eq(1.75) }
    end

    context 'between 0.75 and 1.00' do
      let(:price) { 1.77.to_d }

      it { expect(exchange.send(:rounded_price, :buy, price)).to be_a(BigDecimal).and eq(1.75) }
      it { expect(exchange.send(:rounded_price, :sell, price)).to be_a(BigDecimal).and eq(2) }
    end
  end

  describe '#cancel_order', vcr: { cassette_name: 'itbit/cancel_order' } do
    let(:order) { exchange.orders.find { |ord| ord.id == 'ddc531f0-b35d-4edc-98a3-49f8d50b3792' } }

    subject(:cancelling) { exchange.cancel_order(order) }

    it { is_expected.to be_a(::Itbit::Order) }

    its(:id) { is_expected.to eq('ddc531f0-b35d-4edc-98a3-49f8d50b3792') }
    its(:status) { is_expected.to eq(:cancelling) }
  end

  describe '#transactions', vcr: { cassette_name: 'itbit/transactions' } do
    subject(:transactions) { exchange.transactions }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Transaction)) }

    describe '#transaction_parser' do
      let(:raw_transaction) { exchange.send(:market_accessor).trades.first }

      subject(:transaction) { exchange.send(:transaction_parser, raw_transaction) }

      it { is_expected.to be_a(BitexBot::Exchanges::Transaction) }

      its(:id) { is_expected.to eq('5EUUIUW6FMF1') }
      its(:price) { is_expected.to be_a(BigDecimal).and eq(5_234) }
      its(:amount) { is_expected.to be_a(BigDecimal).and eq(1.9_106) }
      its(:timestamp) { is_expected.to be_a(Integer).and eq(1_554_828_343) }
      its(:raw) { is_expected.to be_a(Hash) }
    end
  end

  describe '#user_transactions' do
    it { expect { exchange.user_transactions }.to raise_error('self subclass responsibility') }
  end

  describe '#amount_and_quantity', vcr: { cassette_name: 'itbit/amount_and_quantity' } do
    subject(:amount_and_quantity) { exchange.amount_and_quantity('b2b09f54-9ea2-48c4-a41f-ee9a92a723d9') }

    # fiat amount
    its([0]) { is_expected.to be_a(BigDecimal).and eq(10.036_761) }
    # crypto amount
    its([1]) { is_expected.to be_a(BigDecimal).and eq(0.0_021) }
  end
end
