require 'spec_helper'

describe BitstampApiWrapper do
  let(:api_wrapper) { described_class }
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitstamp: {
        api_key: 'BITSTAMP_KEY',
        secret: 'BITSTAMP_SECRET',
        client_id: 'BITSTAMP_USERNAME',
        currency_pair: :btcusd
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  describe 'Sends User-Agent header' do
    let(:url) { 'https://www.bitstamp.net/api/v2/balance/btcusd/' }

    it do
      stub_stuff = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

      # we don't care about the response
      api_wrapper.balance rescue nil

      expect(stub_stuff).to have_been_requested
    end
  end

  describe '.currency_pair' do
    subject { api_wrapper.send(:currency_pair) }

    it { is_expected.to be_a(Hash) }
    it { is_expected.to eq({ name: :btcusd, base: :btc, quote: :usd }) }

    it { expect { api_wrapper.currency_pair }.to raise_exception(NoMethodError) }
  end

  describe '.balance', vcr: { cassette_name: 'bitstamp/balance' } do
    subject { api_wrapper.balance }

    it { is_expected.to be_a(ApiWrapper::BalanceSummary) }

    its(:members) { is_expected.to eq(%i[crypto fiat fee]) }

    shared_examples_for 'currency balance' do |currency_type|
      subject { api_wrapper.balance.send(currency_type) }

      it { is_expected.to be_a(ApiWrapper::Balance) }

      its(:members) { is_expected.to eq(%i[total reserved available]) }

      its(:total) { is_expected.to be_a(BigDecimal) }
      its(:reserved) { is_expected.to be_a(BigDecimal) }
      its(:available) { is_expected.to be_a(BigDecimal) }
    end

    it_behaves_like 'currency balance', :crypto
    it_behaves_like 'currency balance', :fiat

    context 'fee' do
      subject { api_wrapper.balance.fee }

      it { is_expected.to be_a(BigDecimal) }
    end
  end

  describe '.order_book', vcr: { cassette_name: 'bitstamp/order_book' } do
    subject { api_wrapper.order_book }

    it { is_expected.to be_a(ApiWrapper::OrderBook) }

    its(:members) { is_expected.to eq(%i[timestamp bids asks]) }

    its(:timestamp) { is_expected.to be_a(Integer) }
    its(:bids) { is_expected.to be_a(Array) }
    its(:asks) { is_expected.to be_a(Array) }

    shared_examples_for :orders do |order_type|
      subject { api_wrapper.order_book.send(order_type).sample }

      it { is_expected.to be_a(ApiWrapper::OrderSummary) }

      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:quantity) { is_expected.to be_a(BigDecimal) }
    end

    it_behaves_like :orders, :bids
    it_behaves_like :orders, :asks
  end

  describe '.send_order' do
    context 'successful buy', vcr: { cassette_name: 'bitstamp/orders/successful_buy' } do
      subject { api_wrapper.send_order(:buy, 1.01, 1) }

      it { is_expected.to be_a(ApiWrapper::Order) }

      its(:members) { is_expected.to eq(%i[id type price amount timestamp raw_order]) }

      its(:id) { is_expected.to be_a(String) }
      its(:type) { is_expected.to be_a(Symbol) }
      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:amount) { is_expected.to be_a(BigDecimal) }
      its(:timestamp) { is_expected.to be_a(Integer) }
      its(:raw_order) { is_expected.to be_a(Bitstamp::Order) }

      context 'raw order' do
        subject { api_wrapper.send_order(:buy, 1.01, 1).raw_order }

        its(:id) { is_expected.to be_a(Integer) }
        its(:type) { is_expected.to be_a(Integer) }
        its(:price) { is_expected.to be_a(String) }
        its(:amount) { is_expected.to be_a(String) }
        its(:datetime) { is_expected.to be_a(String) }
      end
    end

    context 'failure sell', vcr: { cassette_name: 'bitstamp/orders/failure_sell' } do
      subject { api_wrapper.send_order(:sell, 1_000, 1) }

      it { is_expected.to be_nil }
    end
  end

  describe '.transactions', vcr: { cassette_name: 'bitstamp/transactions' } do
    subject { api_wrapper.transactions.sample }

    it { is_expected.to be_a(ApiWrapper::Transaction) }

    its(:members) { is_expected.to eq(%i[id price amount timestamp]) }

    its(:id) { is_expected.to be_a(Integer) }
    its(:price) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:timestamp) { is_expected.to be_a(Integer) }
  end

  describe '.user_transaction', vcr: { cassette_name: 'bitstamp/user_transactions' } do
    subject { api_wrapper.user_transactions.sample }

    it { is_expected.to be_a(ApiWrapper::UserTransaction) }

    its(:members) { is_expected.to eq(%i[order_id fiat crypto crypto_fiat fee type timestamp])  }

    # same user transactions haven't order_id
    its(:order_id) do
      is_expected.to be_a(Integer) if subject.order_id.present?
      is_expected.to be_nil unless subject.order_id.present?
    end

    its(:fiat) { is_expected.to be_a(BigDecimal) }
    its(:crypto) { is_expected.to be_a(BigDecimal) }
    its(:crypto_fiat) { is_expected.to be_a(BigDecimal) }
    its(:fee) { is_expected.to be_a(BigDecimal) }
    its(:type) { is_expected.to be_a(Integer) }
    its(:timestamp) { is_expected.to be_a(Integer) }
  end

  describe '.orders', vcr: { cassette_name: 'bitstamp/orders/all' } do
    subject { api_wrapper.orders.sample }

    it { is_expected.to be_a(ApiWrapper::Order) }

    its(:id) { is_expected.to be_a(String) }
    its(:type) { is_expected.to be_a(Symbol) }
    its(:price) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:timestamp) { is_expected.to be_a(Integer) }
  end

  describe '.find_lost', vcr: { cassette_name: 'bitstamp/orders/all', allow_playback_repeats: true } do
    before(:each) { Timecop.freeze(Time.strptime(order.timestamp.to_s, '%s') - 3.minutes.ago) }

    let(:order) { api_wrapper.orders.sample }

    subject { api_wrapper.find_lost(order.type, order.price, order.amount) }

    it { is_expected.to be_present }
  end

  describe '.cancel', vcr: { cassette_name: 'bitstamp/orders/all' } do
    subject { api_wrapper.orders.sample }

    it { is_expected.to respond_to(:cancel!) }
  end
end
