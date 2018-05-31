require 'spec_helper'

describe BitexBot::Settings do
  describe '#to_hash' do
    it 'returns a symbolized hash' do
      BitexBot::Settings.to_hash.should eq({
        bitex: { api_key: 'your_bitex_api_key_which_should_be_kept_safe', order_book: :btc_usd },
        fx_rate: 1.to_d,
        bitstamp: { api_key: 'YOUR_API_KEY', secret: 'YOUR_API_SECRET', client_id: 'YOUR_BITSTAMP_USERNAME' },
        buying: { amount_to_spend_per_order: 10.to_d, profit: 0.5.to_d },
        database: { adapter: :sqlite3, database: 'bitex_bot.db' },
        itbit: { client_key: 'the-client-key', secret: 'the-secret', user_id: 'the-user-id', default_wallet_id: 'wallet-000' },
        kraken: { api_key: 'your_api_key', api_secret: 'your_api_secret' },
        log: { file: 'bitex_bot.log', level: :info },
        mailer: {
          from: 'robot@example.com',
          to: 'you@example.com',
          delivery_method: :smtp,
          options: {
            address: 'your_smtp_server_address.com',
            port: 587,
            authentication: 'plain',
            enable_starttls_auto: true,
            user_name: 'your_user_name',
            password: 'your_smtp_password'
          }
        },
        sandbox: false,
        selling: { quantity_to_sell_per_order: 0.1.to_d, profit: 0.5.to_d },
        taker: 'bitstamp',
        time_to_live: 20
      })
    end
  end
end
