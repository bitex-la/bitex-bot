# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bitex_bot/version'

Gem::Specification.new do |spec|
  spec.name          = "bitex_bot"
  spec.version       = BitexBot::VERSION
  spec.authors       = ["Nubis", "Eromirou"]
  spec.email         = ["nb@bitex.la", "tr@bitex.la"]
  spec.description   = %q{Both a trading robot and a library to build trading
                        robots. The bitex-bot lets you buy cheap on bitex and
                        sell on another exchange and vice versa.}
  spec.summary       = %q{A trading robot to do arbitrage between bitex.la and
                        other exchanges!}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  
  spec.add_dependency "settingslogic"
  spec.add_dependency "activerecord"
  spec.add_dependency "activesupport"
  spec.add_dependency "sqlite3"
  spec.add_dependency "bitstamp"
  spec.add_dependency "bitex", "0.1.9"
  spec.add_dependency "itbit", "0.0.3"
  spec.add_dependency "mail"
  spec.add_dependency "hashie"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-mocks"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "factory_girl"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "debugger"
  spec.add_development_dependency "shoulda-matchers"
end
