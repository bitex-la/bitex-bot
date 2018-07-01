require 'spec_helper'

describe BitexBot::Settings do
  describe '#to_hash' do
    it 'returns a symbolized hash' do
      described_class.to_hash.should eq(
        log: { file: 'bitex_bot.log', level: :info },
        time_to_live: 20,
        buying: { amount_to_spend_per_order: 10, profit: 0.5 },
        selling: { quantity_to_sell_per_order: 0.1, profit: 0.5 },
        buying_foreign_exchange_rate: 1,
        selling_foreign_exchange_rate: 1,

        maker: { bitex: { api_key: 'your_bitex_api_key_which_should_be_kept_safe', order_book: :btc_usd, sandbox: false } },
        # By default Bitstamp is taker market.
        taker: { bitstamp: { api_key: 'YOUR_API_KEY', secret: 'YOUR_API_SECRET', client_id: 'YOUR_BITSTAMP_USERNAME' } },

        database: { adapter: :sqlite3, database: 'bitex_bot.db' },
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
        }
      )
    end

    context 'buying foreign exchange rate' do
      context 'when Store isn´t loaded' do
        it 'by default' do
          described_class.buying_fx_rate.should eq(1)
        end
      end

      context 'when Store is loaded' do
        before(:each) do
          BitexBot::Store.stub(first: BitexBot::Store.new )
          BitexBot::Store.any_instance.stub(buying_fx_rate: buying_fx_rate)
        end

        let(:buying_fx_rate) { rand(10) }

        it 'take rate from it' do
          described_class.buying_fx_rate.should eq(buying_fx_rate)
        end
      end
    end

    context 'maker' do
      {
        bitex: { api_key: 'your_bitex_api_key_which_should_be_kept_safe', order_book: :btc_usd, sandbox: false }
      }.each do |market, market_settings|
        before(:each) { described_class.stub(taker: BitexBot::SettingsClass.new(taker_hash)) }

        let(:taker_hash) { { market => market_settings } }

        context "for #{market}" do
          it { described_class.taker.to_hash.should eq(taker_hash) }
        end
      end
    end

    context 'taker' do
      {
        bitstamp: { api_key: 'YOUR_API_KEY', secret: 'YOUR_API_SECRET', client_id: 'YOUR_BITSTAMP_USERNAME' },
        itbit: { client_key: 'client-key', secret: 'secret', user_id: 'user-id',  default_wallet_id: 'wallet-000', sandbox: false },
        kraken: { api_key: 'your_api_key', api_secret: 'your_api_secret' }
      }.each do |market, market_settings|
        before(:each) { described_class.stub(taker: BitexBot::SettingsClass.new(taker_hash)) }

        let(:taker_hash) { { market => market_settings } }
        let(:taker_class) { "#{market.capitalize}ApiWrapper".constantize }

        context "for #{market}" do
          it { described_class.taker.to_hash.should eq(taker_hash) }
          it { described_class.taker_class.should eq(taker_class) }
        end
      end
    end

    context 'currencies by default' do
      let(:order_book) { described_class.maker.bitex.order_book.to_s }
      let(:base) { order_book.split('_')[0] }
      let(:quote) { order_book.split('_')[1] }

      it { described_class.base.should eq(base) }
      it { described_class.quote.should eq(quote) }
    end
  end
end
