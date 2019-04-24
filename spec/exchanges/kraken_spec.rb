require 'spec_helper'

describe BitexBot::Exchanges::Kraken do
  let(:exchange) do
    settings = BitexBot::SettingsClass.new(
      api_key: 'your_api_key',
      api_secret: 'your_api_secret',
      orderbook_code: 'xbtusd'
    )

    described_class.new(settings)
  end

  describe 'Sends User-Agent header' do
    let(:url) { 'https://api.kraken.com/0/public/AssetPairs' }

    it do
      stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

      # We don't care about the response
      exchange.market rescue nil

      expect(stub_stuff).to have_been_requested
    end
  end

  describe '#asset_pairs', vcr: { cassette_name: 'kraken/asset_pairs' } do
    describe '#currency_pair' do
      subject(:currency_pair) { exchange.send(:currency_pair) }

      it { is_expected.to be_a(Hashie::Mash) }

      its(:altname) { is_expected.to eq('XBTUSD') }
      its(:base) { is_expected.to eq('XXBT') }
      its(:quote) { is_expected.to eq('ZUSD') }
      its(:code) { is_expected.to eq('XXBTZUSD') }
    end

    describe '#base' do
      subject(:base) { exchange.base }

      it { is_expected.to eq('XXBT') }
    end

    describe '#quote' do
      subject(:quote) { exchange.quote }

      it { is_expected.to eq('ZUSD') }
    end

    describe '#base_quote' do
      subject(:base_quote) { exchange.base_quote }

      it { is_expected.to eq('XXBT_ZUSD') }
    end
  end

  describe '#balance', vcr: { cassette_name: 'kraken/balance' } do
    subject(:balance) { exchange.balance }

    it { is_expected.to be_a(BitexBot::Exchanges::BalanceSummary) }

    describe '#balance_summary_parser' do
      subject(:raw_balance) { exchange.send(:balance_summary_parser, exchange.client.private.balance) }

      it { is_expected.to be_a(BitexBot::Exchanges::BalanceSummary) }

      its(:crypto) { is_expected.to be_a(BitexBot::Exchanges::Balance)  }
      its(:fiat) { is_expected.to be_a(BitexBot::Exchanges::Balance)  }
      its(:fee) { is_expected.to be_a(BigDecimal).and eq(0.26) }

      describe '#balance_parser' do
        subject(:balance) { exchange.send(:balance_parser, 500.to_d, 200.to_d) }

        it { is_expected.to be_a(BitexBot::Exchanges::Balance) }

        its(:total) { is_expected.to be_a(BigDecimal).and eq(500) }
        its(:reserved) { is_expected.to be_a(BigDecimal).and eq(200) }
        its(:available) { is_expected.to be_a(BigDecimal).and eq(300) }
      end
    end
  end

  describe '#market', vcr: { cassette_name: 'kraken/market' } do
    subject(:market) { exchange.market }

    it { is_expected.to be_a(BitexBot::Exchanges::Orderbook) }

    describe '#orderbook_parser' do
      let(:raw_orderbook) { exchange.client.public.order_book(:XBTUSD)[:XXBTZUSD] }

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

          its(:price) { is_expected.to be_a(BigDecimal).and eq(5_212.6) }
          its(:amount) { is_expected.to be_a(BigDecimal).and eq(6.3) }
        end
      end
    end
  end

  describe '#orders', vcr: { cassette_name: 'kraken/orders' } do
    subject(:orders) { exchange.orders }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Order)) }

    context 'with raw order' do
      let(:raw) { exchange.client.private.open_orders[:open].first }
      let(:raw_data) { raw[1] }

      describe '#order_parser' do
        subject(:order) { exchange.send(:order_parser, *raw) }

        it { is_expected.to be_a(BitexBot::Exchanges::Order) }

        its(:id) { is_expected.to eq('OVNC2C-IVCXL-DM4QSE') }
        its(:type) { is_expected.to eq(:ask) }
        its(:price) { is_expected.to be_a(BigDecimal).and eq(20_000) }
        its(:amount) { is_expected.to be_a(BigDecimal).and eq(0.005) }
        its(:timestamp) { is_expected.to be_a(Integer).and eq(1_555_503_140) }
        its(:status) { is_expected.to eq(:executing) }
        its(:raw) { is_expected.to be_a(Hashie::Mash) }
      end

      describe '#order_statuses' do
        subject(:statuses) { exchange.send(:order_statuses) }

        it { is_expected.to eq('open' => :executing, 'closed' => :completed, 'cancelled' => :cancelled) }
      end

      describe '#order_types' do
        subject(:order_types) { exchange.send(:order_types) }

        it { is_expected.to eq('sell' => :ask, 'buy' => :bid) }
      end
    end
  end

  describe '#enough_order_size?' do
    it { expect(described_class::MIN_AMOUNT).to be_a(BigDecimal).and eq(0.002) }

    context 'enough' do
      it { expect(exchange.enough_order_size?(0.002, 1, nil)).to be_truthy }
    end

    context 'not enough' do
      it { expect(exchange.enough_order_size?(0.0_019, 1, nil)).to be_falsey }
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

        it { expect { subject }.to raise_error(BitexBot::Exchanges::OrderNotFound, 'Not found buy order for XXBT 2 @ ZUSD 3500.') }
      end
    end
  end

  describe '#send_order', vcr: { cassette_name: 'kraken/send_order' } do
    subject(:order) { exchange.send(:send_order, :sell, 30_000, 0.005) }

    it { is_expected.to be_a(BitexBot::Exchanges::Order) }

    its(:id) { is_expected.to be_present }
    its(:type) { is_expected.to eq(:ask) }
    its(:price) { is_expected.to eq(30_000) }
    its(:amount) { is_expected.to eq(0.005) }
    its(:timestamp) { is_expected.to be_present }
    its(:status) { is_expected.to eq(:executing) }
    its(:raw) { is_expected.to be_a(Hash) }
  end

  describe '#find_lost' do
    context 'as open order', vcr: { cassette_name: 'kraken/find_lost/open_orders' } do
      subject(:lost) { exchange.send(:find_lost, :buy, 1_000.to_d, 0.005.to_d, threshold) }

      let(:threshold) { Time.parse('2019-04-17 19:56:28 UTC') }

      it { is_expected.to be_a(BitexBot::Exchanges::Order) }

      its(:type) { is_expected.to eq(:bid) }
      its(:price) { is_expected.to eq(1_000) }
      its(:amount) { is_expected.to eq(0.005) }
      its(:timestamp) { is_expected.to be >= threshold.to_i }
    end

    context 'as executed order', vcr: { cassette_name: 'kraken/find_lost/finished_orders' } do
      subject(:lost) { exchange.send(:find_lost, :sell, 5_220.to_d, 0.01.to_d, threshold) }

      let(:threshold) { Time.parse('2019-04-17 18:56:19 UTC') }

      it { is_expected.to be_a(BitexBot::Exchanges::Order) }

      its(:type) { is_expected.to eq(:ask) }
      its(:price) { is_expected.to eq(5_220) }
      its(:amount) { is_expected.to eq(0.01) }
      its(:timestamp) { is_expected.to be >= threshold.to_i }
    end
  end

  describe '#cancel_order', vcr: { cassette_name: 'kraken/cancel_order' } do
    let(:order) { exchange.orders.find { |ord| ord.id == 'OKDVAY-2YDZ7-CT53PG' } }

    subject(:cancelled) { exchange.cancel_order(order) }

    it { is_expected.to be_a(Hash) }

    its(:count) { is_expected.to eq(1) }
  end

  describe '#transactions', vcr: { cassette_name: 'kraken/transactions' } do
    subject(:transactions) { exchange.transactions }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Transaction)) }

    describe '#transaction_parser' do
      let(:raw_transaction) { exchange.client.public.trades('XBTUSD')['XXBTZUSD'].first }

      subject(:transaction) { exchange.send(:transaction_parser, raw_transaction) }

      it { is_expected.to be_a(BitexBot::Exchanges::Transaction) }

      its(:id) { is_expected.to eq('1555927188') }
      its(:price) { is_expected.to be_a(BigDecimal).and eq(5_300.8) }
      its(:amount) { is_expected.to be_a(BigDecimal).and eq(0.0_520_304) }
      its(:timestamp) { is_expected.to be_a(Integer).and eq(1_555_927_188) }
      its(:raw) { is_expected.to be_a(Array) }
    end
  end

  describe '#user_transactions' do
    it { expect { exchange.user_transactions }.to raise_error('self subclass responsibility') }
  end

  describe '#amount_and_quantity', vcr: { cassette_name: 'kraken/amount_and_quantity' } do
    subject(:amount_and_quantity) { exchange.amount_and_quantity('OE35BB-5R5Z5-H3A342') }

    # fiat amount
    its([0]) { is_expected.to be_a(BigDecimal).and eq(26.5_385) }
    # crypto amount
    its([1]) { is_expected.to be_a(BigDecimal).and eq(0.005) }
  end
end
