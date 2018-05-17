require 'spec_helper'

describe BitexBot::BuyClosingFlow do
  it 'closes a single open position completely' do
    stub_bitstamp_trade(:sell)
    open = create :open_buy
    BitexBot::BuyClosingFlow.close_open_positions
    flow = BitexBot::BuyClosingFlow.last

    open.reload.closing_flow.should == flow

    flow.open_positions.should == [open]
    flow.desired_price.should == 310
    flow.quantity.should == 2
    flow.amount.should == 600
    flow.btc_profit.should be_nil
    flow.usd_profit.should be_nil

    close = flow.close_positions.first
    close.order_id.should == '1'
    close.amount.should be_nil
    close.quantity.should be_nil
  end

  it 'closes an aggregate of several open positions' do
    stub_bitstamp_trade(:sell)
    open_one = create :tiny_open_buy
    open_two = create :open_buy
    BitexBot::BuyClosingFlow.close_open_positions
    flow = BitexBot::BuyClosingFlow.last

    close = flow.close_positions.first

    open_one.reload.closing_flow.should == flow
    open_two.reload.closing_flow.should == flow

    flow.open_positions.should == [open_one, open_two]
    flow.desired_price.round(10).should == '310.4975124378'.to_d
    flow.quantity.should == 2.01
    flow.amount.should == 604
    flow.btc_profit.should be_nil
    flow.usd_profit.should be_nil

    close.order_id.should == '1'
    close.amount.should be_nil
    close.quantity.should be_nil
  end

  it 'does not try to close if the amount is too low' do
    open = create :tiny_open_buy
    expect do
      BitexBot::BuyClosingFlow.close_open_positions.should be_nil
    end.not_to change { BitexBot::BuyClosingFlow.count }
  end

  it 'does not try to close if there are no open positions' do
    expect do
      BitexBot::BuyClosingFlow.close_open_positions.should be_nil
    end.not_to change { BitexBot::BuyClosingFlow.count }
  end

  describe 'when syncinc executed orders' do
    before(:each) do
      stub_bitstamp_trade(:sell)
      stub_bitstamp_empty_user_transactions
      create :tiny_open_buy
      create :open_buy
    end

    it 'syncs the executed orders, calculates profit' do
      BitexBot::BuyClosingFlow.close_open_positions
      flow = BitexBot::BuyClosingFlow.last
      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)

      close = flow.close_positions.last
      close.amount.should == '624.105'.to_d
      close.quantity.should == 2.01

      flow.should be_done
      flow.btc_profit.should == 0
      flow.usd_profit.should == '20.105'.to_d
    end

    it 'retries closing at a lower price every minute' do
      BitexBot::BuyClosingFlow.close_open_positions
      flow = BitexBot::BuyClosingFlow.last

      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change { BitexBot::CloseBuy.count }
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
      end.not_to change { BitexBot::CloseBuy.count }
      Bitstamp.orders.all.size.should == 0
      flow.should_not be_done

      # Next time we try to sync_closed_positions the flow
      # detects the previous close_buy was cancelled correctly so
      # it syncs it's total amounts and tries to place a new one.
      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.to change { BitexBot::CloseBuy.count }.by(1)
      flow.close_positions.first.tap do |close|
        close.amount.should == '312.0525'.to_d
        close.quantity.should == 1.005
      end

      # The second ask is executed completely so we can wrap it up and consider
      # this closing flow done.
      stub_bitstamp_orders_into_transactions
      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      flow.close_positions.last.tap do |close|
        close.amount.should == '312.02235'.to_d
        close.quantity.should == 1.005
      end
      flow.should be_done
      flow.btc_profit.should == 0
      flow.usd_profit.should == '20.07485'.to_d
    end

    it 'does not retry for an amount less than minimum_for_closing' do
      BitexBot::BuyClosingFlow.close_open_positions
      flow = BitexBot::BuyClosingFlow.last
      stub_bitstamp_orders_into_transactions(ratio: 0.999)
      Bitstamp.orders.all.first.cancel!

      expect do
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end.not_to change { BitexBot::CloseBuy.count }

      flow.should be_done
      flow.btc_profit.should == 0.00201
      flow.usd_profit.should == '19.480895'.to_d
    end

    it 'can lose USD if price had to be dropped dramatically' do
      # This flow is forced to sell the original BTC quantity for less, thus regaining
      # less USD than what was spent on bitex.
      BitexBot::BuyClosingFlow.close_open_positions
      flow = BitexBot::BuyClosingFlow.last

      60.times do
        Timecop.travel 60.seconds.from_now
        flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      end

      stub_bitstamp_orders_into_transactions

      flow.sync_closed_positions(Bitstamp.orders.all, Bitstamp.user_transactions.all)
      flow.reload.should be_done
      flow.btc_profit.should == 0
      flow.usd_profit.should == '-34.165'.to_d
    end
  end

  describe 'when there are errors placing the closing order' do
    it 'keeps trying to place a closed position on bitstamp errors' do
      BitstampApiWrapper.stub(send_order: nil)
      BitstampApiWrapper.stub(find_lost: nil) 

      open = create :open_buy
      expect do
        BitexBot::BuyClosingFlow.close_open_positions
      end.to raise_exception(OrderNotFound)
      flow = BitexBot::BuyClosingFlow.last

      open.reload.closing_flow.should == flow

      flow.open_positions.should == [open]
      flow.desired_price.should == 310
      flow.quantity.should == 2
      flow.btc_profit.should be_nil
      flow.usd_profit.should be_nil
      flow.close_positions.should be_empty
    end

    it 'retries until it finds the lost order in the bitstamp' do
      BitstampApiWrapper.stub(send_order: nil)
      counter = 0

      BitstampApiWrapper.stub(:find_lost) do
        counter += 1
        next if counter < 3
        double(amount: 1000, price: 2000, type: 1, id: 1234, datetime: DateTime.now.to_s)
      end

      open = create :open_buy
      BitexBot::BuyClosingFlow.close_open_positions
      flow = BitexBot::BuyClosingFlow.last

      flow.close_positions.should_not be_empty
      flow.close_positions.first do |position|
        position.id.should be 1234
        position.type.should be 1
        position.amount.should be 1000
        position.price.should be 2000
      end
      counter.should == 3
    end
  end
end
