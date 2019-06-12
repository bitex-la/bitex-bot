require 'spec_helper'

# When maker is Bitex and taker is Bitstamp
describe BitexBot::SellClosingFlow do
  before(:each) do
    allow(BitexBot::Robot)
      .to receive(:maker)
      .and_return(BitexApiWrapper.new(double(api_key: 'key', sandbox: true, trading_fee: 0.05, orderbook_code: 'btc_usd')))

    allow(BitexBot::Robot)
      .to receive(:taker)
      .and_return(BitstampApiWrapper.new(double(api_key: 'key', secret: 'xxx', client_id: 'yyy', order_book: 'btcusd')))

    allow(BitexBot::Settings).to receive(:selling_fx_rate).and_return(1.to_d)
  end

  let(:maker) { BitexBot::Robot.maker }
  let(:taker) { BitexBot::Robot.taker }

  describe 'closes a single open position completely' do
    before(:each) do
      stub_bitstamp_active_orders

      create(:open_sell, id: 29, price: 300, amount: 600, quantity: 2)
    end

    let(:open_trade) { BitexBot::OpenSell.find(29) }

    it 'open trade does not start to close yet' do
      expect(open_trade.closing_flow).to be_nil
    end

    context 'starting to close' do
      let(:flow) { described_class.last }

      it do
        expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

        expect(open_trade.closing_flow).to eq(flow)

        expect(flow.open_positions).to eq([open_trade])
        expect(flow.desired_price).to eq(290)
        expect(flow.amount).to eq(600)
        expect(flow.quantity).to eq(2)
        expect(flow.crypto_profit).to be_nil
        expect(flow.fiat_profit).to be_nil

        close_trade = flow.close_positions.first
        expect(close_trade.order_id).to be_present
        expect(close_trade.amount).to be_nil
        expect(close_trade.quantity).to be_nil
      end
    end
  end

  describe 'closes an aggregate of several open positions' do
    before(:each) do
      stub_bitstamp_active_orders

      create(:open_sell, id: 30)
      create(:tiny_open_sell, id: 31)
    end

    let(:open_trade) { BitexBot::OpenSell.find(30) }
    let(:tiny_open_trade) { BitexBot::OpenSell.find(31) }

    it 'open trade does not start to close yet' do
      expect(open_trade.closing_flow).to be_nil
      expect(tiny_open_trade.closing_flow).to be_nil
    end

    context 'starting to close' do
      let(:flow) { described_class.last }

      it do
        expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

        expect(open_trade.closing_flow).to eq(flow)
        expect(tiny_open_trade.closing_flow).to eq(flow)

        expect(flow.open_positions).to eq([open_trade, tiny_open_trade])
        expect(flow.desired_price.truncate(8)).to eq(290.49_751_243)
        expect(flow.amount).to eq(604)
        expect(flow.quantity).to eq(2.01)
        expect(flow.crypto_profit).to be_nil
        expect(flow.fiat_profit).to be_nil

        close_trade = flow.close_positions.first
        expect(close_trade.order_id).to be_present
        expect(close_trade.amount).to be_nil
        expect(close_trade.quantity).to be_nil
      end
    end
  end

  describe 'does not try to close if the amount is too low' do
    before(:each) { create(:tiny_open_sell) }

    it { expect { described_class.close_market }.not_to change { described_class.count } }
  end

  describe 'does not try to close if there are no open positions' do
    it { expect { described_class.close_market }.not_to change { described_class.count } }
  end

  describe 'when sync executed orders' do
    before(:each) do
      stub_bitstamp_active_orders
      allow_any_instance_of(BitstampApiWrapper).to receive(:user_transactions).and_return([])

      create(:tiny_open_sell, id: 39)
      create(:open_sell, id: 40)
    end

    let(:flow) { described_class.last }

    it 'syncs the executed orders, calculates profit' do
      expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

      stub_bitstamp_hit_orders_into_transactions

      described_class.sync_positions

      close_trade = flow.close_positions.last

      expect(close_trade.amount).to eq(583.9)
      expect(close_trade.quantity).to eq(2.01)

      expect(flow).to be_done
      expect(flow.crypto_profit).to be_zero
      expect(flow.fiat_profit).to eq(20.1)
      expect(flow.fx_rate).to eq(1)
    end

    context 'with other fx rate and closed open positions' do
      before(:each) { allow(BitexBot::Settings).to receive(:selling_fx_rate).and_return(0.5.to_d) }

      it 'syncs the executed orders, calculates profit with other fx rate' do
        expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

        stub_bitstamp_hit_orders_into_transactions

        described_class.sync_positions

        close_trade = flow.close_positions.last

        expect(flow).to be_done
        expect(flow.crypto_profit).to be_zero
        expect(flow.fiat_profit).to eq(312.05)
        expect(flow.fx_rate).to eq(0.5)
      end
    end

    it 'retries closing at a lower price every minute' do
      expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

      expect { described_class.sync_positions }.not_to change { BitexBot::CloseSell.count }
      expect(flow).not_to be_done

      # Immediately calling sync again does not try to cancel the ask.
      described_class.sync_positions
      expect(taker.orders.size).to eq(1)

      # Partially executes order, and 61 seconds after that
      # sync_closed_positions tries to cancel it.
      stub_bitstamp_hit_orders_into_transactions(ratio: 0.5)
      Timecop.travel(61.seconds.from_now)
      expect(taker.orders.size).to eq(1)

      expect { described_class.sync_positions }.not_to change { BitexBot::CloseSell.count }
      expect(taker.orders.size).to be_zero
      expect(flow.reload).not_to be_done

      # Next time we try to sync_positions, the sell closing flow class
      # detects the previous close_sell was cancelled correctly so
      # it syncs it's total amounts and tries to place a new one.
      expect { described_class.sync_positions }.to change { BitexBot::CloseSell.count }.by(1)

      close_trade = flow.reload.close_positions.first
      expect(close_trade.amount).to eq(291.95)
      expect(close_trade.quantity).to eq(1.005)

      # The second ask is executed completely so we can wrap it up and consider
      # this closing flow done.
      stub_bitstamp_hit_orders_into_transactions

      expect { described_class.sync_positions }.not_to change { BitexBot::CloseSell.count }

      close_trade = flow.reload.close_positions.last
      expect(close_trade.amount.truncate(8)).to eq(291.94_999_999)
      expect(close_trade.quantity.truncate(8)).to eq(1.00_489_622)

      expect(flow).to be_done
      expect(flow.crypto_profit.truncate(8)).to eq(-0.00_010_377)
      expect(flow.fiat_profit.truncate(8)).to eq(20.1)
      expect(flow.fx_rate).to eq(1)
    end

    it 'does not retry for an amount less than minimum_for_closing' do
      expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

      stub_bitstamp_hit_orders_into_transactions(ratio: 0.999)
      # Cancel from taker server
      BitstampStubs.active_bids.delete_if { |order| order.id ==flow.close_positions.last.order.id  }

      expect { described_class.sync_positions }.not_to change { BitexBot::CloseSell.count }

      flow.reload
      expect(flow).to be_done
      expect(flow.crypto_profit).to eq(-0.00_201)
      expect(flow.fiat_profit).to eq(20.6_839)
      expect(flow.fx_rate).to eq(1)
    end

    it 'can lose CRYPTO if price had to be dropped dramatically' do
      # This flow is forced to sell the original FIAT quantity for less, thus regaining
      # less CRYPTO than what was spent on maker.
      expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

      60.times do |attempt|
        Timecop.travel(60.seconds.from_now)
        described_class.sync_positions
      end

      stub_bitstamp_hit_orders_into_transactions
      described_class.sync_positions

      expect(flow).to be_done
      expect(flow.crypto_profit.truncate(8)).to eq(-0.17_093_047)
      expect(flow.fiat_profit.truncate(8)).to eq(20.1)
      expect(flow.fx_rate).to eq(1)
    end
  end

  describe 'when there are errors placing the closing order' do
    before(:each) { allow_any_instance_of(BitstampApiWrapper).to receive(:send_order).with(:buy, 290, 2).and_return(nil) }

    let(:flow) { described_class.last }

    it 'keeps trying to place a closed position on bitstamp errors' do
      allow_any_instance_of(BitstampApiWrapper).to receive(:find_lost).and_return(nil)

      open_trade = create(:open_sell, id: 162)

      expect(described_class.count).to be_zero

      expect do
        described_class.close_market
      end.to raise_error(BitexBot::CannotCreateFlow, 'Closing: buy order not found for BTC 2.0 @ USD 290.0.')

      expect(described_class.count).to be_zero

      # No deberia crear un flow ante un intento erroneo de crear una order
      # si la orden no se pudo crear, y tampoco se pudo encontrar, el impacto es que
      # esas open positions no fueron procesadas, solo un calculo.
      # open.reload.closing_flow.should == flow

      # flow.open_positions.should == [open]
      # flow.desired_price.should == 310
      # flow.quantity.should == 2
      # flow.crypto_profit.should be_nil
      # flow.fiat_profit.should be_nil
      # flow.close_positions.should be_empty
    end

    it 'retries until it finds the lost order' do
      order = build_bitstamp_order(:buy, 290, 2, 1.minute.ago)
      allow_any_instance_of(BitstampApiWrapper).to receive(:orders).and_return([order])

      open_trade = create(:open_sell)
      expect { described_class.close_market }.to change { BitexBot::CloseSell.count }.by(1)

      expect(flow.desired_price).to eq(290)
      expect(flow.quantity).to eq(2)
      expect(flow.amount).to eq(600)
      expect(flow.open_positions).to eq([open_trade])

      expect(flow.close_positions.last.order_id).to eq(order.id)
    end
  end
end
