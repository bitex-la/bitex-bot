require "bitex_bot/version"
require "active_support"
require "active_record"
require "active_model"
require "mail"
require "logger"
require "bitex"
require "bitstamp"
require "bitex_bot/settings"
require "bitex_bot/database"
require "bitex_bot/models/opening_flow.rb"
require "bitex_bot/models/closing_flow.rb"
Dir[File.dirname(__FILE__) + '/bitex_bot/models/*.rb'].each {|file| require file }
require "bitex_bot/robot"

module BitexBot
end
