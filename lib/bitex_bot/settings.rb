require 'settingslogic'
require 'debugger'
class BitexBot::Settings < Settingslogic
  path = File.expand_path('bitex_bot_settings.yml', Dir.pwd)
  unless FileTest.exists?(path)
    sample_path = File.expand_path('../../../settings.yml.sample', __FILE__)
    FileUtils.cp(sample_path, path)
    puts "No settings found, I've created a new one with sample "\
      "values at #{path}. Please go ahead and edit it before running this again."
    exit 1
  end
  source path
end
