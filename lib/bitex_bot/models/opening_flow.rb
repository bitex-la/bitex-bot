module BitexBot
  # Any arbitrage workflow has 2 stages, opening positions and then closing them.
  # The OpeningFlow stage places an order on bitex, detecting and storing all transactions spawn from that order as
  # Open positions.
  class OpeningFlow < ActiveRecord::Base
    self.abstract_class = true

    # The updated config store as passed from the robot
    cattr_accessor :store

    class << self
      def active
        where('status != "finalised"')
      end

      def old_active
        where('status != "finalised" AND created_at < ?', Settings.time_to_live.seconds.ago)
      end

      # @!group Statuses

      # All possible flow statuses
      # @return [Array<String>]
      def statuses
        %w[executing settling finalised]
      end

      # rubocop:disable Metrics/AbcSize
      def create_for_market(remote_balance, order_book, transactions, bitex_fee, other_fee, store)
        self.store = store

        remote_value, safest_price = calc_remote_value(bitex_fee, other_fee, order_book, transactions)
        raise(CannotCreateFlow, "Needed #{remote_value} but you only have #{remote_balance}") if remote_value > remote_balance

        bitex_price = bitex_price(value_to_use, remote_value)
        order = create_order!(bitex_price)
        raise(CannotCreateFlow, "You need to have #{value_to_use} on bitex to place this #{order_class.name}.") unless
          enough_funds?(order)

        Robot.logger
             .info("Opening: Placed #{order_class.name} ##{order.id} #{value_to_use} @ $#{bitex_price} (#{remote_value})")

        create!(
          price: bitex_price,
          value_to_use: value_to_use,
          suggested_closing_price: safest_price,
          status: 'executing',
          order_id: order.id
        )
      rescue StandardError => e
        raise(CannotCreateFlow, e.message)
      end
      # rubocop:enable Metrics/AbcSize

      def calc_remote_value(bitex_fee, other_fee, order_book, transactions)
        value_to_use_needed = plus_bitex(bitex_fee) / (1 - other_fee / 100.0)
        safest_price = safest_price(transactions, order_book, value_to_use_needed)
        [remote_value_to_use(value_to_use_needed, safest_price), safest_price]
      end

      def plus_bitex(fee)
        value_to_use + (value_to_use * fee / 100.0)
      end

      def bitex_price(_value_to_use, _remote_value)
        raise 'self subclass responsibility'
      end

      def create_order!(bitex_price)
        order_class.create!(:btc, value_to_use, bitex_price, true)
      rescue StandardError => e
        raise(CannotCreateFlow, e.message)
      end

      def enough_funds?(order)
        order.reason != :not_enough_funds
      end

      # Buys on bitex represent open positions, we mirror them locally so that we can plan on how to close them.
      def sync_open_positions
        threshold = open_position_class.order('created_at DESC').first.try(:created_at)
        Bitex::Trade.all.map do |transaction|
          next if sought_transaction?(threshold, transaction)
          flow = find_by_order_id(transaction_order_id(transaction))
          next unless flow.present?

          create_open_position!(transaction, flow)
        end.compact
      end

      def sought_transaction?(threshold, transaction)
        !transaction.is_a?(transaction_class) ||
          active_transaction?(transaction, threshold) ||
          open_position?(transaction) ||
          !btc_specie?(transaction)
      end

      def active_transaction?(transaction, threshold)
        threshold && transaction.created_at < (threshold - 30.minutes)
      end

      def open_position?(transaction)
        open_position_class.find_by_transaction_id(transaction.id)
      end

      def btc_specie?(transaction)
        transaction.specie == :btc
      end

      def create_open_position!(transaction, flow)
        Robot.logger.info("Opening: #{name} ##{flow.id} was hit for #{transaction.quantity} BTC @ $#{transaction.price}")
        open_position_class.create!(
          transaction_id: transaction.id,
          price: transaction.price,
          amount: transaction.amount,
          quantity: transaction.quantity,
          opening_flow: flow
        )
      end
    end

    # The Bitex order has been placed, its id stored as order_id.
    def executing?
      status == 'executing'
    end

    # In process of cancelling the Bitex order and any other outstanding order in the other exchange.
    def settling?
      status == 'settling'
    end

    # Successfully settled or finished executing.
    def finalised?
      status == 'finalised'
    end
    # @!endgroup

    validates :status, presence: true, inclusion: { in: statuses }
    validates :order_id, presence: true
    validates_presence_of :price, :value_to_use

    def finalise!
      order = self.class.order_class.find(order_id)
      canceled_or_completed?(order) ? do_finalize : do_cancel(order)
    end

    private

    def canceled_or_completed?(order)
      order.status == :cancelled || order.status == :completed
    end

    def do_finalize
      Robot.logger.info("Opening: #{self.class.order_class.name} ##{order_id} finalised.")
      update!(status: 'finalised')
    end

    def do_cancel(order)
      order.cancel!
      update!(status: 'settling') unless settling?
    end
  end

  class CannotCreateFlow < StandardError; end
end
