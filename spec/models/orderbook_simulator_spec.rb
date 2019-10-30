require 'spec_helper'

describe BitexBot::OrderbookSimulator do
  before(:each) do
    allow(BitexBot::Robot)
      .to receive(:maker)
      .and_return(BitexBot::ApiWrappers::Bitex.new(double(api_key: 'key', sandbox: true, trading_fee: 0.05, orderbook_code: 'btc_usd')))

    allow(BitexBot::Robot)
      .to receive(:taker)
      .and_return(BitexBot::ApiWrappers::Bitstamp.new(double(api_key: 'key', secret: 'xxx', client_id: 'yyy', order_book: 'btcusd')))

    allow(BitexBot::Settings).to receive(:buying_fx_rate).and_return(1.to_d)
  end

  let(:maker) { BitexBot::Robot.maker }
  let(:taker) { BitexBot::Robot.taker }

  before(:each) do
    stub_bitstamp_transactions
    stub_bitstamp_market
  end

  describe 'when buying on bitex to sell somewhere else' do
    subject(:price) { BitexBot::OrderbookSimulator.run(volatility, taker.transactions, taker.market.bids, amount, nil) }

    context 'gets the safest price' do
      let(:volatility) { 0 }
      let(:amount) { 20.to_d }

      it { is_expected.to eq(30) }
    end

    context 'adjusts for medium volatility' do
      let(:volatility) { 3 }
      let(:amount) { 20.to_d }

      it { is_expected.to eq(25) }
    end

    context 'adjusts for high volatility' do
      let(:volatility) { 6 }
      let(:amount) { 20.to_d }

      it { is_expected.to eq(20) }
    end

    context 'big orders dig deep' do
      let(:volatility) { 0 }
      let(:amount) { 180.to_d }

      it { is_expected.to eq(15) }
    end

    context 'big orders with high volatility' do
      let(:volatility) { 6 }
      let(:amount) { 100.to_d }

      it { is_expected.to eq(10) }
    end

    context 'still returns a price on very high volatility and low liquidity' do
      let(:volatility) { 10_000 }
      let(:amount) { 10_000.to_d }

      it { is_expected.to eq(10) }
    end
  end

  describe 'when selling on bitex to buy somewhere else' do
    subject(:price) { BitexBot::OrderbookSimulator.run(volatility, taker.transactions, taker.market.asks, nil, quantity) }

    context 'gets the safest price' do
      let(:volatility) { 0 }
      let(:quantity) { 2.to_d }

      it { is_expected.to eq(10) }
    end

    context 'adjusts for medium volatility' do
      let(:volatility) { 3 }
      let(:quantity) { 2.to_d }

      it { is_expected.to eq(15) }
    end

    context 'adjusts for high volatility' do
      let(:volatility) { 6 }
      let(:quantity) { 2.to_d }

      it { is_expected.to eq(25) }
    end

    context 'big orders dig deep' do
      let(:volatility) { 0 }
      let(:quantity) { 8.to_d }

      it { is_expected.to eq(25) }
    end

    context 'big orders with high volatility' do
      let(:volatility) { 6 }
      let(:quantity) { 6.to_d }

      it { is_expected.to eq(30) }
    end
  end
end
