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
require 'bitex_bot/models/api_wrappers/api_wrapper.rb'
Dir[File.dirname(__FILE__) + '/bitex_bot/models/api_wrappers/**/*.rb'].each { |file| require file }
require 'bitex_bot/models/opening_flow.rb'
require 'bitex_bot/models/closing_flow.rb'
Dir[File.dirname(__FILE__) + '/bitex_bot/models/*.rb'].each { |file| require file }
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
