require 'spec_helper'

describe BitexBot::Store do
  before(:each) do
    allow(BitexBot::Robot).to receive(:logger).and_return(BitexBot::Logger.setup)

    allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('maker_crypto')
    allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('maker_fiat')

    allow(BitexBot::Robot).to receive_message_chain(:taker, :base).and_return('taker_crypto')
    allow(BitexBot::Robot).to receive_message_chain(:taker, :quote).and_return('taker_fiat')

    allow(BitexBot::Robot).to receive_message_chain(:maker, :name).and_return('maker_name')
    allow(BitexBot::Robot).to receive_message_chain(:taker, :name).and_return('taker_name')
  end

  subject(:store) { create(:store) }

  describe 'valid factory' do
    its(:maker_fiat) { is_expected.to be_zero }
    its(:maker_crypto) { is_expected.to be_zero }
    its(:taker_fiat) { is_expected.to be_zero }
    its(:taker_crypto) { is_expected.to be_zero }

    its(:crypto_stop) { is_expected.to be_nil }
    its(:crypto_warning) { is_expected.to be_nil }
    its(:fiat_stop) { is_expected.to be_nil }
    its(:fiat_warning) { is_expected.to be_nil }

    its(:buying_amount_to_spend_per_order) { is_expected.to be_nil }
    its(:buying_fx_rate) { is_expected.to be_nil }
    its(:buying_profit) { is_expected.to be_nil }

    its(:selling_quantity_to_sell_per_order) { is_expected.to be_nil }
    its(:selling_fx_rate) { is_expected.to be_nil }
    its(:selling_profit) { is_expected.to be_nil }

    its(:hold) { is_expected.to be_falsey }
    its(:log) { is_expected.to be_nil }
    its(:last_warning) { is_expected.to be_nil }
  end

  describe '#sync' do
    let(:maker_balance) { build_bitex_balance_summary({ total: 100, available: 30 }, { total: 200, available: 60 }, 0.5) }
    let(:taker_balance) { build_bitex_balance_summary({ total: 300, available: 90 }, { total: 400, available: 120 }, 0.75) }

    it do
      expect { subject.sync(maker_balance, taker_balance) }
        .to change(subject, :maker_fiat).from(0).to(60)
        .and change(subject, :maker_crypto).from(0).to(30)
        .and change(subject, :taker_fiat).from(0).to(120)
        .and change(subject, :taker_crypto).from(0).to(90)
    end
  end

  describe '#summary_for' do
    it do
      expect(subject.send(:summary_for, :maker))
        .to eq('{ maker: maker_name, crypto: MAKER_CRYPTO 0.0, fiat: MAKER_FIAT 0.0 }')
    end
  end
end
