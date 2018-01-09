# An OpenSell represents a Sell transaction on Bitex.
# OpenSells are open sell positions that are closed by one
# SellClosingFlow
# TODO: document attributes.
class BitexBot::OpenSell < ActiveRecord::Base
  belongs_to :opening_flow, class_name: 'SellOpeningFlow', foreign_key: :opening_flow_id
  belongs_to :closing_flow, class_name: 'SellClosingFlow', foreign_key: :closing_flow_id
  scope :open, ->{ where('closing_flow_id IS NULL') }
end
