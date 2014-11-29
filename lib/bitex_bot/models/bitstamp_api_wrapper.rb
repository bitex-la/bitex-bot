class BitstampApiWrapper
  def self.setup(settings)
    Bitstamp.setup do |config|
      config.key = settings.bitstamp.key
      config.secret = settings.bitstamp.secret
      config.client_id = settings.bitstamp.client_id.to_s
    end
  end

  #{
  #  tid:i,
  #  date: (i+1).seconds.ago.to_i.to_s,
  #  price: price.to_s,
  #  amount: amount.to_s
  #}
  def self.transactions
    Bitstamp.transactions
  end
  
  #  { 'timestamp' => DateTime.now.to_i.to_s,
  #    'bids' =>
  #      [['30', '3'], ['25', '2'], ['20', '1.5'], ['15', '4'], ['10', '5']],
  #    'asks' =>
  #      [['10', '2'], ['15', '3'], ['20', '1.5'], ['25', '3'], ['30', '3']]
  #  }
  def self.order_book(retries = 20)
    begin
      Bitstamp.order_book
    rescue StandardError => e
      if retries == 0
        raise
      else
        BitexBot::Robot.logger.info("Bitstamp order_book failed, retrying #{retries} more times")
        sleep 1
        self.order_book(retries - 1)
      end
    end
  end

  # {"btc_balance"=> "10.0", "btc_reserved"=> "0", "btc_available"=> "10.0",
  # "usd_balance"=> "100.0", "usd_reserved"=>"0", "usd_available"=> "100.0",
  # "fee"=> "0.5000"}
  def self.balance
    Bitstamp.balance
  end

  # ask = double(amount: args[:amount], price: args[:price],
  #   type: 1, id: remote_id, datetime: DateTime.now.to_s)
  # ask.stub(:cancel!) do
  def self.orders
    Bitstamp.orders.all
  end

  # double(usd: (usd * ratio).to_s, btc: (btc * ratio).to_s,
  #   btc_usd: o.price.to_s, order_id: o.id, fee: "0.5", type: 2,
  #   datetime: DateTime.now.to_s)
  def self.user_transactions
    Bitstamp.user_transactions.all
  end
  
  def self.order_is_done?(order)
    order.nil?
  end
  
  def self.amount_and_quantity(order_id, transactions)
    closes = transactions.select{|t| t.order_id.to_s == order_id}
    amount = closes.collect{|x| x.usd.to_d }.sum.abs
    quantity = closes.collect{|x| x.btc.to_d }.sum.abs
    [amount, quantity]
  end
  
  def self.place_order(type, price, quantity)
    Bitstamp.orders.send(type, amount: quantity, price: price)
  end
end
