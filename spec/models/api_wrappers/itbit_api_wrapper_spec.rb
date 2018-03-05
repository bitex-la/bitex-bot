require 'spec_helper'

describe ItbitApiWrapper do
  before(:each) do
    BitexBot::Robot.stub(taker: api_wrapper)
    BitexBot::Robot.setup
  end

  def stub_itbit_transactions
    Itbit::XBTUSDMarketData.stub(:trades) do
      [
        { tid: 601855, price: 0.4.to_d, amount: 0.19.to_d, date: 1460161126 },
        { tid: 601856, price: 0.5.to_d, amount: 0.18.to_d, date: 1460161129 }
      ]
    end
  end

  def stub_itbit_orders
    Itbit::Order.stub(:all).with(status: :open) do
      [
        double(
          id: '8888888-ffff', wallet_id: 'b440efce-5555', side: :buy, instrument: :xbtusd, type: :limit,
          amount: 3.to_d, display_amount: 3.to_d, amount_filled: 3.to_d, price: 0.5.to_d,
          volume_weighted_average_price: 3.to_d, status: :open, client_order_identifier: 'o', created_time: 1415290187,
          metadata: { foo: 'bar' }
        ),
        double(
          id: '7777777-gggg', wallet_id: 'b440efce-4444', side: :buy, instrument: :xbtusd, type: :limit,
          amount: 3.to_d, display_amount: 3.to_d, amount_filled: 3.to_d, price: 0.5.to_d,
          volume_weighted_average_price: 3.to_d, status: :open, client_order_identifier: 'o', created_time: 1415290287,
          metadata: { foo: 'bar' }
        )
      ]
    end
  end

  def stub_itbit_order_book
    Itbit::XBTUSDMarketData.stub(:orders) do
      {
        bids: [[0.63.to_d, 0.1.to_d], [0.63.to_d, 0.4.to_d], [0.63.to_d, 0.15.to_d]],
        asks: [[0.64.to_d, 0.4.to_d], [0.64.to_d, 0.9.to_d], [0.64.to_d, 0.25.to_d]]
      }
    end
  end

  def stub_itbit_default_wallet_id
    Itbit.stub(:default_wallet_id) { 'fae1ce9a-848d-479b-b059-e93cb026cdf9' }
  end

  def stub_itbit_balance
    Itbit::Wallet.stub(:all) do
      [{
        id: 'fae1ce9a-848d-479b-b059-e93cb026cdf9',
        name: 'primary',
        user_id: '326a3369-78fc-44e7-ad52-03e97371ca72',
        account_identifier: 'PRIVATEBETA55-2285-2HN',
        balances: [
          { total_balance: 20.8.to_d, currency: :usd, available_balance: 10.0.to_d },
          { total_balance: 0.to_d, currency: :xbt, available_balance: 0.to_d },
          { total_balance: 0.to_d, currency: :eur, available_balance: 0.to_d }
        ]
      }]
    end
  end

  let(:api_wrapper) { ItbitApiWrapper }

  it '#transactions' do
    stub_itbit_transactions

    api_wrapper.transactions.all? { |o| o.should be_a(ApiWrapper::Transaction) }

    transaction = api_wrapper.transactions.sample
    transaction.id.should be_a(Integer)
    transaction.price.should be_a(BigDecimal)
    transaction.amount.should be_a(BigDecimal)
    transaction.timestamp.should be_a(Integer)
  end

  it '#orders' do
    stub_itbit_orders

    api_wrapper.orders.all? { |o| o.should be_a(ApiWrapper::Order) }

    order = api_wrapper.orders.sample
    order.id.should be_a(String)
    order.type.should be_a(Symbol)
    order.price.should be_a(BigDecimal)
    order.amount.should be_a(BigDecimal)
    order.timestamp.should be_a(Integer)
  end

  it '#order_book' do
    stub_itbit_order_book

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

  it '#balance' do
    stub_itbit_default_wallet_id
    stub_itbit_balance

    balance = api_wrapper.balance
    balance.should be_a(ApiWrapper::BalanceSummary)
    balance.btc.should be_a(ApiWrapper::Balance)
    balance.usd.should be_a(ApiWrapper::Balance)

    btc = balance.btc
    btc.total.should be_a(BigDecimal)
    btc.reserved.should be_a(BigDecimal)
    btc.available.should be_a(BigDecimal)

    usd = balance.usd
    usd.total.should be_a(BigDecimal)
    usd.reserved.should be_a(BigDecimal)
    usd.available.should be_a(BigDecimal)

    balance.fee.should be_a(BigDecimal)
  end

  it '#user_transaction' do
    api_wrapper.user_transactions.should be_a(Array)
    api_wrapper.user_transactions.empty?.should be_truthy
  end
end
