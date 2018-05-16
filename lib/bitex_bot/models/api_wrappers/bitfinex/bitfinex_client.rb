##
# Open Bitfinex gem module.
#
module Bitfinex
  ##
  # Set User Agen into Bitfinex gem.
  module WithUserAgent
    def new_rest_connection
      super.tap { |conn| conn.headers['User-Agent'] = BitexBot.user_agent }
    end
  end

  ##
  # Open Bitfinex Client to preprend user agent.
  class Client
    prepend WithUserAgent
  end
end
