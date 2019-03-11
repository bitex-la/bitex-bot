module BitexBot
  # Shared behaviour for position opening.
  module OpenableTrade
    extend ActiveSupport::Concern

    included do
      belongs_to :opening_flow, class_name: opening_flow_class.name, foreign_key: :opening_flow_id
      belongs_to :closing_flow, class_name: closing_flow_class.name, foreign_key: :closing_flow_id

      scope :open, -> { where(closing_flow: nil) }
    end
  end
end
