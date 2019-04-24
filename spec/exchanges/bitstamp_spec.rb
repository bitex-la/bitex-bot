require 'spec_helper'

describe BitexBot::Exchanges::Bitstamp do
  let(:exchange) do
    settings = BitexBot::SettingsClass.new(
      api_key: 'apikey',
      secret: 'secret',
      client_id: '99999',
      orderbook_code: 'btcusd'
    )

    described_class.new(settings)
  end

  describe 'Sends User-Agent header' do
    let(:url) { 'https://www.bitstamp.net/api/v2/order_book/btcusd/' }

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

      its(:base) { is_expected.to eq('btc') }
      its(:quote) { is_expected.to eq('usd') }
      its(:code) { is_expected.to eq('btcusd') }
    end

    describe '#base' do
      subject(:base) { exchange.base }

      it { is_expected.to eq('BTC') }
    end

    describe '#quote' do
      subject(:quote) { exchange.quote }

      it { is_expected.to eq('USD') }
    end

    describe '#base_quote' do
      subject(:base_quote) { exchange.base_quote }

      it { is_expected.to eq('BTC_USD') }
    end
  end

  describe '#balance', vcr: { cassette_name: 'bitstamp/balance' } do
    subject(:balance) { exchange.balance }

    it { is_expected.to be_a(BitexBot::Exchanges::BalanceSummary) }

    describe '#balance_summary_parser' do
      subject(:summary) { exchange.send(:balance_summary_parser, ::Bitstamp.balance(:btcusd).symbolize_keys) }

      it { is_expected.to be_a(BitexBot::Exchanges::BalanceSummary) }

      its(:crypto) { is_expected.to be_a(BitexBot::Exchanges::Balance)  }
      its(:fiat) { is_expected.to be_a(BitexBot::Exchanges::Balance)  }
      its(:fee) { is_expected.to be_a(BigDecimal).and eq(0.25) }
    end

    describe '#balance_parser' do
      subject(:balance) { exchange.send(:balance_parser, ::Bitstamp.balance(:btcusd).symbolize_keys, :usd) }

      it { is_expected.to be_a(BitexBot::Exchanges::Balance) }

      its(:total) { is_expected.to be_a(BigDecimal).and eq(2.07) }
      its(:reserved) { is_expected.to be_a(BigDecimal).and eq(0) }
      its(:available) { is_expected.to be_a(BigDecimal).and eq(2.07) }
    end
  end

  describe '#market', vcr: { cassette_name: 'bitstamp/market' } do
    subject(:market) { exchange.market }

    it { is_expected.to be_a(BitexBot::Exchanges::Orderbook) }

    describe '#orderbook_parser' do
      let(:raw_orderbook) { ::Bitstamp.order_book(:btcusd).deep_symbolize_keys }

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

          its(:price) { is_expected.to be_a(BigDecimal).and eq(5281.39) }
          its(:amount) { is_expected.to be_a(BigDecimal).and eq(0.03) }
        end
      end
    end
  end

  describe '#orders', vcr: { cassette_name: 'bitstamp/orders' } do
    subject(:orders) { exchange.orders }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Order)) }

    context 'with raw order' do
      let(:raw_order) { ::Bitstamp.orders.all(currency_pair: :btcusd).first }

      describe '#order_parser' do
        subject(:order) { exchange.send(:order_parser, raw_order) }

        it { is_expected.to be_a(BitexBot::Exchanges::Order) }

        its(:id) { is_expected.to eq('3112295973') }
        its(:type) { is_expected.to eq(:bid) }
        its(:price) { is_expected.to be_a(BigDecimal).and eq(10) }
        its(:amount) { is_expected.to be_a(BigDecimal).and eq(1) }
        its(:timestamp) { is_expected.to be_a(Integer).and eq(1_554_915_555) }
        its(:status) { is_expected.to eq(:executing) }
        its(:raw) { is_expected.to be_a(::Bitstamp::Order) }
      end

      describe '#order_types' do
        subject(:order_types) { exchange.send(:order_types) }

        it { is_expected.to eq('0' => :bid, '1' => :ask, buy: :bid, sell: :ask) }
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

        it { expect { subject }.to raise_error(BitexBot::Exchanges::OrderNotFound, 'Not found buy order for BTC 2 @ USD 3500.') }
      end
    end
  end

  describe '#send_order' do
    context 'successful', vcr: { cassette_name: 'bitstamp/send_order/successful' } do
      subject(:order) { exchange.send(:send_order, :buy, 10, 1) }

      it { is_expected.to be_a(BitexBot::Exchanges::Order) }

      its(:id) { is_expected.to be_present }
      its(:type) { is_expected.to eq(:bid) }
      its(:price) { is_expected.to eq(10) }
      its(:amount) { is_expected.to eq(1) }
      its(:timestamp) { is_expected.to be_present }
      its(:raw) { is_expected.to be_a(::Bitstamp::Order) }
    end

    context 'wrong', vcr: { cassette_name: 'bitstamp/send_order/wrong' } do

      it do
        expect { exchange.send(:send_order, :buy, 1000, 0.004) }
          .to raise_error(BitexBot::Exchanges::OrderError, 'Minimum order size is 5.0 USD.')
      end
    end
  end

  describe '#find_lost' do
    context 'in open orders', vcr: { cassette_name: 'bitstamp/find_lost/open_orders' } do
      subject(:lost) { exchange.send(:find_lost, :buy, 10.to_d, 1.to_d, threshold) }

      let(:threshold) { Time.parse('2019-04-10 18:26:54 UTC') }

      it { is_expected.to be_a(BitexBot::Exchanges::Order) }

      its(:type) { is_expected.to eq(:bid) }
      its(:price) { is_expected.to eq(10) }
      its(:amount) { is_expected.to eq(1) }
      its(:timestamp) { is_expected.to be >= threshold.to_i }
    end

    context 'as executed order', vcr: { cassette_name: 'bitstamp/find_lost/finished_orders' } do
      subject(:lost) { exchange.send(:find_lost, :sell, 5078.5.to_d, 0.001.to_d, threshold) }

      let(:threshold) { Time.parse('2019-04-12 19:11:09 UTC') }

      it { is_expected.to be_a(BitexBot::Exchanges::Order) }

      its(:type) { is_expected.to eq(:ask) }
      its(:price) { is_expected.to eq(5078.5) }
      its(:amount) { is_expected.to eq(0.001) }
      its(:timestamp) { is_expected.to be >= threshold.to_i }
    end
  end

  describe '#cancel_order', vcr: { cassette_name: 'bitstamp/cancel_order' } do
    let(:order) { exchange.orders.find { |ord| ord.id == '3112295973' } }

    subject(:cancelling) { exchange.cancel_order(order) }

    it { is_expected.to be_a(Hash) }

    its([:id]) { is_expected.to be_a(Integer).and eq(3_112_295_973) }
  end

  describe '#transactions', vcr: { cassette_name: 'bitstamp/transactions' } do
    subject(:trades) { exchange.transactions }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Transaction)) }

    describe '#transaction_parser' do
      let(:raw_trade) { ::Bitstamp.transactions(:btcusd).first }

      subject(:trade) { exchange.send(:transaction_parser, raw_trade) }

      it { is_expected.to be_a(BitexBot::Exchanges::Transaction) }

      its(:id) { is_expected.to eq('85463441') }
      its(:price) { is_expected.to be_a(BigDecimal).and eq(5_273.58) }
      its(:amount) { is_expected.to be_a(BigDecimal).and eq(0.02_457_942) }
      its(:timestamp) { is_expected.to be_a(Integer).and eq(1_554_914_979) }
      its(:raw) { is_expected.to be_a(::Bitstamp::Transactions) }
    end
  end

  describe '#user_transactions', vcr: { cassette_name: 'bitstamp/user_transactions' } do
    subject(:trades) { exchange.user_transactions }

    it { is_expected.to all(be_a(BitexBot::Exchanges::UserTransaction)) }

    describe '#user_transaction_parser' do
      let(:raw_trade) { ::Bitstamp.user_transactions.all(currency_pair: :btcusd).first }

      subject(:trade) { exchange.send(:user_transaction_parser, raw_trade) }

      it { is_expected.to be_a(BitexBot::Exchanges::UserTransaction) }

      its(:order_id) { is_expected.to eq('3112292663') }
      its(:fiat) { is_expected.to be_a(BigDecimal).and eq(23.72) }
      its(:crypto) { is_expected.to be_a(BigDecimal).and eq(-0.0_045) }
      its(:price) { is_expected.to be_a(BigDecimal).and eq(5_271.2) }
      its(:fee) { is_expected.to be_a(BigDecimal).and eq(0.06) }
      its(:type) { is_expected.to eq(:undefined) }
      its(:timestamp) { is_expected.to be_a(Integer).and eq(1_554_926_257) }
      its(:raw) { is_expected.to be_a(::Bitstamp::UserTransaction) }
    end
  end

  describe '#amount_and_quantity', vcr: { cassette_name: 'bitstamp/user_transactions' } do
    subject(:amount_and_quantity) { exchange.amount_and_quantity('3112292663') }

    # fiat amount
    its([0]) { is_expected.to be_a(BigDecimal).and eq(23.72) }
    # crypto amount
    its([1]) { is_expected.to be_a(BigDecimal).and eq(0.0_045) }
  end
end
