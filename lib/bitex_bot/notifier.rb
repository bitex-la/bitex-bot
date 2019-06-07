module BitexBot
  class Notifier

    cattr_accessor(:cache) { {} }
    cattr_accessor(:log_entries) { [] }

    cattr_accessor(:logger) do
      logdev = Settings.log.try(:file)
      STDOUT.sync = true unless logdev.present?
      Logger.new(logdev || STDOUT, 10, 10_240_000).tap do |log|
        log.level = Logger.const_get(Settings.log.level.upcase)
        log.formatter = proc do |severity, datetime, _progname, msg|
          date = datetime.strftime('%m/%d %H:%M:%S.%L')
          "#{format('%-6s', severity)} #{date}: #{msg}\n"
        end
      end
    end

    def self.get_latest_entries_and_clear
      logs = log_entries.join("\n")
      log_entries.clear
    end

    def self.notify(message, subj = 'Notice from your robot trader')
      if cache[subj]
        cache[subj][:counter] += 1
        now = Time.now
        elapsed = now - cache[subj][:last_notif]
        if elapsed >= 1.hour
          cache[subj][:counter] = 1
          cache[subj][:last_notif] = now
          notify_internal(message, subj)
        end
      else
        cache[subj] = {counter: 1, last_notif: Time.now}
        notify_internal(message, subj)
      end
      # could it be interesting to return if the message was immediately notified or not?
    end

    def self.notify_internal(message, subj)
      log(:info, "Sending mail with subject: #{subj}\n\n#{message}")
      return unless Settings.mailer.present?

      new_mail(subj, message).tap do |mail|
        mail.delivery_method(Settings.mailer.delivery_method.to_sym, Settings.mailer.options.to_hash)
      end.deliver!
    end

    def self.new_mail(subj, message)
      Mail.new do
        from Settings.mailer.from
        to Settings.mailer.to
        subject subj
        body message
      end
    end

    def self.log(level, message)
      log_entries << "#{level.upcase} #{Time.now.strftime('%m/%d %H:%M:%S.%L')}: #{message}"
      logger.send(level, message)
    end

  end
end
