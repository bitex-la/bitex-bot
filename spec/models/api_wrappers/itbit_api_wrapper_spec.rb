require 'spec_helper'

describe ItbitApiWrapper do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      itbit: {
        client_key: 'client-key',
        secret: 'secret',
        user_id: 'user-id',
        default_wallet_id: 'wallet-000',
        sandbox: false,
        order_book: 'xbtusd'
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  let(:api_wrapper) { BitexBot::Robot.taker }

  it 'Sends User-Agent header' do
    url = "https://api.itbit.com/v1/markets/#{api_wrapper.currency_pair[:name].upcase}/order_book"
    stub_stuff = stub_request(:get, url).with(headers: { 'User-Agent': BitexBot.user_agent })

    # We don't care about the response
    api_wrapper.order_book rescue nil

    expect(stub_stuff).to have_been_requested
  end

  def stub_default_wallet_id
    Itbit.stub(:default_wallet_id) { 'wallet-000' }
  end

  def stub_balance(count: 1, total: 1.5, available: 2.5)
    stub_default_wallet_id
    Itbit::Wallet.stub(:all) do
      count.times.map do |i|
        {
          id: "wallet-#{i.to_s.rjust(3, '0')}",
          name: 'primary',
          user_id: '326a3369-78fc-44e7-ad52-03e97371ca72',
          account_identifier: 'PRIVATEBETA55-2285-2HN',
          balances: [
            { total_balance: (total + i).to_d, currency: :usd, available_balance: (available + i).to_d },
            { total_balance: (total + i).to_d, currency: :xbt, available_balance: (available + i).to_d },
            { total_balance: (total + i).to_d, currency: :eur, available_balance: (available + i).to_d }
          ]
        }
      end
    end
  end

  it '#balance' do
    stub_balance

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
    fiat.reserved.should be_a(BigDecimal)
    fiat.available.should be_a(BigDecimal)

    balance.fee.should be_a(BigDecimal)
  end

  it '#cancel' do
    stub_orders

    expect(api_wrapper.orders.sample).to respond_to(:cancel!)
  end

  def stub_order_book(count: 3, price: 1.5, amount: 2.5)
    Itbit::XBTUSDMarketData.stub(:orders) do
      {
        bids: count.times.map { |i| [(price + i).to_d, (amount + i).to_d] },
        asks: count.times.map { |i| [(price + i).to_d, (amount + i).to_d] }
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

  def stub_orders(count: 1, amount: 1.5, price: 2.5)
    Itbit::Order.stub(:all).with(hash_including(status: :open)) do
      count.times.map do |i|
        Itbit::Order.new({
          id: "id-#{i.to_s.rjust(3, '0')}",
          wallet_id: "wallet-#{i.to_s.rjust(3, '0')}",
          side: :buy,
          instrument: :xbtusd,
          type: :limit,
          amount: (amount + i).to_d,
          display_amount: (amount + i).to_d,
          amount_filled: (amount + i).to_d,
          price: (price + i).to_d,
          volume_weighted_average_price: (price + i).to_d,
          status: :open,
          client_order_identifier: 'o',
          metadata: { foo: 'bar' },
          created_time: 1.seconds.ago.to_i
        }.stringify_keys)
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
  end

  def stub_transactions(count: 1, price: 1.5, amount: 2.5)
    Itbit::XBTUSDMarketData.stub(:trades) do
      count.times.map do |i|
        {
          tid: i,
          price: (price + i).to_d,
          amount: (amount + i).to_d,
          date: 1.seconds.ago.to_i
        }
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

  it '#user_transaction' do
    api_wrapper.user_transactions.should be_a(Array)
    api_wrapper.user_transactions.empty?.should be_truthy
  end

  it '#find_lost' do
    stub_orders

    api_wrapper.orders.all? { |o| api_wrapper.find_lost(o.type, o.price, o.amount).present? }
  end
end
