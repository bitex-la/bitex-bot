module BitexBot
  # Use Store for check balances warning flag.
  class WarningChecker < BalanceChecker
    def self.alert(*args)
      super(*args)
      store.touch(:last_warning)
    end

    def self.alert_message(currency_type)
      "#{currency_type.upcase} balance is too low, "\
        "it's #{store.send("maker_#{currency_type}")}, "\
        "make it #{store.send("#{currency_type}_warning")} to stop this warning."
    end

    def self.balance_flag_for(currency_type)
      balance_flag = store.send("#{currency_type}_warning")
      balance_flag /= Settings.buying_fx_rate if currency_type == :fiat

      balance_flag
    end

    def self.log_step
      :warning
    end
  end
end
