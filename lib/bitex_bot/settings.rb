require 'hashie'

module BitexBot
  class FileSettings < ::Hashie::Clash
    def method_missing(name, *args)
      return super unless args.size == 1 && args.none?
      self[name] = args.first
    end
  end

  class SettingsClass < ::Hashie::Mash
    include ::Hashie::Extensions::Mash::SymbolizeKeys

    def load_default
      path = ARGV[0] || 'bitex_bot_settings.rb'
      unless FileTest.exists?(path)
        sample_path = File.expand_path('../../../settings.rb.sample', __FILE__)
        FileUtils.cp(sample_path, path)
        puts "No settings found, I've created a new one with sample "\
          "values at #{path}. Please go ahead and edit it before running this again."
        exit 1
      end
      load_settings(path)
    end
    
    def load_test
      load_settings File.expand_path('../../../settings.rb.sample', __FILE__)
    end

    def load_settings(path)
      file_settings = FileSettings.new
      file_settings.instance_eval(File.read(path), path, 1)
      merge!(file_settings)
    end
  end

  Settings = SettingsClass.new
end
