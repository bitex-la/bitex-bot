module BitexBot
  # Simulates hitting an order-book to find a price at which an order can be assumed to get executed completely.
  # It essentially drops the start of the orderbook, to account for price volatility (assuming those orders may be taken by
  # someone else), and then digs until the given FIAT amount or CRYPTO quantity are reached, finally returning the last price
  # seen, which is the 'safest' price at which we can expect this order to get executed quickly.
  class OrderbookSimulator
    # @param volatility [Integer] How many seconds of recent volume we need to skip from the start of the order book to be more
    #   certain that our order will get executed.
    # @param transactions [ApiWrapper::Transaction] a list of hashes representing all transactions in the taker market:
    # @param orders [ApiWrapper::Order] a list of lists representing the orderbook to dig in.
    # @param amount_target [BigDecimal] stop when this amount has been reached, leave as nil if looking for a quantity_target.
    # @param quantity_target [BigDecimal] stop when this quantity has been reached, leave as nil if looking for an
    #   amount_target.
    # @return [BigDecimal] Returns the price that we're more likely to get when executing an order for the given amount or
    #   quantity.
    #
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.run(volatility, taker_transactions, taker_orderbook, amount_target, quantity_target, fx_rate = 1)
      to_skip = estimate_quantity_to_skip(volatility, taker_transactions)
      seen = 0

      taker_orderbook.each do |order_summary|
        price = order_summary.price
        quantity = order_summary.quantity

        # An order may be partially or completely skipped due to volatility.
        if to_skip.positive?
          dropped = [quantity, to_skip].min
          to_skip -= dropped
          quantity -= dropped
          log("Skipped #{Robot.taker.base.upcase} #{dropped} @ #{Robot.taker.quote.upcase} #{price}")
          next if quantity.zero?
        end

        if quantity_target.present?
          if best_price?(quantity, quantity_target, seen)
            log("To get #{Robot.maker.base.upcase} #{quantity_target}, best price is #{Robot.taker.quote.upcase} #{price}")
            return price
          end

          seen += quantity
        elsif amount_target.present?
          amount = price * quantity
          if best_price?(amount, amount_target, seen)
            log("To get #{Robot.maker.quote} #{amount_target * fx_rate}, best price is #{Robot.taker.quote} #{price}")
            return price
          end

          seen += amount
        end
      end
      taker_orderbook.last.price
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def self.estimate_quantity_to_skip(volatility, transactions)
      threshold = transactions.first.timestamp - volatility
      transactions
        .select { |t| t.timestamp > threshold }
        .sum(&:amount)
        .tap { |to_skip| log("Skipping #{Robot.taker.base.upcase} #{to_skip}") }
    end

    def self.best_price?(volume, target, seen)
      volume >= (target - seen)
    end

    def self.log(details)
      Robot.log(:debug, :opening, :safest_price, details)
    end

    private_class_method :estimate_quantity_to_skip, :best_price?, :log
  end
end
