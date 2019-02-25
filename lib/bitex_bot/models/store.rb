module BitexBot
  class Store < ActiveRecord::Base
    before_save :sanitize_log

    def sanitize_log
      self.log = log.reverse.truncate(1000).reverse if log.present?
    end
  end
end
