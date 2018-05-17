module KrakenStubs
  def stub_kraken_public_client
    api_client.stub(public: double)
  end

  def stub_kraken_private_client
    api_client.stub(private: double)
  end

  def stub_kraken_balance
    api_client.private.stub(account_info: [{ taker_fees: '89.2' }])
    api_client.private.stub(:balance) do
      { 'XXBT': '1433.0939', 'ZUSD': '1230.0233', 'XETH': '99.7497224800' }.with_indifferent_access
    end
  end

  def stub_kraken_trade_volume
    api_client.private.stub(:trade_volume).with(hash_including(pair: 'XBTUSD')) do
      {
        'currency' => 'ZUSD', 'volume' => '3878.8703',
        'fees' => {
          'XXBTZUSD' => {
            'fee' => '0.2600',
            'minfee' => '0.1000',
            'maxfee' => '0.2600',
            'nextfee' => '0.2400',
            'nextvolume' => '10000.0000',
            'tiervolume' => '0.0000'
          }
        },
        'fees_maker' => {
          'XETHZEUR' => {
            'fee' => '0.1600',
            'minfee' => '0.0000',
            'maxfee' => '0.1600',
            'nextfee' => '0.1400',
            'nextvolume' => '10000.0000',
            'tiervolume' => '0.0000'
          }
        }
      }.with_indifferent_access
    end
  end

  def stub_kraken_order_book(count: 3, price: 1.5, amount: 2.5)
    api_client.public.stub(:order_book) do
      {
        'XXBTZUSD' => {
          'bids' => count.times.map { |i| [(price + i).to_d, (amount + i).to_d, 1.seconds.ago.to_i.to_s] },
          'asks' => count.times.map { |i| [(price + i).to_d, (amount + i).to_d, 1.seconds.ago.to_i.to_s] }
        }
      }.with_indifferent_access
    end
  end

  def stub_kraken_orders
    api_client.private.stub(:open_orders) do
      {
        'open' => {
          'O5TDV2-WDYB2-6OGJRD' => {
            'refid' => nil, 'userref' => nil, 'status' => 'open', 'opentm' => 1_440_292_821.839, 'starttm' => 0, 'expiretm' => 0,
            'descr' => {
              'pair' => 'ETHEUR', 'type' => 'buy', 'ordertype' => 'limit', 'price' => '1.19000', 'price2' => '0',
              'leverage' => 'none', 'order' => 'buy 1204.00000000 ETHEUR @ limit 1.19000'
            },
            'vol' => '1204.00000000', 'vol_exec' => '0.00000000', 'cost' => '0.00000', 'fee' => '0.00000',
            'price' => '0.00008', 'misc' => '', 'oflags' => 'fciq'
          },
          'OGAEYL-LVSPL-BYGGRR' => {
            'refid' => nil, 'userref' => nil, 'status' => 'open', 'opentm' => 1_440_254_004.621, 'starttm' => 0, 'expiretm' => 0,
            'descr' => {
              'pair' => 'ETHEUR', 'type' => 'sell', 'ordertype' => 'limit', 'price' => '1.29000', 'price2' => '0',
              'leverage' => 'none', 'order' => 'sell 99.74972000 ETHEUR @ limit 1.29000'
            },
            'vol' => '99.74972000', 'vol_exec' => '0.00000000', 'cost' => '0.00000', 'fee' => '0.00000',
            'price' => '0.00009', 'misc' => '', 'oflags' => 'fciq'
          }
        }
      }.with_indifferent_access
    end
  end

  def stub_kraken_transactions(count: 1, price: 1.5, amount: 2.5)
    api_client.public.stub(:trades).with('XBTUSD') do
      {
        XXBTZUSD: [
          ['202.51626', '0.01440000', 1_440_277_319.1_922, 'b', 'l', ''],
          ['202.54000', '0.10000000', 1_440_277_322.8_993, 'b', 'l', '']
        ]
      }
    end
  end

  private

  def api_client
    KrakenApiWrapper.client
  end
end
