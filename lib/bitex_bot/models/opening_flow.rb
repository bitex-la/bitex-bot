module BitexBot
  # Any arbitrage workflow has 2 stages, opening positions and then closing them.
  # The OpeningFlow stage places an order on bitex, detecting and storing all transactions spawn from that order as
  # Open positions.
  #
  class OpeningFlow < ActiveRecord::Base
    self.abstract_class = true

    # The updated config store as passed from the robot
    cattr_accessor :store

    # @!group Statuses
    # All possible flow statuses
    # @return [Array<String>]
    cattr_accessor(:statuses) { %w[executing settling finalised] }

    def self.active
      where('status != "finalised"')
    end

    def self.old_active
      where('status != "finalised" AND created_at < ?', Settings.time_to_live.seconds.ago)
    end
    # @!endgroup

    # This use hooks methods, these must be defined in the subclass:
    #   #maker_price
    #   #order_class
    #   #remote_value_to_use
    #   #safest_price
    #   #value_to_use
    # rubocop:disable Metrics/AbcSize
    def self.create_for_market(remote_balance, order_book, transactions, maker_fee, taker_fee, store)
      self.store = store

      remote_value, safest_price = calc_remote_value(maker_fee, taker_fee, order_book, transactions)
      raise CannotCreateFlow, "Needed #{remote_value} but you only have #{remote_balance}" unless
        enough_remote_funds?(remote_balance, remote_value)

      bitex_price = maker_price(remote_value) * fx_rate
      order = create_order!(bitex_price)
      raise CannotCreateFlow, "You need to have #{value_to_use} on bitex to place this #{order_class.name}." unless
        enough_funds?(order)

      Robot.log(:info, "Opening: Placed #{order_class.name} ##{order.id} #{value_to_use} @ $#{bitex_price} (#{remote_value})")

      create!(
        price: bitex_price,
        value_to_use: value_to_use,
        suggested_closing_price: safest_price,
        status: 'executing',
        order_id: order.id
      )
    rescue StandardError => e
      raise CannotCreateFlow, e.message
    end
    # rubocop:enable Metrics/AbcSize

    # create_for_market helpers
    def self.calc_remote_value(maker_fee, taker_fee, order_book, transactions)
      value_to_use_needed = (value_to_use + maker_plus(maker_fee)) / (1 - taker_fee / 100)
      safest_price = safest_price(transactions, order_book, value_to_use_needed)
      remote_value = remote_value_to_use(value_to_use_needed, safest_price)

      [remote_value, safest_price]
    end

    def self.create_order!(bitex_price)
      order_class.create!(:btc, value_to_use, bitex_price, true)
    rescue StandardError => e
      raise CannotCreateFlow, e.message
    end

    def self.enough_funds?(order)
      !order.reason.to_s.inquiry.not_enough_funds?
    end

    def self.enough_remote_funds?(remote_balance, remote_value)
      remote_balance >= remote_value
    end

    def self.maker_plus(fee)
      value_to_use * fee / 100
    end

    def self.fx_rate
      store.fx_rate || Settings.fx_rate
    end
    # end: create_for_market helpers

    # Buys on bitex represent open positions, we mirror them locally so that we can plan on how to close them.
    # This use hooks methods, these must be defined in the subclass:
    #   #transaction_order_id(transaction)
    #   #open_position_class
    def self.sync_open_positions
      threshold = open_position_class.order('created_at DESC').first.try(:created_at)
      Bitex::Trade.all.map do |transaction|
        next if sought_transaction?(threshold, transaction)
        flow = find_by_order_id(transaction_order_id(transaction))
        next unless flow.present?

        create_open_position!(transaction, flow)
      end.compact
    end

    # sync_open_positions helpers
    def self.create_open_position!(transaction, flow)
      Robot.log(:info, "Opening: #{name} ##{flow.id} was hit for #{transaction.quantity} BTC @ $#{transaction.price}")
      open_position_class.create!(
        transaction_id: transaction.id,
        price: transaction.price,
        amount: transaction.amount,
        quantity: transaction.quantity,
        opening_flow: flow
      )
    end

    # This use hooks methods, these must be defined in the subclass:
    #   #transaction_class
    def self.sought_transaction?(threshold, transaction)
      !transaction.is_a?(transaction_class) ||
        active_transaction?(transaction, threshold) ||
        open_position?(transaction) ||
        !btc_specie?(transaction)
    end
    # end: sync_open_positions helpers

    # sought_transaction helpers
    def self.active_transaction?(transaction, threshold)
      threshold && transaction.created_at < (threshold - 30.minutes)
    end

    def self.open_position?(transaction)
      open_position_class.find_by_transaction_id(transaction.id)
    end

    def self.btc_specie?(transaction)
      transaction.specie == :btc
    end
    # end: sought_transaction helpers

    validates :status, presence: true, inclusion: { in: statuses }
    validates :order_id, presence: true
    validates_presence_of :price, :value_to_use

    # Statuses:
    #   executing: The Bitex order has been placed, its id stored as order_id.
    #   setting: In process of cancelling the Bitex order and any other outstanding order in the other exchange.
    #   finalised: Successfully settled or finished executing.
    statuses.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    def finalise!
      order = self.class.order_class.find(order_id)
      canceled_or_completed?(order) ? do_finalize : do_cancel(order)
    end

    private

    # finalise! helpers
    def canceled_or_completed?(order)
      order.status == :cancelled || order.status == :completed
    end

    def do_finalize
      Robot.log(:info, "Opening: #{self.class.order_class.name} ##{order_id} finalised.")
      update!(status: 'finalised')
    end

    def do_cancel(order)
      Robot.log(:info, "Opening: #{self.class.order_class.name} ##{order_id} canceled.")
      order.cancel!
      update!(status: 'settling') unless settling?
    end
    # end: finalise! helpers
  end

  class CannotCreateFlow < StandardError; end
end
