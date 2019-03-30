module BitexBot
  # Stores all robot settings and state to be shared with other applications.
  class Store < ActiveRecord::Base
    def sync(maker_balance, taker_balance)
      with_log do
        update(
          maker_fiat: maker_balance.fiat.total, maker_crypto: maker_balance.crypto.total,
          taker_fiat: taker_balance.fiat.total, taker_crypto: taker_balance.crypto.total,
          log: Robot.logger.history.join("\n").truncate(1_000)
        )
      end
    end

    private

    def with_log
      Robot.log(:info, :bot, :sync_store, "#{self.class}: [#{summary_for(:maker)}, #{summary_for(:taker)}]")
      yield
      Robot.logger.clean
    end

    # @param [Symbol] market. <:maker|:taker>
    def summary_for(market)
      "{ #{market}: #{Robot.send(market).name}, "\
        "crypto: #{Robot.send(market).base.upcase} #{send("#{market}_crypto").to_d}, "\
        "fiat: #{Robot.send(market).quote.upcase} #{send("#{market}_fiat").to_d} }"\
    end
  end
end
