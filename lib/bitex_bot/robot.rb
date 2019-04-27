trap 'INT' do
  if BitexBot::Robot.graceful_shutdown
    print "\b"
    puts "Ok, ok, I'm out."
    exit 1
  end
  BitexBot::Robot.graceful_shutdown = true
  puts "Shutting down as soon as I've cleaned up."
end

module BitexBot
  # Documentation here!
  class Robot
    extend Forwardable

    cattr_accessor :taker
    cattr_accessor :maker

    cattr_accessor :graceful_shutdown
    cattr_accessor :cooldown_until
    cattr_accessor(:current_cooldowns) { 0 }
    cattr_accessor(:last_log) { [] }

    cattr_accessor(:logger) do
      logdev = Settings.log.try(:file)
      STDOUT.sync = true unless logdev.present?
      Logger.new(logdev || STDOUT, 10, 10_240_000).tap do |log|
        log.level = Logger.const_get(Settings.log.level.upcase)
        log.formatter = proc do |severity, datetime, _progname, msg|
          date = datetime.strftime('%m/%d %H:%M:%S.%L')
          "#{format('%-6s', severity)} #{date}: #{msg}\n"
        end
      end
    end

    def self.setup
      self.maker = Settings.maker_class.new(Settings.maker_settings)
      self.taker = Settings.taker_class.new(Settings.taker_settings)
    end

    # Trade constantly respecting cooldown times so that we don't get banned by api clients.
    def self.run!
      bot = start_robot
      self.cooldown_until = Time.now
      loop do
        start_time = Time.now
        next if start_time < cooldown_until

        self.current_cooldowns = 0
        bot.trade!
        self.cooldown_until = start_time + current_cooldowns.seconds
      end
    end

    def self.sleep_for(seconds)
      sleep(seconds)
    end
    def_delegator self, :sleep_for

    def self.log(level, message)
      last_log << "#{level.upcase} #{Time.now.strftime('%m/%d %H:%M:%S.%L')}: #{message}"
      logger.send(level, message)
    end
    def_delegator self, :log

    def self.with_cooldown
      yield.tap do
        self.current_cooldowns += 1
        sleep_for(0.1)
      end
    end
    def_delegator self, :with_cooldown

    def self.start_robot
      setup
      log(:info, "Loading trading robot, ctrl+c *once* to exit gracefully.\n")
      new
    end

    # rubocop:disable Metrics/AbcSize
    def trade!
      sync_opening_flows if active_opening_flows?
      finalise_some_opening_flows
      shutdown! if shutdable?
      start_closing_flows if open_positions?
      sync_closing_flows if active_closing_flows?
      start_opening_flows_if_needed
    rescue CannotCreateFlow => e
      notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 3)
    rescue Curl::Err::TimeoutError => e
      notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
      sleep_for(15)
    rescue OrderNotFound => e
      notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
    rescue ApiWrapperError => e
      notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
    rescue OrderArgumentError => e
      notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
    rescue StandardError => e
      notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 2)
    end
    # rubocop:enable Metrics/AbcSize

    def active_closing_flows?
      [BuyClosingFlow, SellClosingFlow].map(&:active).any?(&:exists?)
    end

    def active_opening_flows?
      [BuyOpeningFlow, SellOpeningFlow].map(&:active).any?(&:exists?)
    end

    # The trader has a Store
    def store
      @store ||= Store.first || Store.create
    end

    private

    def sync_opening_flows
      [SellOpeningFlow, BuyOpeningFlow].each(&:sync_positions)
    end

    def shutdable?
      !(active_flows? || open_positions?) && turn_off?
    end

    def shutdown!
      log(:info, 'Shutdown completed')
      exit
    end

    def active_flows?
      active_opening_flows? || active_closing_flows?
    end

    def turn_off?
      self.class.graceful_shutdown
    end

    def finalise_some_opening_flows
      [BuyOpeningFlow, SellOpeningFlow].each { |kind| active_flows(kind).each(&:finalise!) }
    end

    def active_flows(opening_flow_class)
      turn_off? ? opening_flow_class.active : opening_flow_class.old_active
    end

    def start_closing_flows
      [BuyClosingFlow, SellClosingFlow].each(&:close_market)
    end

    def open_positions?
      [OpenBuy, OpenSell].map(&:open).any?(&:exists?)
    end

    def sync_closing_flows
      [BuyClosingFlow, SellClosingFlow].each(&:sync_positions)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def start_opening_flows_if_needed
      return log(:debug, 'Not placing new orders, because Store is held') if store.reload.hold?
      return log(:debug, 'Not placing new orders, has active closing flows.') if active_closing_flows?
      return log(:debug, 'Not placing new orders, shutting down.') if turn_off?

      recent_buying, recent_selling = recent_operations
      return log(:debug, 'Not placing new orders, recent ones exist.') if recent_buying && recent_selling

      maker_balance = with_cooldown { maker.balance }
      taker_balance = with_cooldown { taker.balance }

      sync_log_and_store(maker_balance, taker_balance)
      log_balances('Store: Current balances.')

      check_balance_warning if expired_last_warning?
      return if stop_opening_flows?

      taker_market = with_cooldown { taker.market }
      taker_transactions = with_cooldown { taker.transactions }

      OpeningFlow.store = store
      args = [taker_transactions, maker_balance.fee, taker_balance.fee]

      BuyOpeningFlow.open_market(*[taker_balance.crypto.available, taker_market.bids] + args) unless recent_buying
      SellOpeningFlow.open_market(*[taker_balance.fiat.available, taker_market.asks] + args) unless recent_selling
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def recent_operations
      threshold = (Settings.time_to_live / 2).seconds.ago
      [BuyOpeningFlow, SellOpeningFlow].map { |kind| kind.active.where('created_at > ?', threshold).first }
    end

    # rubocop:disable Metrics/AbcSize
    def sync_log_and_store(maker_balance, taker_balance)
      log_balances('Store: Updating log, maker and taker balances...')
      last_log << "Last run: #{Time.now.utc}, Open Bids: #{BuyOpeningFlow.resume}, Open Asks: #{SellOpeningFlow.resume}."
      logs = last_log.join("\n")
      last_log.clear
      store.update(
        maker_fiat: maker_balance.fiat.total, maker_crypto: maker_balance.crypto.total,
        taker_fiat: taker_balance.fiat.total, taker_crypto: taker_balance.crypto.total,
        log: logs
      )
    end

    def log_balances(header)
      log(
        :info,
        "#{header}\n"\
        "Store: #{maker.name} maker - #{maker.base.upcase}: #{store.maker_crypto}, #{maker.quote.upcase}: #{store.maker_fiat}.\n"\
        "Store: #{taker.name} taker - #{taker.base.upcase}: #{store.taker_crypto}, #{taker.quote.upcase}: #{store.taker_fiat}.\n"
      )
    end
    # rubocop:enable Metrics/AbcSize

    def expired_last_warning?
      store.last_warning.nil? || store.last_warning < 30.minutes.ago
    end

    def stop_opening_flows?
      (log(:info, "Opening: Not placing new orders, #{maker.quote.upcase} target not met") if alert?(:fiat, :stop)) ||
        (log(:info, "Opening: Not placing new orders, #{maker.base.upcase} target not met") if alert?(:crypto, :stop))
    end

    def check_balance_warning
      notify_balance_warning(maker.base, balance(:crypto), store.crypto_warning) if alert?(:crypto, :warning)
      notify_balance_warning(maker.quote, balance(:fiat), store.fiat_warning) if alert?(:fiat, :warning)
    end

    def alert?(currency, flag)
      return unless store.send("#{currency}_#{flag}").present?

      balance(currency) <= store.send("#{currency}_#{flag}")
    end

    def balance(currency)
      fx_rate = currency == :fiat ? Settings.buying_fx_rate : 1
      store.send("maker_#{currency}") / fx_rate + store.send("taker_#{currency}")
    end

    def notify_balance_warning(currency, amount, warning_amount)
      notify("#{currency.upcase} balance is too low, it's #{amount}, make it #{warning_amount} to stop this warning.")
      store.update(last_warning: Time.now)
    end

    def notify(message, subj = 'Notice from your robot trader')
      log(:info, "Sending mail with subject: #{subj}\n\n#{message}")
      return unless Settings.mailer.present?

      new_mail(subj, message).tap do |mail|
        mail.delivery_method(Settings.mailer.delivery_method.to_sym, Settings.mailer.options.to_hash)
      end.deliver!
    end

    def new_mail(subj, message)
      Mail.new do
        from Settings.mailer.from
        to Settings.mailer.to
        subject subj
        body message
      end
    end
  end
end
