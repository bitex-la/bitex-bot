require 'spec_helper'

describe 'BitexApi' do
  before(:each) { BitexBot::Robot.setup }
  let(:maker) { BitexBot::Robot.maker }

  it 'Sends User-Agent header' do
    stub_request(:get, 'https://bitex.la/api-v1/rest/private/profile?api_key=your_bitex_api_key_which_should_be_kept_safe')
      .with(headers: { 'User-Agent': BitexBot.user_agent })

    maker.profile rescue nil # we don't care about the response
  end
end
