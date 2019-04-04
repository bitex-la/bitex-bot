require 'spec_helper'

describe BitexBot::StopChecker do
  describe '.alert?' do
    shared_examples_for 'for currency type' do |currency_type|
      before(:each) do
        allow(described_class).to receive(:total_balance_for).with(currency_type).and_return(total_balance.to_d)
        allow(described_class).to receive(:balance_flag_for).with(currency_type).and_return(balance_flag.to_d)
      end

      subject { described_class.alert?(currency_type) }

      let(:balance_flag) { 100 }

      context 'total balance greather than balance flag' do
        let(:total_balance) { 200 }

        it { is_expected.to be_falsey }
      end

      context 'total balance is lower or equal than balance flag' do
        let(:total_balance) { 100 }

        it { is_expected.to be_truthy }
      end
    end

    it_behaves_like 'for currency type', :crypto
    it_behaves_like 'for currency type', :fiat
  end

  describe '.alert' do
    shared_examples_for 'for currency type' do |currency_type|
      before(:each) { allow(described_class).to receive(:alert_message).with(currency_type).and_return('alert msg') }

      it do
        expect(BitexBot::Robot).to receive(:log).with(:info, :store, :stop, 'alert msg')
        expect(BitexBot::Robot).to receive(:notify).with('alert msg')

        described_class.alert(currency_type)
      end
    end

    it_behaves_like 'for currency type', :crypto
    it_behaves_like 'for currency type', :fiat
  end

  describe '.alert_message' do
    before(:each) do
      allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('maker_base')
      allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('maker_quote')
    end

    shared_examples_for 'for currency type' do |currency_type, currency_code|
      subject(:message) { described_class.alert_message(currency_type) }

      it { is_expected.to eq("Not placing new orders, #{currency_code} target not met.") }

      describe '.currency_code' do
        subject(:code) { described_class.currency_code(currency_type) }

        it { is_expected.to eq(currency_code) }
      end
    end

    it_behaves_like 'for currency type', :fiat, 'MAKER_QUOTE'
    it_behaves_like 'for currency type', :crypto, 'MAKER_BASE'
  end

  describe '.balance_flag_for' do
    before(:each) { allow(described_class).to receive(:store).and_return(store) }

    subject(:balance) { described_class.balance_flag_for(currency_type) }

    context 'for fiat type' do
      before(:each) { allow(BitexBot::Settings).to receive(:buying_fx_rate).and_return(2.to_d) }

      let(:store) { create(:store, fiat_stop: 200) }
      let(:currency_type) { :fiat }

      it { is_expected.to eq(100) }
    end

    context 'for crypto type' do
      let(:store) { create(:store, crypto_stop: 200) }
      let(:currency_type) { :crypto }

      it { is_expected.to eq(200) }
    end
  end

  it '.log_step' do
    expect(described_class.log_step).to eq(:stop)
  end
end
