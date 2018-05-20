require 'hashie'
require 'bigdecimal'
require 'bigdecimal/util'

module BitexBot
  ##
  # Documentation here!
  #
  class FileSettings < ::Hashie::Clash
    # rubocop:disable Style/MethodMissing
    def method_missing(name, *args)
      return super unless args.size == 1 && args.none?
      self[name] = args.first
    end
    # rubocop:enable Style/MethodMissing
  end

  ##
  # This class load settings file, else write a sample file.
  #
  class SettingsClass < ::Hashie::Mash
    include ::Hashie::Extensions::Mash::SymbolizeKeys

    def load_default
      path = ARGV[0] || 'bitex_bot_settings.rb'
      show_sample(path) unless FileTest.exists?(path)
      load_settings(path)
    end

    def load_test
      load_settings(sample_path)
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
  end

  Settings = SettingsClass.new
end
