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
    cattr_accessor :logger do
      Logger.new(Settings.log.file || STDOUT, 10, 10240000).tap do |l|
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
        return if start_time < cooldown_until
        self.current_cooldowns = 0
        bot.trade!
        self.cooldown_until = start_time + current_cooldowns.seconds
      end
    end
    
    def self.setup
      Bitex.api_key = Settings.bitex
      Bitstamp.setup do |config|
        config.key = Settings.bitstamp.key
        config.secret = Settings.bitstamp.secret
        config.client_id = Settings.bitstamp.client_id.to_s
      end
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
      finalise_some_opening_flows
      if(!active_opening_flows? && !open_positions? &&
        !active_closing_flows? && self.class.graceful_shutdown)
        self.class.logger.info("Shutdown completed")
        exit
      end
      sync_opening_flows if active_opening_flows?
      start_closing_flows if open_positions?
      sync_closing_flows if active_closing_flows?
      start_opening_flows_if_needed
    rescue CannotCreateFlow => e
      self.notify("#{e.message}:\n\n#{e.backtrace.join("\n")}")
      BitexBot::Robot.graceful_shutdown = true
    rescue StandardError => e
      self.notify("#{e.message}:\n\n#{e.backtrace.join("\n")}")
      sleep 30 unless self.class.test_mode
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
      orders = with_cooldown{ Bitstamp.orders.all }
      transactions = with_cooldown{ Bitstamp.user_transactions.all }

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
      return if open_positions?
      return if active_closing_flows?
      return if self.class.graceful_shutdown
      
      
      recent_buying, recent_selling =
        [BuyOpeningFlow, SellOpeningFlow].collect do |kind|
          threshold = (Settings.time_to_live / 2).seconds.ago
          kind.active.where('created_at > ?', threshold).first
        end

      return if recent_buying && recent_selling
      
      balances = with_cooldown{ Bitstamp.balance }
      order_book = with_cooldown{ Bitstamp.order_book }
      transactions = with_cooldown{ Bitstamp.transactions }
      
      unless recent_buying
        BuyOpeningFlow.create_for_market(
          balances['btc_available'].to_d,
          order_book['bids'],
          transactions,
          Bitex::Profile.get[:fee],
          balances['fee'].to_d )
      end
      unless recent_selling
        SellOpeningFlow.create_for_market(
          balances['usd_available'].to_d,
          order_book['asks'],
          transactions,
          Bitex::Profile.get[:fee],
          balances['fee'].to_d )
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
  end
end
