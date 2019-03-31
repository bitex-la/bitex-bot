require 'spec_helper'

describe BitexBot::CloseSell do
  before(:each) do
    allow(BitexBot::Robot).to receive_message_chain(:maker, :base).and_return('MAKER_BASE')
    allow(BitexBot::Robot).to receive_message_chain(:maker, :quote).and_return('MAKER_QUOTE')
  end

  subject(:close_trade) { create(:close_sell) }

  it_behaves_like 'CloseableTrades'
end
