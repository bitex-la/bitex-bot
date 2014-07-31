module BitexBot
  # A workflow for selling bitcoin in Bitex and buying on another exchange.  The
  # SellOpeningFlow factory function estimates how much you could buy on the other
  # exchange and calculates a reasonable price taking into account the remote
  # orderbook and the recent operated volume.
  #
  # When created, a SellOpeningFlow places an Ask on Bitex for the calculated
  # quantity and price, when the Ask is matched on Bitex an OpenSell is
  # created to buy the same quantity for a lower price on the other exchange.
  #
  # A SellOpeningFlow can be cancelled at any point, which will cancel the Bitex
  # order and any orders on the remote exchange created from its OpenSell's
  # 
  # @attr order_id The first thing a SellOpeningFlow does is placing an Ask on Bitex,
  #   this is its unique id. 
  class SellOpeningFlow < OpeningFlow
    
    # Start a workflow for selling bitcoin on bitex and buying on the other
    # exchange. The quantity to be sold on bitex is retrieved from Settings, if
    # there is not enough BTC on bitex or USD on the other exchange then no
    # order will be placed and an exception will be raised instead.
    # The amount a SellOpeningFlow will try to sell and the price it will try to
    # charge are derived from these parameters:
    # 
    # @param usd_balance [BigDecimal] amount of usd available in the other
    #   exchange that can be spent to balance this sale.
    # @param order_book [[price, quantity]] a list of lists representing an ask
    #   order book in the other exchange.
    # @param transactions [Hash] a list of hashes representing
    #   all transactions in the other exchange. Each hash contains 'date', 'tid',
    #   'price' and 'amount', where 'amount' is the BTC transacted.
    # @param bitex_fee [BigDecimal] the transaction fee to pay on bitex.
    # @param other_fee [BigDecimal] the transaction fee to pay on the other
    #   exchange.
    #
    # @return [SellOpeningFlow] The newly created flow.
    # @raise [CannotCreateFlow] If there's any problem creating this flow, for
    #   example when you run out of BTC on bitex or out of USD on the other
    #   exchange.
    def self.create_for_market(usd_balance, order_book, transactions,
      bitex_fee, other_fee)
      super
    end
    
    def self.open_position_class
      OpenSell
    end
    
    def self.transaction_class
      Bitex::Sell
    end
    
    def self.transaction_order_id(transaction)
      transaction.ask_id
    end

    def self.order_class
      Bitex::Ask
    end

    def self.value_to_use
      Settings.selling.quantity_to_sell_per_order
    end
    
    def self.get_safest_price(transactions, order_book, bitcoins_to_use)
      OrderBookSimulator.run(Settings.time_to_live, transactions,
        order_book, nil, bitcoins_to_use)
    end
      
    def self.get_remote_value_to_use(value_to_use_needed, safest_price)
      value_to_use_needed * safest_price
    end
    
    def self.get_bitex_price(btc_to_sell, usd_to_spend_re_buying) 
     (usd_to_spend_re_buying / btc_to_sell) * (1 + Settings.selling.profit / 100.0)
    end
  end
end
