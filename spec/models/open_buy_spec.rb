require 'spec_helper'

describe BitexBot::OpenBuy do
  context 'factory' do
    subject(:open_trade) { create(:open_buy) }

    its(:opening_flow) { is_expected.to be_a(BitexBot::BuyOpeningFlow) }
    its(:closing_flow) { is_expected.to be_nil }

    its(:transaction_id) { is_expected.to be_a(Integer) }
    its(:price) { is_expected.to be_a(BigDecimal) }
    its(:amount) { is_expected.to be_a(BigDecimal) }
    its(:quantity) { is_expected.to be_a(BigDecimal) }
  end

  context '.open' do
    before(:each) do
      create(:open_buy, id: 1)
      create(:closing_open_buy, id: 2)
    end

    subject(:open_trades) { described_class.open }

    its(:size) { is_expected.to eq(1) }

    context 'opening trade' do
      subject(:opening_trade) { open_trades.find(1) }

      its(:closing_flow) { is_expected.to be_nil }
    end
  end
end
