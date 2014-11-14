require 'spec_helper'

describe BitexBot::OrderBookSimulator do
  describe 'when buying on bitex to sell somewhere else' do
    def simulate(volatility, amount)
      BitexBot::OrderBookSimulator.run(volatility, bitstamp_transactions_stub,
        bitstamp_order_book_stub['bids'], amount, nil)
    end

    it 'gets the safest price' do
      simulate(0, 20).should == 30
    end

    it 'adjusts for medium volatility' do
      simulate(3, 20).should == 25
    end
    
    it 'adjusts for high volatility' do
      simulate(6, 20).should == 20
    end
  
    it 'big orders dig deep' do
      simulate(0, 180).should == 15
    end
    
    it 'big orders with high volatility' do
      simulate(6, 100).should == 10
    end

    it 'still returns a price on very high volatility and low liquidity' do
      simulate(10000, 10000).should == 10
    end
  end

  describe 'when selling on bitex to buy somewhere else' do
    def simulate(volatility, quantity)
      BitexBot::OrderBookSimulator.run(volatility, bitstamp_transactions_stub,
        bitstamp_order_book_stub['asks'], nil, quantity)
    end

    it 'gets the safest price' do
      simulate(0, 2).should == 10
    end

    it 'adjusts for medium volatility' do
      simulate(3, 2).should == 15
    end
    
    it 'adjusts for high volatility' do
      simulate(6, 2).should == 25
    end
  
    it 'big orders dig deep' do
      simulate(0, 8).should == 25
    end
    
    it 'big orders with high volatility dig deep' do
      simulate(6, 6).should == 30
    end
  end
end
