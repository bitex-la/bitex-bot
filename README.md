# BitexBot

A robot to do arbitrage between bitex.la and other exchanges.

## Installation

Add this line to your application's Gemfile:

    gem 'bitex_bot'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install bitex_bot

## Usage

This software is provided as is, and it serves as an example to the
https://github.com/bitex-la/bitex-ruby API wrapper for bitex.

With that said, you can use this robot yourself to take advantage of price
differences between bitex and bitstamp.

Before you can start using this robot you need to have approved accounts in
https://bitex.la and https://bitstamp.net. Both accounts should have enough
BTC and USD as the robot will try to sell on bitex and buy on bitstamp
and to buy on bitex and sell on bitstamp.

This gem provides bitex_bot executable, it will create a config file on the first run.

Edit the config file to include your bitex and bitstmap api_keys, configure your
trading parameters and desired profit on successfull trades.

Optionally, configure your outgoing email credentials to receive emails when your
robot needs attention.

Once you're done, run bitex_bot again and it will start placing orders on bitex,
looking for opportunities to make a profit. Start with low amounts and then
start trading more as you become more comfortable with how the robot operates. 

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
