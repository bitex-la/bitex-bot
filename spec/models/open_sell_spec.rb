require 'spec_helper'

describe BitexBot::OpenSell do
  context 'factory' do
    subject(:open_trade) { create(:open_sell) }

    its(:opening_flow) { is_expected.to be_a(BitexBot::SellOpeningFlow) }
    its(:closing_flow) { is_expected.to be_nil }

    its(:transaction_id) { is_expected.to be_a(Integer) }
    its(:price) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:quantity) { is_expected.to be_a(BigDecimal) }
  end

  context '.open' do
    before(:each) do
      create(:open_sell, id: 1)
      create(:closing_open_sell, id: 2)
    end

    subject(:open_trades) { described_class.open }

    its(:size) { is_expected.to eq(1) }

    context 'opening trade' do
      subject(:opening_trade) { open_trades.find(1) }

      its(:closing_flow) { is_expected.to be_nil }
    end
  end
end
