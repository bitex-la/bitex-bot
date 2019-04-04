module BitexBot
  # Use Store for check balances flag.
  class BalanceChecker
    def self.alert?(currency_type)
      total_balance_for(currency_type) <= balance_flag_for(currency_type)
    end

    def self.alert(currency_type)
      msg = alert_message(currency_type)
      Robot.notify(msg)
      Robot.log(:info, :store, log_step, msg)
    end

    def self.store
      Robot.store
    end

    def self.total_balance_for(currency_type)
      maker_balance = store.send("maker_#{currency_type}")
      maker_balance /= Settings.buying_fx_rate if currency_type == :fiat

      maker_balance + store.send("taker_#{currency_type}")
    end
  end
end
