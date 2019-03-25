module BitexBot
  # Any arbitrage workflow has 2 stages, opening positions and then closing them.
  # The OpeningFlow stage places an order on maker market, detecting and storing all transactions spawn from that order as
  # Open positions.
  class OpeningFlow < ActiveRecord::Base
    extend Forwardable

    self.abstract_class = true

    scope :active, -> { where.not(status: :finalised) }
    scope :old_active, ->(threshold) { active.where('created_at < ?', threshold) }
    scope :recents, ->(threshold) { active.where('created_at >= ?', threshold) }

    # The updated config store as passed from the robot
    cattr_accessor :store

    def self.open_market(taker_balance, maker_balance, taker_orders, taker_transactions, maker_fee, taker_fee)
      unless enough_funds?(maker_balance, value_per_order)
        raise CannotCreateFlow,
              "Needed #{maker_specie_to_spend} #{value_per_order.truncate(8)} on maker to place this "\
              "#{trade_type} but you only have #{maker_specie_to_spend} #{maker_balance.truncate(8)}."
      end

      taker_amount, taker_safest_price = calc_taker_amount(taker_balance, maker_fee, taker_fee, taker_orders, taker_transactions)
      price = maker_price(taker_amount)

      create!(
        price: price,
        value_to_use: value_to_use,
        suggested_closing_price: taker_safest_price,
        status: :executing
      ).tap(&:place_orders)
    rescue StandardError => e
      raise CannotCreateFlow, e.message
    end

    # Flow will try to place an rolify orders team, but dont care if cant place anyone, in this case, only log these.
    def place_orders
      {
        first_tip: { price: price, amount: value_to_use * 0.5 },
        second_tip: { price: price_scale(0.01), amount: value_to_use * 0.25 },
        support: { price: price_scale(0.02), amount: value_to_use * 0.05 },
        informant: { price: price_scale(0.05), amount: value_to_use * 0.15 },
        final: { price: price_scale(0.1), amount: value_to_use * 0.05 }
      }.each do |order_role, order_data|
        place_order(order_role, order_data[:price], order_data[:amount])
      end
    end

    # @param role [Symbol]: OpeningOrder.roles
    # rubocop:disable Metrics/AbcSize
    def place_order(role, price, amount)
      Robot.with_cooldown do
        Robot.maker.place_order(trade_type, price, amount).tap do |order|
          Robot.log(
            :info,
            "Opening: Placed #{role} #{trade_type} ##{order.id}"\
            " by #{Robot.maker.base.upcase} #{amount} @ #{Robot.maker.quote.upcase} #{price}."
          )
          opening_orders.create(order_id: order.id, role: role, price: price, amount: amount)
        end
      end
    rescue StandardError => e
      Robot.log(
        :error,
        "#{e.message}."\
        " Opening: Fail place #{role} #{trade_type}"\
        " by #{Robot.maker.base.upcase} #{amount} @ #{Robot.maker.quote.upcase} #{price}."
      )
    end
    # rubocop:enable Metrics/AbcSize

    def resume
      opening_orders.where.not(status: :finalised).map(&:resume)
    end

    # Checks if you have necessary funds for the amount you want to execute in the order.
    #   If BuyOpeningFlow, they must be in relation to the amounts and crypto funds.
    #   If SellOpeningFlow, they must be in relation to the amounts and fiat funds.
    #
    # @param[BigDecimal] balance. Funds of the species corresponding to the Flow you wish to open.
    # @param [BigDecimal] amount. Order size to open.
    #
    # @return [Booolean]
    def self.enough_funds?(funds, amount)
      funds >= amount
    end

    # Calculates the size of the order and its best price in relation to the order size configured for the purchase and
    # for the sale and with taker market information.
    #
    # @param [BigDecimal] taker_balance. Its represent available amountn on crypto/fiat.
    # @param [BigDecimal] maker_fee.
    # @param [BigDecimal] taker_fee.
    # @param [Array<ApiWrapper::Order>] taker_orders. List of taker bids/asks.
    # @param [Array<ApiWrapper::Transaction>] taker_orders. List of taker transactions.
    #
    # @return [Array[BigDecimal, BigDecimal]]
    def self.calc_taker_amount(taker_balance, maker_fee, taker_fee, taker_orders, taker_transactions)
      value = value_needed(maker_fee, taker_fee)
      price = safest_price(taker_transactions, taker_orders, value)
      amount = remote_value_to_use(value, price)

      unless enough_funds?(taker_balance, amount)
        raise CannotCreateFlow,
              "Needed #{taker_specie_to_spend} #{amount.truncate(8)} on taker to close this "\
              "#{trade_type} position but you only have #{taker_specie_to_spend} #{taker_balance.truncate(8)}."
      end

      [amount, price]
    end

    def self.value_needed(maker_fee, taker_fee)
      (value_to_use + maker_plus(maker_fee)) / (1 - taker_fee / 100)
    end

    def self.maker_plus(fee)
      value_to_use * fee / 100
    end

    # Buys on maker market represent open positions, we mirror them locally so that we can plan on how to close them.
    # rubocop:disable Metrics/AbcSize
    def self.sync_positions
      threshold = open_position_class.last.try(:created_at)

      Robot.maker.trades.each do |trade|
        next unless sought_transaction?(trade, threshold)

        flow = find_by_order_id(trade.order_id)
        # Asume que cualquier referencia a una orden que no sea referenciada por un flujo de apertura
        # es una orden que no ha podido concretar su enlace con el flujo.
        # TODO entonces envio a cancelar esa orden
        next unless flow.present?

        Robot.log(
          :info,
          "Opening: #{self} ##{flow.id} on order_id #{trade.order_id} was hit for #{Robot.maker.base.upcase} #{trade.crypto}"\
          " @ #{Robot.maker.quote.upcase} #{trade.price}."
        )

        open_position_class.create!(
          transaction_id: trade.order_id, price: trade.price, amount: trade.fiat, quantity: trade.crypto, opening_flow: flow
        )
      end
    end
    # rubocop:enable Metrics/AbcSize

    # @param [ApiWrapper::UserTransaction] trade.
    # @param [Time] threshold.
    #
    # @return [Boolean]
    def self.sought_transaction?(trade, threshold)
      expected_kind_trade?(trade) && !active_trade?(trade, threshold) && !syncronized?(trade) && expected_orderbook?(trade)
    end

    # @param [ApiWrapper::UserTransaction] trade.
    # @param [Time] threshold.
    #
    # @return [Boolean]
    def self.active_trade?(trade, threshold)
      threshold.present? && trade.timestamp < (threshold - 30.minutes).to_i
    end

    # @param [ApiWrapper::UserTransaction] trade.
    #
    # @return [Boolean]
    def self.syncronized?(trade)
      # TODO: syncronizeds scope
      open_position_class.find_by_transaction_id(trade.order_id).present?
    end

    # @param [ApiWrapper::UserTransaction] trade.
    #
    # @return [Boolean]
    def self.expected_orderbook?(trade)
      trade.raw.orderbook_code.to_s == Robot.maker.base_quote
    end

    # Statuses:
    #   executing: The maker order has been placed, its id stored as order_id.
    #   settling: In process of cancelling the maker order and any other outstanding order in the taker exchange.
    #   finalised: Successfully settled or finished executing.
    enum status: %i[executing settling finalised]

    validates :status, presence: true, inclusion: { in: statuses }
    validates_presence_of :price, :value_to_use

    def finalise
      return if finalised?

      return finalised! if
        opening_orders.empty? ||
        opening_orders.all?(&:finalised?) ||
        opening_orders.each(&:finalise).all?(&:finalised?)

      settling! unless settling?
    end
  end

  class CannotCreateFlow < StandardError; end
end
