require 'spec_helper'

describe BitexBot::Exchanges::Bitex do
  let(:exchange) do
    settings = BitexBot::SettingsClass.new(
      api_key: 'your_magic_api_key',
      sandbox: true,
      orderbook_code: 'btc_usd',
      trading_fee: 0.05
    )

    described_class.new(settings)
  end

  describe '#asset_pairs' do
    describe '#currency_pair' do
      subject(:currency_pair) { exchange.currency_pair }

      it { is_expected.to be_a(Hashie::Mash) }

      its(:base) { is_expected.to eq(:btc) }
      its(:quote) { is_expected.to eq(:usd) }
      its(:code) { is_expected.to eq(:btc_usd) }
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

  describe '#balance', vcr: { cassette_name: 'bitex/balance' } do
    subject(:balance) { exchange.balance }

    it { is_expected.to be_a(BitexBot::Exchanges::BalanceSummary) }

    describe '#balance_parser' do
      subject(:balance) { exchange.send(:balance_parser, exchange.client.coin_wallets.find(:btc)) }

      it { is_expected.to be_a(BitexBot::Exchanges::Balance) }

      its(:total) { is_expected.to be_a(BigDecimal).and eq(23.10_785_424) }
      its(:reserved) { is_expected.to be_a(BigDecimal).and eq(0.02_443_267) }
      its(:available) { is_expected.to be_a(BigDecimal).and eq(23.08_342_157) }
    end
  end

  context '#market', vcr: { cassette_name: 'bitex/market' } do
    subject(:market) { exchange.market }

    it { is_expected.to be_a(BitexBot::Exchanges::Orderbook) }

    its(:timestamp) { is_expected.to be_a(Integer) }
    its(:asks) { is_expected.to all(be_a(BitexBot::Exchanges::OrderSummary)) }
    its(:bids) { is_expected.to all(be_a(BitexBot::Exchanges::OrderSummary)) }

    describe '#order_summary_parser' do
      let(:raw_orders) do
        exchange.client.markets.find(
          exchange.client.orderbooks.find_by_code(:btc_usd),
          includes: %i[asks bids]
        ).asks
      end

      subject(:order_summaries) { exchange.send(:order_summary_parser, raw_orders) }

      it { is_expected.to all(be_a(BitexBot::Exchanges::OrderSummary)) }

      context 'taking a sample' do
        subject(:order_summary) { order_summaries.first }

        its(:price) { is_expected.to be_a(BigDecimal).and eq(4400) }
        its(:amount) { is_expected.to be_a(BigDecimal).and eq(20) }
      end
    end
  end

  context '#orders', vcr: { cassette_name: 'bitex/orders' } do
    subject(:orders) { exchange.orders }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Order)) }

    context 'with raw order' do
      let(:raw_order) { exchange.client.orders.all.first }

      describe '#order_parser' do
        subject(:order) { exchange.send(:order_parser, raw_order) }

        it { is_expected.to be_a(BitexBot::Exchanges::Order) }

        its(:id) { is_expected.to eq('4253') }
        its(:type) { is_expected.to eq(:bid) }
        its(:price) { is_expected.to be_a(BigDecimal).and eq(4_050) }
        its(:amount) { is_expected.to be_a(BigDecimal).and eq(12_000) }
        its(:timestamp) { is_expected.to be_a(Integer).and eq(1_549_287_937) }
        its(:status) { is_expected.to eq(:executing) }
        its(:raw) { is_expected.to be_a(Bitex::Resources::Orders::Order) }
      end

      describe '#order_types' do
        subject(:order_types) { exchange.send(:order_types) }

        it { is_expected.to eq('asks' => :ask, 'bids' => :bid) }
      end
    end
  end

  describe '#enough_order_size?' do
    subject(:enough?) { exchange.enough_order_size?(amount, :dont_care, trate_type) }

    describe '#enough_sell_size?' do
      it { expect(described_class::MIN_ASK_AMOUNT).to be_a(BigDecimal).and eq(0.0_001) }

      context 'enough' do
        it { expect(exchange.enough_order_size?(0.0_001, :dont_care, :sell)).to be_truthy }
        it { expect(exchange.send(:enough_sell_size?, 0.0_001)).to be_truthy }
      end

      context 'not enough' do
        it { expect(exchange.enough_order_size?(0.00_009, :dont_care, :sell)).to be_falsey }
        it { expect(exchange.send(:enough_sell_size?, 0.00_009)).to be_falsey }
      end
    end

    describe '#enough_buy_size?' do
      it { expect(described_class::MIN_BID_AMOUNT).to be_a(BigDecimal).and eq(0.1) }

      context 'enough' do
        it { expect(exchange.enough_order_size?(0.1, :dont_care, :buy)).to be_truthy }
        it { expect(exchange.send(:enough_buy_size?, 0.1)).to be_truthy }
      end

      context 'not enough' do
        it { expect(exchange.enough_order_size?(0.09, :dont_care, :buy)).to be_falsey }
        it { expect(exchange.send(:enough_buy_size?, 0.09)).to be_falsey }
      end
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

        it { expect { subject }.to raise_error(BitexBot::Exchanges::OrderNotFound, 'Buy order for BTC 2 @ USD 3500.') }
      end
    end
  end

  describe '#send_order', vcr: { cassette_name: 'bitex/send_order' } do
    subject(:order) { exchange.send(:send_order, :buy, 3_500, 2) }

    it { is_expected.to be_a(BitexBot::Exchanges::Order) }

    its(:id) { is_expected.to be_present }
    its(:type) { is_expected.to eq(:bid) }
    its(:price) { is_expected.to eq(3_500) }
    its(:amount) { is_expected.to eq(2) }
    its(:timestamp) { is_expected.to be_present }
    its(:raw) { is_expected.to be_a(Bitex::Resources::Orders::Bid) }
  end

  describe '#find_lost' do
    subject(:lost) { exchange.send(:find_lost, :buy, 4300.to_d, 2.to_d, threshold) }

    let(:threshold) { Time.parse('2019-04-15 16:12:40 UTC') }

    shared_examples_for 'Found' do
      it { is_expected.to be_a(BitexBot::Exchanges::Order) }

      its(:type) { is_expected.to eq(:bid) }
      its(:price) { is_expected.to eq(4_300) }
      its(:amount) { is_expected.to eq(2) }
      its(:timestamp) { is_expected.to be >= threshold.to_i }
    end

    context 'is open order', vcr: { cassette_name: 'bitex/find_lost/open_orders' } do
      it_behaves_like 'Found'
    end

    context 'as executed order', vcr: { cassette_name: 'bitex/find_lost/finished_orders' } do
      it_behaves_like 'Found'
    end
  end

  describe '#cancel_order', vcr: { cassette_name: 'bitex/cancel_order' } do
    let(:order) { exchange.orders.find { |ord| ord.id == '5036' } }

    subject { exchange.cancel_order(order) }

    it { is_expected.to be_a(Array).and be_empty }
  end

  describe '#transactions', vcr: { cassette_name: 'bitex/transactions' }do
    subject(:transactions) { exchange.transactions }

    it { is_expected.to all(be_a(BitexBot::Exchanges::Transaction)) }

    describe '#transaction_parser' do
      let(:raw_trade) do
        exchange
          .client
          .transactions
          .all(orderbook: exchange.client.orderbooks.find_by_code(:btc_usd))
          .first
      end

      subject(:trade) { exchange.send(:transaction_parser, raw_trade) }

      it { is_expected.to be_a(BitexBot::Exchanges::Transaction) }

      its(:id) { is_expected.to eq('2068') }
      its(:price) { is_expected.to be_a(BigDecimal).and eq(4_400) }
      its(:amount) { is_expected.to be_a(BigDecimal).and eq(1) }
      its(:timestamp) { is_expected.to be_a(Integer).and eq(1_555_353_198) }
      its(:raw) { is_expected.to be_a(::Bitex::Resources::Transaction) }
    end
  end

  describe '#user_transactions', vcr: { cassette_name: 'bitex/user_transactions' } do
    subject(:trades) { exchange.user_transactions }

    it { is_expected.to all(be_a(BitexBot::Exchanges::UserTransaction)) }

    describe '#user_transaction_parser' do
      let(:raw_trade) do
        exchange
          .client
          .trades
          .all(orderbook: exchange.client.orderbooks.find_by_code(:btc_usd), days: 30)
          .first
      end

      subject(:trade) { exchange.send(:user_transaction_parser, raw_trade) }

      it { is_expected.to be_a(BitexBot::Exchanges::UserTransaction) }

      its(:order_id) { is_expected.to eq('5037') }
      its(:fiat) { is_expected.to be_a(BigDecimal).and eq(4_400) }
      its(:crypto) { is_expected.to be_a(BigDecimal).and eq(0.9_975.to_d) }
      its(:price) { is_expected.to be_a(BigDecimal).and eq(4_400) }
      its(:fee) { is_expected.to be_a(BigDecimal).and eq(0.0_025) }
      its(:type) { is_expected.to eq(:buy) }
      its(:timestamp) { is_expected.to be_a(Integer).and eq(1_555_353_198) }
      its(:raw) { is_expected.to be_a(::Bitex::Resources::Trades::Trade) }

      describe '#order_id' do
        subject { exchange.send(:order_id, raw_trade) }

        it { is_expected.to eq('5037') }
      end

      describe '#order_types' do
        subject(:trade_types) { exchange.send(:trade_types) }

        it { is_expected.to eq('sells' => :sell, 'buys' => :buy) }
      end
    end
  end

  describe '#amount_and_quantity', vcr: { cassette_name: 'bitex/user_transactions' } do
    subject(:amount_and_quantity) { exchange.amount_and_quantity('5037') }

    # fiat amount
    its([0]) { is_expected.to be_a(BigDecimal).and eq(4_400) }

    # crypto quantity
    its([1]) { is_expected.to be_a(BigDecimal).and eq(0.9975.to_d) }
  end

  context '#trades', vcr: { cassette_name: 'bitex/trades' } do
    subject(:trades) { exchange.trades }

    it { is_expected.to all(be_a(BitexBot::Exchanges::UserTransaction)) }
  end
end
