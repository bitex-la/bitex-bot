trap 'INT' do
  if BitexBot::Robot.graceful_shutdown
    print "\b"
    BitexBot::Robot.log(:info, "Ok, ok, I'm out.")
    exit 1
  end
  BitexBot::Robot.graceful_shutdown = true
  BitexBot::Robot.log(:info, "Shutting down as soon as I've cleaned up.")
end

module BitexBot
  ##
  # Documentation here!
  #
  # rubocop:disable Metrics/ClassLength
  class Robot
    cattr_accessor(:orderbook) { Settings.bitex.orderbook }
    cattr_accessor(:base_coin) { orderbook.to_s.split('_')[0].upcase }
    cattr_accessor(:quote_coin) { orderbook.to_s.split('_')[1].upcase }

    cattr_accessor :cooldown_until
    cattr_accessor(:current_cooldowns) { 0 }
    cattr_accessor :graceful_shutdown
    cattr_accessor :logger do
      logdev = Settings.log.try(:file)
      STDOUT.sync = true unless logdev.present?
      Logger.new(logdev || STDOUT, 10, 10_240_000).tap do |log|
        log.level = Logger.const_get(Settings.log.level.upcase)
        # rubocop:disable Lint/UnusedBlockArgument
        log.formatter = proc do |severity, datetime, progname, msg|
          date = datetime.strftime('%m/%d %H:%M:%S.%L')
          "#{format('%-6s', severity)} #{date}: #{msg}\n"
        end
        # rubocop:enable Lint/UnusedBlockArgument
      end
    end
    cattr_accessor(:taker) { "#{Settings.taker.capitalize}ApiWrapper".constantize }

    def self.setup
      Bitex.api_key = Settings.bitex.api_key
      Bitex.sandbox = Settings.sandbox
      taker.setup(Settings)
    end

    def self.fx_rate
      Settings.fx_rate
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

        # This global sleep is so that we don't stress bitex too much.
        sleep_for(0.3)
        self.cooldown_until = start_time + current_cooldowns.seconds
      end
    end

    def self.sleep_for(seconds)
      sleep(seconds)
    end

    def self.log(level, message)
      logger.send(level, message)
    end

    def self.with_cooldown
      yield.tap do
        self.current_cooldowns += 1
        sleep_for(0.1)
      end
    end

    # private class methods

    def self.start_robot
      setup
      log(:info, 'Loading trading robot, ctrl+c *once* to exit gracefully.')
      new
    end

    # end: private class methods

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def trade!
      sync_opening_flows if active_opening_flows?
      finalise_some_opening_flows
      shutdown! if shutdable?
      start_closing_flows if open_positions?
      sync_closing_flows if active_closing_flows?
      start_opening_flows_if_needed
    rescue CannotCreateFlow => e
      notify("#{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 3)
    rescue Curl::Err::TimeoutError => e
      log(:error, "#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep_for(15)
    rescue OrderNotFound => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
    rescue ApiWrapperError => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
    rescue OrderArgumentError => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
    rescue StandardError => e
      notify("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 2)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def active_closing_flows?
      [BuyClosingFlow.active, SellClosingFlow.active].any?(&:exists?)
    end

    def active_opening_flows?
      [BuyOpeningFlow.active, SellOpeningFlow.active].any?(&:exists?)
    end

    # The trader has a Store
    def store
      @store ||= Store.first || Store.create
    end

    private

    def with_cooldown(&block)
      self.class.with_cooldown(&block)
    end

    def sync_opening_flows
      [SellOpeningFlow, BuyOpeningFlow].each(&:sync_open_positions)
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
      [BuyClosingFlow, SellClosingFlow].each(&:close_open_positions)
    end

    def open_positions?
      [OpenBuy.open, OpenSell.open].any?(&:exists?)
    end

    def sync_closing_flows
      orders = with_cooldown { BitexBot::Robot.taker.orders }
      transactions = with_cooldown { BitexBot::Robot.taker.user_transactions }

      [BuyClosingFlow, SellClosingFlow].each do |kind|
        kind.active.each { |flow| flow.sync_closed_positions(orders, transactions) }
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def start_opening_flows_if_needed
      return log(:debug, 'Not placing new orders because of hold') if store.reload.hold?
      return log(:debug, 'Not placing new orders, closing flows.') if active_closing_flows?
      return log(:debug, 'Not placing new orders, shutting down.') if turn_off?

      recent_buying, recent_selling = recent_operations
      return log(:debug, 'Not placing new orders, recent ones exist.') if [recent_buying, recent_selling].all?(&:present?)

      balance = with_cooldown { BitexBot::Robot.taker.balance }
      profile = Bitex::Profile.get
      total_usd = balance.usd.total + profile[:usd_balance]
      total_btc = balance.btc.total + profile[:btc_balance]

      sync_log(balance)
      check_balance_warning(total_usd, total_btc) if expired_last_warning?
      return log(:debug, "Not placing new orders, #{base_coin} target not met") if usd_target_met?(total_usd)
      return log(:debug, "Not placing new orders, #{quote_coin} target not met") if btc_target_met?(total_btc)

      order_book = with_cooldown { BitexBot::Robot.taker.order_book }
      transactions = with_cooldown { BitexBot::Robot.taker.transactions }

      create_buy_opening_flow(balance, order_book, transactions, profile) if recent_buying.nil?
      create_sell_opening_flow(balance, order_book, transactions, profile) if recent_selling.nil?
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def recent_operations
      [BuyOpeningFlow, SellOpeningFlow].map { |kind| kind.active.where('created_at > ?', threshold).first }
    end

    def threshold
      (Settings.time_to_live / 2).seconds.ago
    end

    def sync_log(balance)
      file = Settings.log.try(:file)
      last_log = `tail -c 61440 #{file}` if file.present?
      store.update(taker_usd: balance.usd.total, taker_btc: balance.btc.total, log: last_log)
    end

    def expired_last_warning?
      store.last_warning.nil? || store.last_warning < 30.minutes.ago
    end

    def check_balance_warning(total_usd, total_btc)
      notify_balance_warning(:usd, total_usd, store.usd_warning) if balance_warning_notify?(:usd, total_usd)
      notify_balance_warning(:btc, total_btc, store.btc_warning) if balance_warning_notify?(:btc, total_btc)
    end

    def balance_warning_notify?(currency, total)
      warning = "#{currency}_warning"
      store.send(warning).present? && total <= store.send(warning)
    end

    def usd_target_met?(total)
      store.usd_stop.present? && total <= store.usd_stop
    end

    def btc_target_met?(total)
      store.btc_stop.present? && total <= store.btc_stop
    end

    def notify_balance_warning(currency, total, currency_warning)
      notify("#{currency.upcase} balance is too low, it's #{total}, make it #{currency_warning} to stop this warning.")
      store.update(last_warning: Time.now)
    end

    def notify(message, subj = 'Notice from your robot trader')
      log(:error, message)
      return unless Settings.mailer.present?
      mail = new_mail(subj, message)
      mail.delivery_method(Settings.mailer.delivery_method.to_sym, Settings.mailer.options.to_hash)
      mail.deliver!
    end

    def new_mail(subj, message)
      Mail.new do
        from Settings.mailer.from
        to Settings.mailer.to
        subject subj
        body message
      end
    end

    def create_buy_opening_flow(balance, order_book, transactions, profile)
      BuyOpeningFlow.create_for_market(balance.btc.available, order_book.bids, transactions, profile[:fee], balance.fee, store)
    end

    def create_sell_opening_flow(balance, order_book, transactions, profile)
      SellOpeningFlow.create_for_market(balance.usd.available, order_book.asks, transactions, profile[:fee], balance.fee, store)
    end

    def sleep_for(seconds)
      self.class.sleep_for(seconds)
    end

    def log(level, message)
      self.class.log(level, message)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
