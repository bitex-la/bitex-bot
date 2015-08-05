trap "INT" do
  if BitexBot::Robot.graceful_shutdown
    print "\b"
    BitexBot::Robot.logger.info("Ok, ok, I'm out.")
    exit 1
  end
  BitexBot::Robot.graceful_shutdown = true
  BitexBot::Robot.logger.info("Shutting down as soon as I've cleaned up.")
end

module BitexBot
  class Robot
    cattr_accessor :graceful_shutdown
    cattr_accessor :cooldown_until
    cattr_accessor :test_mode
    cattr_accessor :taker do
      Settings.taker == 'itbit' ? ItbitApiWrapper : BitstampApiWrapper
    end
    cattr_accessor :logger do
      Logger.new(Settings.log.try(:file) || STDOUT, 10, 10240000).tap do |l|
        l.level = Logger.const_get(Settings.log.level.upcase)
        l.formatter = proc do |severity, datetime, progname, msg|
          date = datetime.strftime("%m/%d %H:%M:%S.%L")
          "#{ '%-6s' % severity } #{date}: #{msg}\n"
        end
      end
    end
    cattr_accessor :current_cooldowns do 0 end
    
    # Trade constantly respecting cooldown times so that we don't get
    # banned by api clients.
    def self.run!
      setup
      logger.info("Loading trading robot, ctrl+c *once* to exit gracefully.")
      self.cooldown_until = Time.now
      bot = new
      
      while true
        start_time = Time.now
        next if start_time < cooldown_until
        self.current_cooldowns = 0
        bot.trade!
        # This global sleep is so that we don't stress bitex too much.
        sleep 0.3 unless test_mode
        self.cooldown_until = start_time + current_cooldowns.seconds
      end
    end
    
    def self.setup
      Bitex.api_key = Settings.bitex
      Bitex.sandbox = Settings.sandbox
      taker.setup(Settings)
    end
  
    def self.with_cooldown(&block)
      result = block.call
      return result if test_mode
      self.current_cooldowns += 1
      sleep 0.1 
      return result
    end

    def with_cooldown(&block)
      self.class.with_cooldown(&block)
    end

    def trade!
      sync_opening_flows if active_opening_flows?
      finalise_some_opening_flows
      if(!active_opening_flows? && !open_positions? &&
        !active_closing_flows? && self.class.graceful_shutdown)
        self.class.logger.info("Shutdown completed")
        exit
      end
      start_closing_flows if open_positions?
      sync_closing_flows if active_closing_flows?
      start_opening_flows_if_needed
    rescue CannotCreateFlow => e
      self.notify("#{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep (60 * 3) unless self.class.test_mode
    rescue StandardError => e
      self.notify("#{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep 60 unless self.class.test_mode
    end
    
    def finalise_some_opening_flows
      [BuyOpeningFlow, SellOpeningFlow].each do |kind|
        flows = self.class.graceful_shutdown ? kind.active : kind.old_active
        flows.each{|flow| flow.finalise! }
      end
    end
    
    def start_closing_flows
      [BuyClosingFlow, SellClosingFlow].each{|kind| kind.close_open_positions}
    end

    def open_positions?
      OpenBuy.open.exists? || OpenSell.open.exists?
    end
    
    def sync_closing_flows
      orders = with_cooldown{ BitexBot::Robot.taker.orders }
      transactions = with_cooldown{ BitexBot::Robot.taker.user_transactions }

      [BuyClosingFlow, SellClosingFlow].each do |kind|
        kind.active.each do |flow|
          flow.sync_closed_positions(orders, transactions)
        end
      end
    end
    
    def active_closing_flows?
      BuyClosingFlow.active.exists? || SellClosingFlow.active.exists?
    end
    
    def start_opening_flows_if_needed
      if store.reload.hold?
        BitexBot::Robot.logger.debug("Not placing new orders because of hold")
        return
      end
      
      if active_closing_flows?
        BitexBot::Robot.logger.debug("Not placing new orders, closing flows.")
        return
      end
      
      if self.class.graceful_shutdown
        BitexBot::Robot.logger.debug("Not placing new orders, shutting down.")
        return
      end
      
      recent_buying, recent_selling =
        [BuyOpeningFlow, SellOpeningFlow].collect do |kind|
          threshold = (Settings.time_to_live / 2).seconds.ago
          kind.active.where('created_at > ?', threshold).first
        end

      if recent_buying && recent_selling
        BitexBot::Robot.logger.debug("Not placing new orders, recent ones exist.")
        return
      end
      
      balances = with_cooldown{ BitexBot::Robot.taker.balance }
      profile = Bitex::Profile.get
      
      total_usd = balances['usd_balance'].to_d + profile[:usd_balance]
      total_btc = balances['btc_balance'].to_d + profile[:btc_balance]
      
      last_log = `tail -c 61440 #{Settings.log.try(:file)}` if Settings.log.try(:file)
  
      store.update_attributes(taker_usd: balances['usd_balance'],
        taker_btc: balances['btc_balance'], log: last_log)
      
      if store.last_warning.nil? || store.last_warning < 30.minutes.ago 
        if store.usd_warning && total_usd <= store.usd_warning
          notify("USD balance is too low, it's #{total_usd},"\
            "make it #{store.usd_warning} to stop this warning.")
          store.update_attributes(last_warning: Time.now)
        end

        if store.btc_warning && total_btc <= store.btc_warning
          notify("BTC balance is too low, it's #{total_btc},"\
            "make it #{store.btc_warning} to stop this warning.")
          store.update_attributes(last_warning: Time.now)
        end
      end

      if store.usd_stop && total_usd <= store.usd_stop
        BitexBot::Robot.logger.debug("Not placing new orders, USD target not met")
        return
      end
      if store.btc_stop && total_btc <= store.btc_stop
        BitexBot::Robot.logger.debug("Not placing new orders, BTC target not met")
        return
      end

      order_book = with_cooldown{ BitexBot::Robot.taker.order_book }
      transactions = with_cooldown{ BitexBot::Robot.taker.transactions }
      
      unless recent_buying
        BuyOpeningFlow.create_for_market(
          balances['btc_available'].to_d,
          order_book['bids'],
          transactions,
          profile[:fee],
          balances['fee'].to_d,
          store)
      end
      unless recent_selling
        SellOpeningFlow.create_for_market(
          balances['usd_available'].to_d,
          order_book['asks'],
          transactions,
          profile[:fee],
          balances['fee'].to_d,
          store)
      end
    end
    
    def sync_opening_flows
      [SellOpeningFlow, BuyOpeningFlow].each{|o| o.sync_open_positions }
    end
    
    def active_opening_flows?
      BuyOpeningFlow.active.exists? || SellOpeningFlow.active.exists?
    end
    
    def notify(message)
      self.class.logger.error(message)
      if Settings.mailer
        mail = Mail.new do
          from Settings.mailer.from
          to Settings.mailer.to
          subject 'Notice from your robot trader'
          body message
        end
        mail.delivery_method(Settings.mailer.method.to_sym,
          Settings.mailer.options.symbolize_keys)
        mail.deliver!
      end
    end

    # The trader has a Store
    def store
      @store ||= Store.first || Store.create
    end
  end
end
