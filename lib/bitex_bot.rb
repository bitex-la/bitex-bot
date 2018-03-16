require 'bitex_bot/version'

# Utilities
require 'active_record'
require 'bigdecimal'
require 'bigdecimal/util'
require 'hashie'
require 'logger'
require 'mail'

# Traders Platforms
require 'bitex'
require 'bitstamp'
require 'itbit'
require 'bitfinex'

# BitexBot Models
require 'bitex_bot/settings'
require 'bitex_bot/database'
require 'bitex_bot/models/api_wrappers/api_wrapper.rb'
Dir[File.dirname(__FILE__) + '/bitex_bot/models/api_wrappers/**/*.rb'].each { |file| require file }
require 'bitex_bot/models/opening_flow.rb'
require 'bitex_bot/models/closing_flow.rb'
Dir[File.dirname(__FILE__) + '/bitex_bot/models/*.rb'].each { |file| require file }
require 'bitex_bot/robot'

# #
# Get version and bitex-bot as user-agent
#
module BitexBot
  class << self
    def user_agent
      "Bitexbot/#{VERSION} (https://github.com/bitex-la/bitex-bot)"
    end
  end
end

module Bitex
  # #
  # Set bitex-bot user-agent on request.
  #
  module WithUserAgent
    def grab_curl
      super.tap do |curl|
        curl.headers['User-Agent'] = BitexBot.user_agent
      end
    end
  end

  ##
  # Mixing to include request behaviour and set user-agent.
  #
  class Api
    class << self
      prepend WithUserAgent
    end
  end
end

module RestClient
  # #
  # On Itbit and Bitstamp, the mechanism to set bitex-bot user-agent are different.
  #
  module WithUserAgent
    def default_headers
      super.merge(user_agent: BitexBot.user_agent)
    end
  end

  ##
  # Mixing to include request behaviour and set user-agent.
  #
  class Request
    prepend WithUserAgent
  end
end
