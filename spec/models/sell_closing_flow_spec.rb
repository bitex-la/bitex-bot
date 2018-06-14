require 'spec_helper'

describe BitexBot::SellClosingFlow do
  let(:taker_settings) do
    BitexBot::SettingsClass.new(
      bitstamp: {
        api_key: 'YOUR_API_KEY', secret: 'YOUR_API_SECRET', client_id: 'YOUR_BITSTAMP_USERNAME'
      }
    )
  end

  before(:each) do
    BitexBot::Settings.stub(taker: taker_settings)
    BitexBot::Robot.setup
  end

  it 'closes a single open position completely' do
    stub_bitstamp_buy
    open = create :open_sell
    BitexBot::SellClosingFlow.close_open_positions
    flow = BitexBot::SellClosingFlow.last

    open.reload.closing_flow.should == flow

    flow.open_positions.should == [open]
    flow.desired_price.should == 290
    flow.quantity.should == 2
    flow.amount.should == 600
    flow.btc_profit.should be_nil
    flow.fiat_profit.should be_nil

    close = flow.close_positions.first
    close.order_id.should == '1'
    close.amount.should be_nil
    close.quantity.should be_nil
  end

  it 'closes an aggregate of several open positions' do
    stub_bitstamp_buy
    open_one = create :tiny_open_sell
    open_two = create :open_sell
    BitexBot::SellClosingFlow.close_open_positions
    flow = BitexBot::SellClosingFlow.last

    close = flow.close_positions.first

    open_one.reload.closing_flow.should == flow
    open_two.reload.closing_flow.should == flow

    flow.open_positions.should == [open_one, open_two]
    flow.desired_price.round(10).should == '290.4975124378'.to_d
    flow.quantity.should == 2.01
    flow.amount.should == 604
    flow.btc_profit.should be_nil
    flow.fiat_profit.should be_nil

    close.order_id.should == '1'
    close.amount.should be_nil
    close.quantity.should be_nil
  end

  describe 'when there are errors placing the closing order' do
    it 'keeps trying to place a closed position on bitstamp errors' do
      BitstampApiWrapper.stub(send_order: nil)
      BitstampApiWrapper.stub(find_lost: nil)

      open = create :open_sell
      expect do
        flow = BitexBot::SellClosingFlow.close_open_positions
      end.to raise_exception(OrderNotFound)
      flow = BitexBot::SellClosingFlow.last

      open.reload.closing_flow.should == flow

      flow.open_positions.should == [open]
      flow.desired_price.should == 290
      flow.quantity.should == 2
      flow.btc_profit.should be_nil
      flow.fiat_profit.should be_nil
      flow.close_positions.should be_empty
    end

    it 'retries until it finds the lost order' do
      BitstampApiWrapper.stub(send_order: nil)
      BitstampApiWrapper.stub(:orders) do
        [BitstampApiWrapper::Order.new(1, :buy, 290, 2, 1.minute.ago.to_i)]
      end

      open = create(:open_sell)
      BitexBot::SellClosingFlow.close_open_positions
      flow = BitexBot::SellClosingFlow.last

      flow.close_positions.should_not be_empty
      flow.close_positions.first do |position|
        position.id.should eq 1234
        position.type.should eq 1
        position.amount.should eq 1000
        position.price.should eq 2000
      end
    end
  end

  it 'does not try to close if the amount is too low' do
    open = create :tiny_open_sell
    expect do
      BitexBot::SellClosingFlow.close_open_positions.should be_nil
    end.not_to change{ BitexBot::SellClosingFlow.count }
  end

  it 'does not try to close if there are no open positions' do
    expect do
      BitexBot::SellClosingFlow.close_open_positions.should be_nil
    end.not_to change{ BitexBot::SellClosingFlow.count }
  end

  describe 'when syncinc executed orders' do
    before(:each) do
      stub_bitstamp_buy
      stub_bitstamp_empty_user_transactions
      create :tiny_open_sell
      create :open_sell
    end

    it 'syncs the executed orders, calculates profit' do
      BitexBot::SellClosingFlow.close_open_positions
      flow = BitexBot::SellClosingFlow.last
      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)

      close = flow.close_positions.last
      close.amount.should == '583.905'.to_d
      close.quantity.should == 2.01

      flow.should be_done
      flow.btc_profit.should == 0
      flow.fiat_profit.should == '20.095'.to_d
    end

    context 'with other fx rate and closed open positions' do
      let(:fx_rate) { 10.to_d }
      let(:flow) { subject.class.last }
      let(:positions_balance_amount) { flow.open_positions.sum(:amount) - flow.positions_balance_amount }

      before(:each) do
        BitexBot::Settings.stub(fx_rate: fx_rate)
        subject.class.close_open_positions

        stub_bitstamp_orders_into_transactions
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end

      it 'syncs the executed orders, calculates profit with other fx rate' do
        flow.should be_done
        flow.btc_profit.should be_zero
        flow.fiat_profit.should eq positions_balance_amount
      end
    end

    it 'retries closing at a higher price every minute' do
      BitexBot::SellClosingFlow.close_open_positions
      flow = BitexBot::SellClosingFlow.last

      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change{ BitexBot::CloseSell.count }
      flow.should_not be_done

      # Immediately calling sync again does not try to cancel the ask.
      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      Bitstamp.orders.all.size.should == 1

      # Partially executes order, and 61 seconds after that
      # sync_closed_positions tries to cancel it.
      stub_bitstamp_orders_into_transactions(ratio: 0.5)
      Timecop.travel 61.seconds.from_now
      Bitstamp.orders.all.size.should == 1
      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change{ BitexBot::CloseSell.count }
      Bitstamp.orders.all.size.should == 0
      flow.should_not be_done

      # Next time we try to sync_closed_positions the flow
      # detects the previous close_buy was cancelled correctly so
      # it syncs it's total amounts and tries to place a new one.
      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.to change{ BitexBot::CloseSell.count }.by(1)

      flow.close_positions.first.tap do |close|
        close.amount.should == '291.9525'.to_d
        close.quantity.should == 1.005
      end

      # The second ask is executed completely so we can wrap it up and consider
      # this closing flow done.
      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      flow.close_positions.last.tap do |close|
        close.amount.should == '291.953597'.to_d
        close.quantity.should == '1.0049'.to_d
      end
      flow.should be_done
      flow.btc_profit.should == '-0.0001'.to_d
      flow.fiat_profit.should == '20.093903'.to_d
    end

    it 'does not retry for an amount less than minimum_for_closing' do
      BitexBot::SellClosingFlow.close_open_positions
      flow = BitexBot::SellClosingFlow.last

      20.times do
        Timecop.travel 60.seconds.from_now
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end

      stub_bitstamp_orders_into_transactions(ratio: 0.999)
      Bitstamp.orders.all.first.cancel!

      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change{ BitexBot::CloseSell.count }

      flow.should be_done
      flow.btc_profit.should == '-0.0224895'.to_d
      flow.fiat_profit.should == '20.66566825'.to_d
    end

    it 'can lose BTC if price had to be raised dramatically' do
      # This flow is forced to spend the original USD amount paying more than
      # expected, thus regaining less BTC than what was sold on bitex.
      BitexBot::SellClosingFlow.close_open_positions
      flow = BitexBot::SellClosingFlow.last

      60.times do
        Timecop.travel 60.seconds.from_now
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end

      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      flow.reload.should be_done
      flow.btc_profit.should == '-0.1709'.to_d
      flow.fiat_profit.should == '20.08575'.to_d

      close = flow.close_positions.last
      (close.amount / close.quantity).should == '317.5'.to_d
    end
  end
end
