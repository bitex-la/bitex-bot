require 'spec_helper'

describe BitexBot::OpenBuy do
  before(:each) do
    allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('MAKER_BASE')
    allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('MAKER_QUOTE')
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to validate_presence_of(:transaction_id) }
  end

  context 'valid factory' do
    subject(:open_trade) { create(:open_buy) }

    its(:valid?) { is_expected.to be_truthy }

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

  context '#hit_summary' do
    subject(:open_trade) { create(:open_buy) }

    its(:hit_summary) do
      is_expected.to eq('BitexBot::BuyOpeningFlow #1 on order_id #12345678 was hit for MAKER_BASE 2.0 @ MAKER_QUOTE 300.0.')
    end
  end
end
