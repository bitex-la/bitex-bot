require "bitex_bot/version"
require 'hashie'
require "active_record"
require "mail"
require "logger"
require "bitex"
require "bitstamp"
require "itbit"
require 'bitfinex'
require "bitex_bot/settings"
require "bitex_bot/database"
require "bitex_bot/models/opening_flow.rb"
require "bitex_bot/models/closing_flow.rb"
Dir[File.dirname(__FILE__) + '/bitex_bot/models/*.rb'].each {|file| require file }
require "bitex_bot/robot"

module BitexBot
  def self.user_agent
    "Bitexbot/#{VERSION} (https://github.com/bitex-la/bitex-bot)"
  end
end

module Bitex
  module WithUserAgent
    def grab_curl
      super.tap do |curl|
        curl.headers['User-Agent'] = BitexBot.user_agent
      end
    end
  end

  class Api
    class << self
      prepend WithUserAgent
    end
  end
end

# Itbit and Bitstamp
module RestClient
  module WithUserAgent
    def default_headers
      super.merge(:user_agent => BitexBot.user_agent)
    end
  end

  class Request
    prepend WithUserAgent
  end
end
