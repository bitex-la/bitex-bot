module BitexBot
  # Simulates hitting an order-book to find a price at which an order can be assumed to get executed completely.
  # It essentially drops the start of the order book, to account for price volatility (assuming those orders may be taken by
  # someone else), and then digs until the given USD amount or BTC quantity are reached, finally returning the last price seen,
  # which is the 'safest' price at which we can expect this order to get executed quickly.
  #
  class OrderBookSimulator
    # @param volatility [Integer] How many seconds of recent volume we need to skip from the start of the order book to be more
    #   certain that our order will get executed.
    # @param transactions [Hash] a list of hashes representing all transactions in the other exchange:
    #    Each hash contains 'date', 'tid', 'price' and 'amount', where 'amount' is the BTC transacted.
    # @param order_book [[price, quantity]] a list of lists representing the order book to dig in.
    # @param amount_target [BigDecimal] stop when this amount has been reached, leave as nil if looking for a quantity_target.
    # @param quantity_target [BigDecimal] stop when this quantity has been reached, leave as nil if looking for an
    #   amount_target.
    # @return [Decimal] Returns the price that we're more likely to get when executing an order for the given amount or
    #   quantity.
    #
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.run(volatility, taker_transactions, taker_orderbook, amount_target, quantity_target, fx_rate = 1)
      to_skip = estimate_quantity_to_skip(volatility, taker_transactions)
      Robot.log(:debug, "Skipping #{to_skip} #{Robot.taker.base.upcase}")
      seen = 0

      taker_orderbook.each do |order_summary|
        price = order_summary.price
        quantity = order_summary.quantity

        # An order may be partially or completely skipped due to volatility.
        if to_skip.positive?
          dropped = [quantity, to_skip].min
          to_skip -= dropped
          quantity -= dropped
          Robot.log(:debug, "Skipped #{dropped} #{Robot.taker.base.upcase} @ #{Robot.taker.quote.upcase} #{price}")
          next if quantity.zero?
        end

        if quantity_target.present?
          return best_price(Robot.maker.base.upcase, quantity_target, price) if best_price?(quantity, quantity_target, seen)

          seen += quantity
        elsif amount_target.present?
          amount = price * quantity
          return best_price(Robot.maker.quote.upcase, amount_target * fx_rate, price) if best_price?(amount, amount_target, seen)

          seen += amount
        end
      end
      taker_orderbook.last.price
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # private class methods

    def self.estimate_quantity_to_skip(volatility, transactions)
      threshold = transactions.first.timestamp - volatility
      transactions
        .select { |t| t.timestamp > threshold }
        .map(&:amount)
        .sum
    end

    def self.best_price?(volume, target, seen)
      volume >= (target - seen)
    end

    def self.best_price(currency, target, price)
      price.tap { Robot.log(:debug, "Best price to get #{currency} #{target} is #{Robot.taker.quote.upcase} #{price}") }
    end

    # end: private class methods
  end
end
