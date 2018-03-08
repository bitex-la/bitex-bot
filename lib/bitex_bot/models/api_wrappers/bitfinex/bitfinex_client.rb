##
# Documentation here!

module Bitfinex
  ##
  # Documentation here!
  module WithUserAgent
    def new_rest_connection
      super.tap do |conn|
        conn.headers['User-Agent'] = BitexBot.user_agent
      end
    end
  end

  ##
  # Documentation here!
  class Client
    prepend WithUserAgent
  end
end
