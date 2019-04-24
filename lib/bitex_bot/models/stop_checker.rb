module BitexBot
  # Use Store for check balances stop flag.
  class StopChecker < BalanceChecker
    def self.alert_message(currency_type)
      "Not placing new orders, #{currency_code(currency_type)} target not met."
    end

    def self.currency_code(currency_type)
      { fiat: Robot.maker.quote, crypto: Robot.maker.base }[currency_type]
    end

    def self.balance_flag_for(currency_type)
      balance_flag = store.send("#{currency_type}_stop")
      balance_flag /= Settings.buying_fx_rate if currency_type == :fiat

      balance_flag
    end

    def self.log_step
      :stop
    end
  end
end
