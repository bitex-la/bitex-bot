# Simulates hitting an order-book to find a price at which an order can be
# assumed to get executed completely.
# It essentially drops the start of the order book, to account for price
# volatility (assuming those orders may be taken by someone else), and then
# digs until the given USD amount or BTC quantity are reached, finally returning
# the last price seen, which is the 'safest' price at which we can expect this
# order to get executed quickly.
class BitexBot::OrderBookSimulator

  # @param volatility [Integer] How many seconds of recent volume we need to
  #   skip from the start of the order book to be more certain that our order
  #   will get executed.
  # @param transactions [Hash] a list of hashes representing
  #   all transactions in the other exchange. Each hash contains 'date', 'tid',
  #   'price' and 'amount', where 'amount' is the BTC transacted.
  # @param order_book [[price, quantity]] a list of lists representing the
  #   order book to dig in.
  # @param amount_target [BigDecimal] stop when this amount has been reached,
  #   leave as nil if looking for a quantity_target.
  # @param quantity_target [BigDecimal] stop when this quantity has been
  #   reached, leave as nil if looking for an amount_target.
  # @return [Decimal] Returns the price that we're more likely to get when
  #   executing an order for the given amount or quantity.
  def self.run(volatility, transactions, order_book, amount_target, quantity_target)
    to_skip = estimate_quantity_to_skip(volatility, transactions)
    BitexBot::Robot.logger.debug("Skipping #{to_skip} BTC")
    seen = 0
    safest_price = 0

    order_book.each do |order_summary|
      price, quantity = order_summary.price, order_summary.quantity

      # An order may be partially or completely skipped due to volatility.
      if to_skip > 0
        dropped = [quantity, to_skip].min
        to_skip -= dropped
        quantity -= dropped
        BitexBot::Robot.logger.debug("Skipped #{dropped} BTC @ $#{price}")
        next if quantity == 0
      end

      if quantity_target
        if quantity >= (quantity_target - seen)
          BitexBot::Robot.logger.debug("Best price to get #{quantity_target} BTC is $#{price}")
          return price
        else
          seen += quantity
        end
      elsif amount_target
        amount = price * quantity
        if amount >= (amount_target - seen)
          BitexBot::Robot.logger.debug("Best price to get $#{amount_target} is $#{price}")
          return price
        else
          seen += amount
        end
      end
    end

    order_book.last.price
  end

  private

  def self.estimate_quantity_to_skip(volatility, transactions)
    threshold = transactions.first.timestamp - volatility
    transactions
      .select { |t| t.timestamp > threshold }
      .collect { |t| t.amount.to_d }
      .sum
  end
end
