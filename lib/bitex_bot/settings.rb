require 'hashie'
require 'bigdecimal'
require 'bigdecimal/util'

module BitexBot
  # Documentation here!
  class FileSettings < ::Hashie::Clash
    def method_missing(name, *args, &block)
      return super unless args.none? && args.size == 1
      self[name] = args.first
    end

    def respond_to_missing?(method_name, include_private = false)
      respond_to?(method_name) || super
    end
  end

  # This class load settings file, else write a sample file.
  class SettingsClass < ::Hashie::Mash
    include ::Hashie::Extensions::Mash::SymbolizeKeys

    def load_test
      load_settings(sample_path)
    end

    def load_default
      path = ARGV[0] || 'bitex_bot_settings.rb'
      show_sample(path) unless FileTest.exists?(path)
      load_settings(path)
    end

    def buying_fx_rate
      Store.first.try(:buying_fx_rate) || buying_foreign_exchange_rate
    end

    def selling_fx_rate
      Store.first.try(:selling_fx_rate) || selling_foreign_exchange_rate
    end

    def base
      order_book_currencies[:base]
    end

    def quote
      order_book_currencies[:quote]
    end

    def maker_class
      exchange_class(maker)
    end

    def taker_class
      exchange_class(taker)
    end

    def maker_settings
      exchange_settings(maker)
    end

    def taker_settings
      exchange_settings(taker)
    end

    private

    def load_settings(path)
      file_settings = FileSettings.new
      file_settings.instance_eval(File.read(path), path, 1)
      merge!(file_settings)
    end

    def sample_path
      File.expand_path('../../settings.rb.sample', __dir__)
    end

    def show_sample(path)
      FileUtils.cp(sample_path, path)
      puts "No settings found, I've created a new one with sample values at #{path}. "\
        'Please go ahead and edit it before running this again.'
      exit 1
    end

    def order_book_currencies
      {}.tap { |currencies| currencies[:base], currencies[:quote] = maker_settings.order_book.to_s.split('_') }
    end

    def exchange_name(exchange)
      exchange.keys.pop
    end

    def exchange_class(exchange)
      "#{exchange_name(exchange).capitalize}ApiWrapper".constantize
    end

    def exchange_settings(exchange)
      exchange.send(exchange_name(exchange))
    end
  end

  Settings = SettingsClass.new
end
