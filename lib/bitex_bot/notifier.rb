module BitexBot
  # Robot notifier, it use https://github.com/mikel/mail
  class Notifier
    def self.notify(message, subj = 'Notice from your robot trader')
      Robot.log(:info, :bot, :notify, "Sending mail: { subject: #{subj}, body: #{message.split("\n").first} }")

      mail(message, subj) do |new_mail|
        new_mail.delivery_method(Settings.mailer.delivery_method.to_sym, Settings.mailer.options.to_hash)
      end.deliver!
    end

    def self.mail(message, subj)
      Mail.new do
        from Settings.mailer.from
        to Settings.mailer.to
        subject subj
        body message
      end
    end

    private_class_method :mail
  end
end
