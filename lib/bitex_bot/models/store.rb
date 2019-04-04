module BitexBot
  # Stores all robot settings and state to be shared with other applications.
  class Store < ActiveRecord::Base
    def sync(maker_balance, taker_balance)
      Robot.log(:info, :bot, :sync_store, sync_msg)
      update(
        maker_fiat: maker_balance.fiat.total, maker_crypto: maker_balance.crypto.total,
        taker_fiat: taker_balance.fiat.total, taker_crypto: taker_balance.crypto.total,
        log: Robot.logger.history.join("\n").truncate(1_000)
      )
      Robot.logger.clean
    end

    def check_balance_warning
      return unless expired_last_warning?

      WarningChecker.alert(:fiat) if WarningChecker.alert?(:fiat)
      WarningChecker.alert(:crypto) if WarningChecker.alert?(:crypto)
    end

    def balance_stop?(currency)
      StopChecker.alert(currency) if StopChecker.alert?(currency)
    end

    private

    def sync_msg
      "#{self.class}: [#{summary_for(:maker)}, #{summary_for(:taker)}]"
    end

    # @param [Symbol] market. <:maker|:taker>
    def summary_for(market_role)
      "{ #{market_role}: #{Robot.send(market_role).name}, "\
        "crypto: #{Robot.send(market_role).base.upcase} #{send("#{market_role}_crypto").to_d}, "\
        "fiat: #{Robot.send(market_role).quote.upcase} #{send("#{market_role}_fiat").to_d} }"\
    end

    def expired_last_warning?
      last_warning.nil? || last_warning < Settings.store_expire_warning.minutes.ago.utc
    end
  end
end
