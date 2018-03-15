trap 'INT' do
  if BitexBot::Robot.graceful_shutdown
    print "\b"
    BitexBot::Robot.logger.info("Ok, ok, I'm out.")
    exit 1
  end
  BitexBot::Robot.graceful_shutdown = true
  BitexBot::Robot.logger.info("Shutting down as soon as I've cleaned up.")
end

module BitexBot
  ##
  # Documentation here!
  #
  # rubocop:disable Metrics/ClassLength
  class Robot
    cattr_accessor :graceful_shutdown
    cattr_accessor :cooldown_until
    cattr_accessor(:taker) { "#{Settings.taker.capitalize}ApiWrapper".constantize }
    cattr_accessor(:current_cooldowns) { 0 }
    cattr_accessor :logger do
      logdev = Settings.log.try(:file)
      STDOUT.sync = true unless logdev.present?
      Logger.new(logdev || STDOUT, 10, 10_240_000).tap do |log|
        log.level = Logger.const_get(Settings.log.level.upcase)
        log.formatter = proc do |severity, datetime, msg|
          date = datetime.strftime('%m/%d %H:%M:%S.%L')
          "#{'%-6s' % severity} #{date}: #{msg}\n"
        end
      end
    end

    class << self
      # Trade constantly respecting cooldown times so that we don't get banned by api clients.
      def run!
        bot = start_robot

        cooldown_until = Time.now
        loop do
          start_time = Time.now
          next if start_time < cooldown_until
          current_cooldowns = 0
          bot.trade!

          # This global sleep is so that we don't stress bitex too much.
          sleep_for(0.3)
          cooldown_until = start_time + current_cooldowns.seconds
        end
      end

      def start_robot
        setup
        logger.info('Loading trading robot, ctrl+c *once* to exit gracefully.')
        new
      end

      def setup
        Bitex.api_key = Settings.bitex
        Bitex.sandbox = Settings.sandbox
        taker.setup(Settings)
      end

      def sleep_for(seconds)
        sleep(seconds)
      end

      def with_cooldown
        result = yield
        self.current_cooldowns += 1
        sleep_for(0.1)
        result
      end
    end

    def with_cooldown(&block)
      self.class.with_cooldown(&block)
    end

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
      self.class.logger.error("#{e.class} - #{e.message}:\n\n#{e.backtrace.join("\n")}")
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

    def active_opening_flows?
      [BuyOpeningFlow.active, SellOpeningFlow.active].any?(&:exists?)
    end

    def sync_opening_flows
      [SellOpeningFlow, BuyOpeningFlow].each(&:sync_open_positions)
    end

    def shutdable?
      !(active_flows? || open_positions?) && turn_off?
    end

    def shutdown!
      self.class.logger.info('Shutdown completed')
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

    def active_closing_flows?
      [BuyClosingFlow.active, SellClosingFlow.active].any?(&:exists?)
    end

    def start_opening_flows_if_needed
      return simple_log(:debug, 'Not placing new orders because of hold') if store.reload.hold?
      return simple_log(:debug, 'Not placing new orders, closing flows.') if active_closing_flows?
      return simple_log(:debug, 'Not placing new orders, shutting down.') if self.class.graceful_shutdown

      recent_buying, recent_selling = recent_operations
      return simple_log(:debug, 'Not placing new orders, recent ones exist.') if recent_buying && recent_selling

      balance = with_cooldown { BitexBot::Robot.taker.balance }
      profile = Bitex::Profile.get
      total_usd = balance.usd.total + profile[:usd_balance]
      total_btc = balance.btc.total + profile[:btc_balance]

      file = Settings.log.try(:file)
      last_log = `tail -c 61440 #{file}` if file.present?
      store.update(taker_usd: balance.usd.total, taker_btc: balance.btc.total, log: last_log)

      if expired_last_warning?
        if store.usd_warning && total_usd <= store.usd_warning
          notify("USD balance is too low, it's #{total_usd}, make it #{store.usd_warning} to stop this warning.")
          store.update_attributes(last_warning: Time.now)
        end

        if store.btc_warning && total_btc <= store.btc_warning
          notify("BTC balance is too low, it's #{total_btc}, ake it #{store.btc_warning} to stop this warning.")
          store.update_attributes(last_warning: Time.now)
        end
      end


      return simple_log(:debug, 'Not placing new orders, USD target not met') if store.usd_stop && total_usd <= store.usd_stop
      return simple_log(:debug, 'Not placing new orders, BTC target not met') if store.btc_stop && total_btc <= store.btc_stop

      order_book = with_cooldown { BitexBot::Robot.taker.order_book }
      transactions = with_cooldown { BitexBot::Robot.taker.transactions }

      unless recent_buying
        BuyOpeningFlow.create_for_market(
          balance.btc.available,
          order_book.bids,
          transactions,
          profile[:fee],
          balance.fee,
          store
        )
      end

      unless recent_selling
        SellOpeningFlow.create_for_market(
          balance.usd.available,
          order_book.asks,
          transactions,
          profile[:fee],
          balance.fee,
          store
        )
      end
    end

    def simple_log(level, message)
      BitexBot::Robot.logger.send(level, message)
    end

    def recent_operations
      [BuyOpeningFlow, SellOpeningFlow].map do |kind|
        threshold = (Settings.time_to_live / 2).seconds.ago
        kind.active.where('created_at > ?', threshold).first
      end
    end

    def expired_last_warning?
      store.last_warning.nil? || store.last_warning < 30.minutes.ago
    end

    def notify(message, subj = 'Notice from your robot trader')
      self.class.logger.error(message)
      return unless Settings.mailer.present?
      mail = Mail.new do
        from Settings.mailer.from
        to Settings.mailer.to
        subject subj
        body message
      end

      mail.delivery_method(Settings.mailer.delivery_method.to_sym, Settings.mailer.options.to_hash)
      mail.deliver!
    end

    # The trader has a Store
    def store
      @store ||= Store.first || Store.create
    end

    def sleep_for(seconds)
      self.class.sleep_for(seconds)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
