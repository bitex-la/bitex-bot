require 'spec_helper'

describe BitexBot::WarningChecker do
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
      before(:each) do
        Timecop.freeze(old_date) do
          allow(described_class)
            .to receive(:store)
            .and_return(create(:store, last_warning: Time.now.utc))
        end

        allow(described_class).to receive(:alert_message).with(currency_type).and_return('alert msg')
      end

      let(:old_date) { 3.days.ago.utc }

      it do
        expect(described_class.store.last_warning).to eq(old_date)

        expect(BitexBot::Robot).to receive(:log).with(:info, :store, :warning, 'alert msg')
        expect(BitexBot::Robot).to receive(:notify).with('alert msg')

        alert_date = 2.days.from_now
        Timecop.freeze(alert_date) { described_class.alert(currency_type) }
        expect(described_class.store.last_warning).to eq(alert_date)
      end
    end

    it_behaves_like 'for currency type', :crypto
    it_behaves_like 'for currency type', :fiat
  end

  describe '.alert_message' do
    before(:each) { allow(described_class).to receive(:store).and_return(store) }

    subject(:message) { described_class.alert_message(currency_type) }

    context 'for fiat type' do
      let(:store) { create(:store, maker_fiat: 2, fiat_warning: 200) }
      let(:currency_type) { :fiat }

      it { is_expected.to eq("FIAT balance is too low, it's 2.0, make it 200.0 to stop this warning.") }
    end

    context 'for crypto type' do
      let(:store) { create(:store, maker_crypto: 1, crypto_warning: 100) }
      let(:currency_type) { :crypto }

      it { is_expected.to eq("CRYPTO balance is too low, it's 1.0, make it 100.0 to stop this warning.") }
    end
  end

  describe '.balance_flag_for' do
    before(:each) { allow(described_class).to receive(:store).and_return(store) }

    subject(:balance) { described_class.balance_flag_for(currency_type) }

    context 'for fiat type' do
      before(:each) { allow(BitexBot::Settings).to receive(:buying_fx_rate).and_return(2.to_d) }

      let(:store) { create(:store, fiat_warning: 200) }
      let(:currency_type) { :fiat }

      it { is_expected.to eq(100) }
    end

    context 'for crypto type' do
      let(:store) { create(:store, crypto_warning: 200) }
      let(:currency_type) { :crypto }

      it { is_expected.to eq(200) }
    end
  end

  it '.log_step' do
    expect(described_class.log_step).to eq(:warning)
  end
end
