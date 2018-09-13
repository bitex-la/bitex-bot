require 'spec_helper'

describe BitstampApiWrapper do
  let(:api_wrapper) { described_class }
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitstamp: {
        api_key: 'YOUR_API_KEY',
        secret: 'YOUR_API_SECRET',
        client_id: 'YOUR_BITSTAMP_USERNAME',
        currency_pair: :btcusd
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  it 'has configured currency pair' do
    expect { api_wrapper.currency_pair }.to raise_exception(NoMethodError)

    api_wrapper.send(:currency_pair).should be_a(Hash)
    api_wrapper.send(:currency_pair).should eq ({ name: :btcusd, base: :btc, quote: :usd })
  end

  it 'Sends User-Agent header' do
    url = "https://www.bitstamp.net/api/v2/balance/#{api_wrapper.send(:currency_pair)[:name]}/"
    stub_stuff = stub_request(:post, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # we don't care about the response
    api_wrapper.balance rescue nil

    expect(stub_stuff).to have_been_requested
  end

  def stub_balance(balance:, reserved:, available:, fee:)
    Bitstamp.stub(:balance).with(an_instance_of(Symbol)) do
      {
        'btc_balance' => balance.to_s,
        'btc_reserved' => reserved.to_s,
        'btc_available' => available.to_s,
        'bch_balance' => (balance * 2).to_s,
        'bch_reserved' => (reserved * 2).to_s,
        'bch_available' => (available *2).to_s,
        'usd_balance' => balance.to_s,
        'usd_reserved' => reserved.to_s,
        'usd_available' => available.to_s,
        'fee' => fee.to_s
      }
    end
  end

  context '#balance' do
    before(:each) do
      stub_balance(balance: total, reserved: reserved, available: available, fee: fee)
    end

    let(:total) { Faker::Number.between(100, 1_000.to_d) }
    let(:reserved) { Faker::Number.between(100, 1_000).to_d }
    let(:available) { Faker::Number.between(100, 1_000).to_d }
    let(:fee) { Faker::Number.between(1, 50).to_d }

    shared_examples_for 'balances' do
      it 'has expected structure' do
        balance = api_wrapper.balance
        balance.should be_a(ApiWrapper::BalanceSummary)
        balance.crypto.should be_a(ApiWrapper::Balance)
        balance.fiat.should be_a(ApiWrapper::Balance)

        crypto = balance.crypto
        crypto.total.should be_a(BigDecimal)
        crypto.reserved.should be_a(BigDecimal)
        crypto.available.should be_a(BigDecimal)

        fiat = balance.fiat
        fiat.total.should be_a(BigDecimal)
        fiat.total.should eq total
        fiat.reserved.should be_a(BigDecimal)
        fiat.reserved.should eq reserved
        fiat.available.should be_a(BigDecimal)
        fiat.available.should eq available

        balance.fee.should be_a(BigDecimal)
        balance.fee.should eq fee
      end
    end

    context 'with btcusd' do
      before(:each) do
        api_wrapper.send(:currency_pair)[:name] = :btcusd
        api_wrapper.send(:currency_pair)[:base] = :btc
        api_wrapper.send(:currency_pair)[:quote] = :usd
      end

      it_behaves_like 'balances'

      it 'has the data belonging to its currency pair' do
        api_wrapper.balance.crypto do |currency|
          currency.total.should eq total
          currency.reserved.should eq reserved
          currency.available.should eq available
        end
      end
    end

    context 'with bchusd' do
      before(:each) do
        api_wrapper.send(:currency_pair)[:name] = :bchusd
        api_wrapper.send(:currency_pair)[:base] = :bch
        api_wrapper.send(:currency_pair)[:quote] = :usd
      end

      it_behaves_like 'balances'

      it 'has the data belonging to its currency pair' do
        api_wrapper.balance.crypto do |currency|
          currency.total.should eq total * 2
          currency.reserved.should eq reserved * 2
          currency.available.should eq available * 2
        end
      end
    end
  end

  it '#cancel' do
    stub_orders

    api_wrapper.orders.sample.should respond_to(:cancel!)
  end

  def stub_order_book(count: 3, price: 1.5, amount: 2.5)
    Bitstamp.stub(:order_book) do
      {
        'timestamp' => Time.now.to_i.to_s,
        'bids' => count.times.map { |i| [(price + i).to_s, (amount + i).to_s] },
        'asks' => count.times.map { |i| [(price + i).to_s, (amount + i).to_s] }
      }
    end
  end

  it '#order_book' do
    stub_order_book

    order_book = api_wrapper.order_book
    order_book.should be_a(ApiWrapper::OrderBook)
    order_book.bids.all? { |bid| bid.should be_a(ApiWrapper::OrderSummary) }
    order_book.asks.all? { |ask| ask.should be_a(ApiWrapper::OrderSummary) }
    order_book.timestamp.should be_a(Integer)

    bid = order_book.bids.sample
    bid.price.should be_a(BigDecimal)
    bid.quantity.should be_a(BigDecimal)

    ask = order_book.asks.sample
    ask.price.should be_a(BigDecimal)
    ask.quantity.should be_a(BigDecimal)
  end

  # [<Bitstamp::Order @id=76, @type=0, @price='1.1', @amount='1.0', @datetime='2013-09-26 23:15:04'>]
  def stub_orders(count: 1, price: 1.5, amount: 2.5)
    Bitstamp.orders.stub(:all) do
      count.times.map do |i|
        Bitstamp::Order.new(
          id: i,
          type: (i % 2),
          price: (price + 1).to_s,
          amount: (amount + i).to_s,
          datetime: 1.seconds.ago.strftime('%Y-%m-%d %H:%m:%S')
        )
      end
    end
  end

  it '#orders' do
    stub_orders

    api_wrapper.orders.all? { |o| o.should be_a(ApiWrapper::Order) }

    order = api_wrapper.orders.sample
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)

    expect(order).to respond_to(:cancel!)
  end

  context '#place_order' do
    it 'raises OrderNotFound error on bitstamp errors' do
      Bitstamp.orders.stub(:buy) do
        raise OrderNotFound
      end

      expect { api_wrapper.place_order(:buy, 10, 100) }.to raise_exception(OrderNotFound)
    end
  end

  # [<Bitstamp::Transactions @tid=14, @price='1.9', @amount='1.1', @date='1380648951'>]
  def stub_transactions(count: 1, price: 1.5, amount: 2.5)
    Bitstamp.stub(:transactions) do
      count.times.map do |i|
        double(
          tid: i,
          date: 1.seconds.ago.to_i,
          price: (price + i).to_s,
          amount: (amount + i).to_s
        )
      end
    end
  end

  it '#transactions' do
    stub_transactions

    api_wrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = api_wrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  # [<Bitstamp::UserTransaction @id=76, @order_id=14, @type=1, @usd='0.00', @btc='-3.078', @btc_usd='0.00', @fee='0.00', @datetime='2013-09-26 13:46:59'>]
  def stub_user_transactions(count: 1, usd: 1.5, btc: 2.5, btc_usd: 3.5, fee: 0.05)
    Bitstamp.user_transactions.stub(:all) do
      count.times.map do |i|
        double(
          id: i,
          order_id: i,
          type: (i % 2),
          usd: (usd + i).to_s,
          btc: (btc + i).to_s,
          btc_usd: (btc_usd + i).to_s,
          fee: fee.to_s,
          datetime: 1.seconds.ago.strftime('%Y-%m-%d %H:%m:%S')
        )
      end
    end
  end

  it '#user_transaction' do
    stub_user_transactions
    BitstampApiWrapper.user_transactions.all? { |ut| ut.should be_a(ApiWrapper::UserTransaction) }

    user_transaction = BitstampApiWrapper.user_transactions.sample
    user_transaction.usd.should be_a(BigDecimal)
    user_transaction.btc.should be_a(BigDecimal)
    user_transaction.btc_usd.should be_a(BigDecimal)
    user_transaction.order_id.should be_a(Integer)
    user_transaction.fee.should be_a(BigDecimal)
    user_transaction.type.should be_a(Integer)
    user_transaction.timestamp.should be_a(Integer)
  end

  it '#find_lost' do
    stub_orders

    api_wrapper.orders.all? { |o| api_wrapper.find_lost(o.type, o.price, o.amount).present? }
  end
end
