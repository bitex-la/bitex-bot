require 'spec_helper'

describe BitexApiWrapper do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      {
        api_key: 'your_magic_api_key',
        sandbox: true,
        order_book: 'btc_usd',
        trading_fee: 0
      }
    )
  end

  let(:wrapper) { BitexApiWrapper.new(taker_settings) }

=begin
  #TODO
  it 'Sends User-Agent header' do
    url = "https://bitex.la/api-v1/rest/private/profile?api_key=#{BitexBot::Robot.taker.api_key}"
    stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    wrapper.balance rescue nil

    expect(stub_stuff).to have_been_requested
  end
=end

  it '#base_quote' do
    expect(wrapper.base_quote).to eq('btc_usd')
  end

  it '#base' do
    expect(wrapper.base).to eq('btc')
  end

  it '#quote' do
    expect(wrapper.quote).to eq('usd')
  end

  context '#balance' do
    subject(:balance) { wrapper.balance }

    before(:each) do
      allow_any_instance_of(BitexApiWrapper).to receive(:cash_wallet).and_return(coin_wallet)
      allow_any_instance_of(BitexApiWrapper).to receive(:coin_wallet).and_return(cash_wallet)
    end

    let(:coin_wallet) { double(type: 'cash_wallets', id: 'usd', balance: 500.to_d, available: 300.to_d, currency: 'usd') }
    let(:cash_wallet) { double(type: 'coin_wallets', id: 'btc', balance: 50.to_d, available: 30.to_d, currency: 'btc') }

    it { is_expected.to be_a(ApiWrapper::BalanceSummary) }

    its(:crypto) { is_expected.to be_a(ApiWrapper::Balance) }
    its(:fiat) { is_expected.to be_a(ApiWrapper::Balance) }
    its(:fee) { is_expected.to be_a(BigDecimal) }

    context 'about crypto balance' do
      subject(:crypto) { balance.crypto }

      its(:total) { is_expected.to be_a(BigDecimal) }
      its(:reserved) { is_expected.to be_a(BigDecimal) }
      its(:available) { is_expected.to be_a(BigDecimal) }
    end

    context 'about fiat balance' do
      subject(:fiat) { balance.crypto }

      its(:total) { is_expected.to be_a(BigDecimal) }
      its(:reserved) { is_expected.to be_a(BigDecimal) }
      its(:available) { is_expected.to be_a(BigDecimal) }
    end
  end

  context '#market', vcr: { cassette_name: 'bitex/market' } do
    subject(:market) { wrapper.market }

    it { is_expected.to be_a(ApiWrapper::OrderBook) }

    its(:bids) { is_expected.to all(be_a(ApiWrapper::OrderSummary)) }
    its(:asks) { is_expected.to all(be_a(ApiWrapper::OrderSummary)) }
    its(:timestamp) { is_expected.to be_a(Integer) }

    context 'about bids' do
      subject(:bids) { market.bids.sample }

      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:quantity) { is_expected.to be_a(BigDecimal) }
    end

    context 'about asks' do
      subject(:asks) { market.asks.sample }

      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:quantity) { is_expected.to be_a(BigDecimal) }
    end
  end

  context '#orders', vcr: { cassette_name: 'bitex/orders/all' } do
    subject(:orders) { wrapper.orders }

    it { is_expected.to all(be_a(BitexApiWrapper::Order)) }

    it 'orders belong to setuped orderbook' do
      expect(orders.map(&:orderbook_code)).to all(eq(taker_settings.order_book))
    end

    context 'about sample' do
      subject(:sample) { orders.sample }

      its(:id) { is_expected.to be_a(String) }
      its(:type) { is_expected.to be_a(Symbol) }
      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:amount) { is_expected.to be_a(BigDecimal) }
      its(:timestamp) { is_expected.to be_a(Integer) }
    end
  end

  context '#cancel_order', vcr: { cassette_name: 'bitex/orders/cancel' } do
    subject { wrapper.cancel_order(order) }

    let(:order) { wrapper.send(:order_parser, client_ask_order) }
    let(:client_ask_order) do
      double(
        type: 'asks', id: order_id, amount: '4000', remaining_amount: '4', price: '5000', status: 'executing',
        orderbook_code: 'btc_usd', created_at: '2019-01-16T19:45:37.160Z'
      )
    end

    let(:order_id) { '1593' }

    it { is_expected.to be_empty }

    context 'searching for cancelling ask order', vcr: { cassette_name: 'bitex/orders/cancelled_not_found' } do
      subject(:not_found) { wrapper.orders.find { |order| order.id == order_id } }

      it { is_expected.to be_nil }
    end
  end

=begin
  context '#place_order' do
    it 'raises OrderNotFound error on Bitex errors' do
      Bitex::Bid.stub(create!: nil)
      Bitex::Ask.stub(create!: nil)
      wrapper.stub(find_lost: nil)

      expect { wrapper.place_order(:buy, 10, 100) }.to raise_exception(OrderNotFound)
      expect { wrapper.place_order(:sell, 10, 100) }.to raise_exception(OrderNotFound)
    end
  end
=end

  context '#transactions', vcr: { cassette_name: 'bitex/transactions' }do
    subject(:transactions) { wrapper.transactions }

    it { is_expected.to all(be_a(ApiWrapper::Transaction)) }

    context 'about sample' do
      subject(:sample) { transactions.sample }

      its(:id) { is_expected.to be_a(Integer) }
      its(:price) { is_expected.to be_a(BigDecimal) }
      its(:amount) { is_expected.to be_a(BigDecimal) }
      its(:timestamp) { is_expected.to be_a(Integer) }
    end
  end

=begin
  it '#user_transaction' do
    stub_bitex_trades

    wrapper.user_transactions.should be_a(Array)
    wrapper.user_transactions.all? { |o| o.should be_a(ApiWrapper::UserTransaction) }

    user_transaction = wrapper.user_transactions.sample
    user_transaction.order_id.should be_a(Integer)
    user_transaction.fiat.should be_a(BigDecimal)
    user_transaction.crypto.should be_a(BigDecimal)
    user_transaction.crypto_fiat.should be_a(BigDecimal)
    user_transaction.fee.should be_a(BigDecimal)
    user_transaction.type.should be_a(Integer)
    user_transaction.timestamp.should be_a(Integer)
  end

  it '#find_lost' do
    stub_bitex_orders

    wrapper.orders.all? { |o| wrapper.find_lost(o.type, o.price, o.amount).present? }
  end
=end
end
