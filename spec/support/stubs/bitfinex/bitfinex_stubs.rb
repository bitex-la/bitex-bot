module BitfinexStubs
  # [
  #   { type: 'exchange', currency: 'btc', amount: '0.0', available: '0.0' },
  #   { type: 'exchange', currency: 'usd', amount: '0.0', available: '0.0' },
  #   ...
  # ]
  def stub_bitfinex_balance(count: 2, amount: 1.5, available: 2.5, fee: 1.0)
    stub_bitfinex_account_info
    Bitfinex::Client.any_instance.stub(:balances).with(hash_including(type: 'exchange')) do
      count.times.map do |i|
        {
          type: 'exchange',
          currency: (i % 2).zero? ? 'usd' : 'btc',
          amount: (amount + i).to_s,
          available: (available + i).to_s
        }
      end
    end
  end

  # [
  #   {
  #     id: 448411365, symbol: 'btcusd', exchange: 'bitfinex', price: '0.02', avg_execution_price: '0.0',  side: 'buy',
  #     type: 'exchange limit', timestamp: '1444276597.0', is_live: true, is_cancelled: false, is_hidden: false,
  #     was_forced: false, original_amount: '0.02', remaining_amount: '0.02', executed_amount: '0.0'
  #   }
  # ]
  def stub_bitfinex_orders(count: 1)
    Bitfinex::Client.any_instance.stub(:orders) do
      count.times.map do |i|
        {
          id: i + 1,
          symbol: 'btcusd',
          exchange: 'bitfinex',
          price: '0.02',
          avg_execution_price: '0.0',
          side: 'buy',
          type: 'exchange limit',
          timestamp: 1.seconds.ago.to_f.to_s,
          is_live: true,
          is_cancelled: false,
          is_hidden: false,
          was_forced: false,
          original_amount: '0.02',
          remaining_amount: '0.02',
          executed_amount: '0.0'
        }
      end
    end
  end

  # {
  #   bids: [{ price: '574.61', amount: '0.14397', timestamp: '1472506127.0' }],
  #   asks: [{ price: '574.62', amount: '19.1334', timestamp: '1472506126.0 '}]
  # }
  def stub_bitfinex_order_book(count: 3, amount: 1.5, price: 2.5)
    Bitfinex::Client.any_instance.stub(:orderbook) do
      {
        bids: count.times.map { |i| { price: (price + i).to_s, amount: (amount + i).to_s, timestamp: 1.seconds.ago.to_f.to_s } },
        asks: count.times.map { |i| { price: (price + i).to_s, amount: (amount + i).to_s, timestamp: 1.seconds.ago.to_f.to_s } }
      }
    end
  end

  # { tid: 15627111, price: 404.01, amount: '2.45116479', exchange: 'bitfinex', type: 'sell', timestamp: 1455526974 }
  def stub_bitfinex_transactions(count: 1, price: 1.5, amount: 2.5)
    Bitfinex::Client.any_instance.stub(:trades) do
      count.times.map do |i|
        {
          tid: i,
          price: price + 1,
          amount: (amount + i).to_s,
          exchange: 'bitfinex',
          type: (i % 2).zero? ? 'sell' : 'buy',
          timestamp: 1.seconds.ago.to_i
        }
      end
    end
  end

  private

  def stub_bitfinex_account_info
    Bitfinex::Client.any_instance.stub(:account_info) do
      [
        {
          maker_fees: '0.1',
          taker_fees: '0.2',
          fees: [
            { pairs: 'BTC', maker_fees: '0.1', taker_fees: '0.2' },
            { pairs: 'LTC', maker_fees: '0.1', taker_fees: '0.2' },
            { pairs: 'ETH', maker_fees: '0.1', taker_fees: '0.2' }
          ]
        }
      ]
    end
  end
end
