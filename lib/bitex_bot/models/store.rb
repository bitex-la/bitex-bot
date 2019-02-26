module BitexBot
  # Stores all robot settings and state to be shared with other applications.
  class Store < ActiveRecord::Base
    before_save :sanitize_log

    def sanitize_log
      self.log = log.reverse.truncate(1000).reverse if log.present?
    end
  end
end
