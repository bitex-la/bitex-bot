# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bitex_bot/version'

Gem::Specification.new do |spec|
  spec.name          = 'bitex_bot'
  spec.version       = BitexBot::VERSION
  spec.authors       = %w[Nubis Eromirou]
  spec.email         = %w[nb@bitex.la tr@bitex.la]
  spec.description   = %q[Both a trading robot and a library to build trading robots. The bitex-bot lets you buy cheap
                        on bitex and sell on another exchange and vice versa.]
  spec.summary       = %q[A trading robot to do arbitrage between bitex.la and other exchanges!]
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r[^bin/]) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r[^(test|spec|features)/])
  spec.require_paths = %w[lib]

  spec.add_dependency 'activerecord', '~> 4.2'
  spec.add_dependency 'sqlite3'
  spec.add_dependency 'bitstamp'
  spec.add_dependency 'bitex', '0.3'
  spec.add_dependency 'itbit', '0.0.6'
  spec.add_dependency 'bitfinex-rb', '0.0.6'
  spec.add_dependency 'kraken_client', '~> 1.2.1'
  spec.add_dependency 'mail'
  spec.add_dependency 'hashie', '~> 3.5.4'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-mocks'
  spec.add_development_dependency 'database_cleaner'
  spec.add_development_dependency 'factory_bot'
  spec.add_development_dependency 'timecop'
  spec.add_development_dependency 'shoulda-matchers'
  spec.add_development_dependency 'webmock'
end
