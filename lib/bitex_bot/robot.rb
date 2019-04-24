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
    cattr_accessor :logger
    cattr_accessor :notifier
    cattr_accessor :store
    def_delegator self, :store

    def self.setup
      self.logger = Logger.setup
      log(:info, :bot, :setup, 'Loading trading robot, ctrl+c *once* to exit gracefully.')

      self.notifier = Notifier if Settings.mailer.present?

      self.store =
        Store.first ||
        Store.create(
          fiat_warning: Settings.fiat_warning,
          crypto_warning: Settings.crypto_warning,
          fiat_stop: Settings.fiat_stop,
          crypto_stop: Settings.crypto_stop
        )

      self.maker = Settings.maker_class.new(Settings.maker_settings)
      self.taker = Settings.taker_class.new(Settings.taker_settings)

      new
    end

    # Trade constantly respecting cooldown times so that we don't get banned by api clients.
    def self.run!
      bot = setup
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

    def self.notify(*args)
      notifier.notify(*args)
    end

    def self.log(level, stage, step, details)
      logger.send(level, stage: stage, step: step, details: details)
    end
    def_delegator self, :log

    def self.with_cooldown
      yield.tap do
        self.current_cooldowns += 1
        sleep_for(0.1)
      end
    end
    def_delegator self, :with_cooldown

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def trade!
      sync_opening_flows if active_opening_flows?
      finalise_some_opening_flows
      shutdown! if shutdownable?
      start_closing_flows if open_positions?
      sync_closing_flows if active_closing_flows?

      return log(:debug, :bot, :trade, 'Not placing new orders, Store is hold') if store.hold?
      return log(:debug, :bot, :trade, 'Not placing new orders, has active closing flows.') if active_closing_flows?
      return log(:debug, :bot, :trade, 'Not placing new orders, shutting down.') if turn_off?

      start_opening_flows_if_needed
    rescue CannotCreateFlow => e
      notifier.notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 3)
    rescue Curl::Err::TimeoutError => e
      notifier.notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
      sleep_for(15)
    rescue Exchanges::OrderNotFound => e
      notifier.notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
    rescue StandardError => e
      notifier.notify("#{e.class} - #{e.message}\n\n#{e.backtrace.join("\n")}")
      sleep_for(60 * 2)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def active_closing_flows?
      [BuyClosingFlow, SellClosingFlow].map(&:active).any?(&:exists?)
    end

    def active_opening_flows?
      [BuyOpeningFlow, SellOpeningFlow].map(&:active).any?(&:exists?)
    end

    private

    def sync_opening_flows
      [BuyOpeningFlow, SellOpeningFlow].each(&:sync_positions)
    end

    def shutdownable?
      !(active_flows? || open_positions?) && turn_off?
    end

    def shutdown!
      log(:info, :bot, :shutdown, 'Shutdown completed')
      exit
    end

    def active_flows?
      active_opening_flows? || active_closing_flows?
    end

    def turn_off?
      self.class.graceful_shutdown
    end

    def finalise_some_opening_flows
      if turn_off?
        [BuyOpeningFlow, SellOpeningFlow].each { |kind| kind.active.each(&:finalise) }
      else
        threshold = Settings.time_to_live.seconds.ago.utc
        [BuyOpeningFlow, SellOpeningFlow].each { |kind| kind.old_active(threshold).each(&:finalise) }
      end
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

    def start_opening_flows_if_needed # rubocop:disable Metrics/AbcSize
      maker_balance = with_cooldown { maker.balance }
      taker_balance = with_cooldown { taker.balance }
      store.sync(maker_balance, taker_balance)
      store.check_balance_warning

      taker_market = with_cooldown { taker.market }
      taker_transactions = with_cooldown { taker.transactions }
      opening_flow_args = [taker_transactions, maker_balance.fee, taker_balance.fee]

      recent_buying, recent_selling = recent_openings

      if recent_buying.present?
        log(:debug, :bot, :trade, 'Not placing new orders, recent ones exist.')
      elsif !store.balance_stop?(:fiat)
        BuyOpeningFlow.open_market(*[taker_balance.crypto.available, taker_market.bids] + opening_flow_args)
      end

      if recent_selling.present?
        log(:debug, :bot, :trade, 'Not placing new orders, recent ones exist.')
      elsif !store.balance_stop?(:crypto)
        SellOpeningFlow.open_market(*[taker_balance.fiat.available, taker_market.asks] + opening_flow_args)
      end
    end

    def recent_openings
      threshold = (Settings.time_to_live / 2).seconds.ago.utc

      [BuyOpeningFlow, SellOpeningFlow].map { |kind| kind.recents(threshold).first }
    end
  end
end
