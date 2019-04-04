require 'spec_helper'

describe BitexBot::Notifier do
  before(:each) do

    allow(BitexBot::Settings)
      .to receive(:mailer)
      .and_return(double(from: 'me@test.com', to: 'you@test.com', delivery_method: :test))
  end

  describe '.notify' do
    before(:each) do
      allow(BitexBot::Robot)
        .to receive(:log)
        .with(:info, :bot, :notify, 'Sending mail: { subject: subject, body: message }')
    end

    it do
      expect(BitexBot::Robot)
        .to receive(:log)
        .with(:info, :bot, :notify, 'Sending mail: { subject: subject, body: message }')

      expect { described_class.notify('message', 'subject') }.to change  { Mail::TestMailer.deliveries.count }.by(1)

      is_expected
        .to have_sent_email
        .from('me@test.com')
        .to('you@test.com')
        .with_subject('subject')
        .with_body('message')
    end
  end

  describe '.mail' do
    subject(:mail) { described_class.send(:mail, 'message', 'subject') }

    its(:from) { is_expected.to eq(%w[me@test.com]) }
    its(:to) { is_expected.to eq(%w[you@test.com]) }
    its(:subject) { is_expected.to eq('subject') }
    its(:decoded) { is_expected.to eq('message') }
  end
end
