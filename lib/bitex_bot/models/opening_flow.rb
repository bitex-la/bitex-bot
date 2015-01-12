module BitexBot
  # Any arbitrage workflow has 2 stages, opening positions and then closing them.
  # The OpeningFlow stage places an order on bitex, detecting and storing all
  # transactions spawn from that order as Open positions.
  class OpeningFlow < ActiveRecord::Base
    self.abstract_class = true

    # The updated config store as passed from the robot
    cattr_accessor :store
    
    def self.active
      where('status != "finalised"')
    end
    
    def self.old_active
      where('status != "finalised" AND created_at < ?',
        Settings.time_to_live.seconds.ago)
    end

    # @!group Statuses

    # All possible flow statuses
    # @return [Array<String>]
    def self.statuses
      %w(executing settling finalised)
    end

    # The Bitex order has been placed, its id stored as order_id.
    def executing?; status == 'executing'; end

    # In process of cancelling the Bitex order and any other outstanding order in the
    # other exchange.
    def settling?; status == 'settling'; end

    # Successfully settled or finished executing.
    def finalised?; status == 'finalised'; end
    # @!endgroup

    validates :status, presence: true, inclusion: {in: statuses}
    validates :order_id, presence: true
    validates_presence_of :price, :value_to_use

    def self.create_for_market(remote_balance, order_book, transactions,
      bitex_fee, other_fee, store)

      self.store = store

      plus_bitex = value_to_use + (value_to_use * bitex_fee / 100.0)
      value_to_use_needed = plus_bitex / (1 - other_fee / 100.0)
      
      safest_price = get_safest_price(transactions, order_book,
        value_to_use_needed)

      remote_value_to_use = get_remote_value_to_use(value_to_use_needed, safest_price)
      
      if remote_value_to_use > remote_balance
        raise CannotCreateFlow.new(
          "Needed #{remote_value_to_use} but you only have #{remote_balance}")
      end

      bitex_price = get_bitex_price(value_to_use, remote_value_to_use)      

      begin 
        order = order_class.create!(:btc, value_to_use, bitex_price, true)
      rescue StandardError => e
        raise CannotCreateFlow.new(e.message)
      end

      if order.reason == :not_enough_funds
        raise CannotCreateFlow.new(
          "You need to have #{value_to_use} on bitex to place this
          #{order_class.name}.")
      end

      Robot.logger.info("Opening: Placed #{order_class.name} ##{order.id} " \
        "#{value_to_use} @ $#{bitex_price} (#{remote_value_to_use})")

      begin 
        self.create!(price: bitex_price, value_to_use: value_to_use,
          suggested_closing_price: safest_price, status: 'executing', order_id: order.id)
      rescue StandardError => e
        raise CannotCreateFlow.new(e.message)
      end
    end

    # Buys on bitex represent open positions, we mirror them locally
    # so that we can plan on how to close them.
    def self.sync_open_positions
      threshold = open_position_class
        .order('created_at DESC').first.try(:created_at)
      Bitex::Trade.all.collect do |transaction|
        next unless transaction.is_a?(transaction_class)
        next if threshold && transaction.created_at < (threshold - 30.minutes)
        next if open_position_class.find_by_transaction_id(transaction.id)
        next if transaction.specie != :btc
        next unless flow = find_by_order_id(transaction_order_id(transaction))
        Robot.logger.info("Opening: #{name} ##{flow.id} "\
          "was hit for #{transaction.quantity} BTC @ $#{transaction.price}")
        open_position_class.create!(
          transaction_id: transaction.id,
          price: transaction.price,
          amount: transaction.amount,
          quantity: transaction.quantity,
          opening_flow: flow)
      end.compact
    end
    
    def finalise!
      order = self.class.order_class.find(order_id)
      if order.status == :cancelled || order.status == :completed
        Robot.logger.info(
          "Opening: #{self.class.order_class.name} ##{order_id} finalised.")
        self.status = 'finalised'
        save!
      else
        order.cancel!
        unless settling?
          self.status = 'settling'
          save!
        end
      end
    end
  end   

  # @visibility private
  class CannotCreateFlow < StandardError; end
end
