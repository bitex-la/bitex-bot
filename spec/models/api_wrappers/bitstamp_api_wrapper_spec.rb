require 'spec_helper'

describe BitstampApiWrapper do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      {
        api_key: 'BITSTAMP_API_KEY',
        secret: 'BITSTAMP_API_SECRET',
        client_id: 'BITSTAMP_USERNAME',
        order_book: 'btcusd'
      }
    )
  end

  let(:wrapper) { BitstampApiWrapper.new(taker_settings) }

  describe 'Sends User-Agent header' do
    let(:url) { 'https://www.bitstamp.net/api/v2/balance/btcusd/' }

    it do
      stub_stuff = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

      # we don't care about the response
      wrapper.balance rescue nil

      expect(stub_stuff).to have_been_requested
    end
  end


  it '#currency_pair' do
    expect(wrapper.currency_pair).to eq({ name: 'btcusd', base: 'btc', quote: 'usd'})
  end

  it '#base_quote' do
    expect(wrapper.base_quote).to eq('btc_usd')
  end

  it '#base' do
    expect(wrapper.base).to eq('btc')
  end

  it '#quote' do
    expect(wrapper.quote).to eq('usd')
  end

  describe '#balance', vcr: { cassette_name: 'bitstamp/balance' } do
    subject { wrapper.balance }

    it { is_expected.to be_a(ApiWrapper::BalanceSummary) }

    its(:members) { is_expected.to eq(%i[crypto fiat fee]) }

    shared_examples_for 'currency balance' do |currency_type|
      subject { wrapper.balance.send(currency_type) }

      it { is_expected.to be_a(ApiWrapper::Balance) }

      its(:members) { is_expected.to eq(%i[total reserved available]) }

      its(:total) { is_expected.to be_a(BigDecimal) }
      its(:reserved) { is_expected.to be_a(BigDecimal) }
      its(:available) { is_expected.to be_a(BigDecimal) }
    end

    it_behaves_like 'currency balance', :crypto
    it_behaves_like 'currency balance', :fiat

    it 'fee' do
      expect(wrapper.balance.fee).to be_a(BigDecimal)
    end
  end

  describe '#market', vcr: { cassette_name: 'bitstamp/market' } do
    before(:each) { allow(BitexBot::Robot).to receive(:logger).and_return(logger) }

    let(:logger) { BitexBot::Logger.setup }

    subject(:market) { wrapper.market }

    it { is_expected.to be_a(ApiWrapper::OrderBook) }

    its(:members) { is_expected.to eq(%i[timestamp bids asks]) }

    its(:timestamp) { is_expected.to be_a(Integer) }
    its(:bids) { is_expected.to be_a(Array) }
    its(:asks) { is_expected.to be_a(Array) }

    shared_examples_for :orders do |order_type|
      subject(:sample) { market.send(order_type).sample }

      it { is_expected.to be_a(ApiWrapper::OrderSummary) }

      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:quantity) { is_expected.to be_a(BigDecimal) }
    end

    it_behaves_like :orders, :bids
    it_behaves_like :orders, :asks
  end

  describe '#send_order' do
    context 'successful buy', vcr: { cassette_name: 'bitstamp/orders/successful_buy' } do
      subject { wrapper.send_order(:buy, 1.01, 1) }

      it { is_expected.to be_a(ApiWrapper::Order) }

      its(:members) { is_expected.to eq(%i[id type price amount timestamp raw]) }

      its(:id) { is_expected.to be_a(String) }
      its(:type) { is_expected.to be_a(Symbol) }
      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:amount) { is_expected.to be_a(BigDecimal) }
      its(:timestamp) { is_expected.to be_a(Integer) }
      its(:raw) { is_expected.to be_a(Bitstamp::Order) }

      context 'raw order' do
        subject { wrapper.send_order(:buy, 1.01, 1).raw }

        its(:id) { is_expected.to be_a(Integer) }
        its(:type) { is_expected.to be_a(Integer) }
        its(:price) { is_expected.to be_a(String) }
        its(:amount) { is_expected.to be_a(String) }
        its(:datetime) { is_expected.to be_a(String) }
      end
    end

    context 'failure sell', vcr: { cassette_name: 'bitstamp/orders/failure_sell' } do
      subject { wrapper.send_order(:sell, 1_000, 1) }

      it { is_expected.to be_nil }
    end
  end

  describe '#transactions', vcr: { cassette_name: 'bitstamp/transactions' } do
    subject { wrapper.transactions.sample }

    it { is_expected.to be_a(ApiWrapper::Transaction) }

    its(:members) { is_expected.to eq(%i[id price amount timestamp raw]) }

    its(:id) { is_expected.to be_a(Integer) }
    its(:price) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:timestamp) { is_expected.to be_a(Integer) }
    its(:raw) { is_expected.to be_a(Bitstamp::Transactions) }
  end

  describe '#user_transaction', vcr: { cassette_name: 'bitstamp/user_transactions' } do
    subject { wrapper.user_transactions.sample }

    it { is_expected.to be_a(ApiWrapper::UserTransaction) }

    its(:members) { is_expected.to eq(%i[order_id fiat crypto price fee type timestamp raw])  }

    its(:order_id) { is_expected.to be_a(String) }
    its(:fiat) { is_expected.to be_a(BigDecimal) }
    its(:crypto) { is_expected.to be_a(BigDecimal) }
    its(:price) { is_expected.to be_a(BigDecimal) }
    its(:fee) { is_expected.to be_a(BigDecimal) }
    its(:type) { is_expected.to be_a(Integer) }
    its(:timestamp) { is_expected.to be_a(Integer) }
  end

  describe '#orders', vcr: { cassette_name: 'bitstamp/orders/all' } do
    subject { wrapper.orders.sample }

    it { is_expected.to be_a(ApiWrapper::Order) }

    its(:id) { is_expected.to be_a(String) }
    its(:type) { is_expected.to be_a(Symbol) }
    its(:price) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:timestamp) { is_expected.to be_a(Integer) }
  end

  describe '#find_lost', vcr: { cassette_name: 'bitstamp/orders/all', allow_playback_repeats: true } do
    let(:order) { wrapper.orders.sample }
    let(:threshold) { Time.strptime(order.timestamp.to_s, '%s') - 1.minute.ago }

    subject { wrapper.find_lost(order.type, order.price, order.amount, threshold) }

    it { is_expected.to be_present }
  end

  describe '#cancel', vcr: { cassette_name: 'bitstamp/orders/all' } do
    subject { wrapper.orders.sample }

    it { is_expected.to respond_to(:cancel!) }
  end
end
