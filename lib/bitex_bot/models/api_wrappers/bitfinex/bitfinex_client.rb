module Bitfinex
  module WithUserAgent
    def new_rest_connection
      super.tap do |conn|
        conn.headers['User-Agent'] = BitexBot.user_agent
      end
    end
  end

  class Client
    prepend WithUserAgent
  end
end
