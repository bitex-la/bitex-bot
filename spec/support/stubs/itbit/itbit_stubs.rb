module ItbitStubs
  def stub_itbit_balance(count: 1, total: 1.5, available: 2.5)
    stub_itbit_default_wallet_id
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

  def stub_itbit_order_book(count: 3, price: 1.5, amount: 2.5)
    Itbit::XBTUSDMarketData.stub(:orders) do
      {
        bids: count.times.map { |i| [(price + i).to_d, (amount + i).to_d] },
        asks: count.times.map { |i| [(price + i).to_d, (amount + i).to_d] }
      }
    end
  end

  def stub_itbit_orders(count: 1, amount: 1.5, price: 2.5)
    Itbit::Order.stub(:all).with(hash_including(status: :open)) do
      count.times.map do |i|
        index = i + 1
        double(
          id: "id-#{index.to_s.rjust(3, '0')}",
          wallet_id: "wallet-#{index.to_s.rjust(3, '0')}",
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
        )
      end
    end
  end

  def stub_itbit_transactions(count: 1, price: 1.5, amount: 2.5)
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

  private

  def stub_itbit_default_wallet_id
    Itbit.stub(:default_wallet_id) { 'wallet-000' }
  end
end
