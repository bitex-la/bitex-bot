require 'bitex_bot/version'

# Utilities
require 'active_record'
require 'bigdecimal'
require 'bigdecimal/util'
require 'forwardable'
require 'hashie'
require 'logger'
require 'mail'

# Traders Platforms
require 'bitex'
require 'bitstamp'
require 'itbit'

# BitexBot Models
require 'bitex_bot/settings'
require 'bitex_bot/database'
require 'bitex_bot/logger'
require 'bitex_bot/notifier'

require 'bitex_bot/exchanges/exchange'
Dir[File.dirname(__FILE__) + '/bitex_bot/exchanges/*.rb'].each { |file| require file }

require 'bitex_bot/models/opening_flow'
require 'bitex_bot/models/sell_opening_flow'
require 'bitex_bot/models/buy_opening_flow'

require 'bitex_bot/models/opening_order'
require 'bitex_bot/models/opening_ask'
require 'bitex_bot/models/opening_bid'

require 'bitex_bot/models/closing_flow'
require 'bitex_bot/models/sell_closing_flow'
require 'bitex_bot/models/buy_closing_flow'

require 'bitex_bot/models/openable_trade'
require 'bitex_bot/models/open_buy'
require 'bitex_bot/models/open_sell'

require 'bitex_bot/models/closeable_trade'
require 'bitex_bot/models/close_buy'
require 'bitex_bot/models/close_sell'

require 'bitex_bot/models/orderbook_simulator'
require 'bitex_bot/models/store'
require 'bitex_bot/models/balance_checker'
require 'bitex_bot/models/stop_checker'
require 'bitex_bot/models/warning_checker'

require 'bitex_bot/robot'

# Get version and bitex-bot as user-agent
module BitexBot
  def self.user_agent
    "Bitexbot/#{VERSION} (https://github.com/bitex-la/bitex-bot)"
  end
end

module RestClient
  # On Itbit and Bitstamp, the mechanism to set bitex-bot user-agent are different.
  module WithUserAgent
    def default_headers
      super.merge(user_agent: BitexBot.user_agent)
    end
  end

  # Mixing to include request behaviour and set user-agent.
  class Request
    prepend WithUserAgent
  end
end
