module BitexBot
  # Custom bot logger
  class Logger < ::Logger
    attr_accessor :history

    def self.setup
      logdev = Settings.log.try(:file)
      STDOUT.sync = true unless logdev.present?

      new(logdev || STDOUT, 10, 10.megabyte, level: Settings.log.level, formatter: Formatter.new)
    end

    def initialize(*args, **kwargs, &block)
      super(*args, **kwargs, &block)
      self.history = []
    end

    def clean
      history.clear
    end

    private

    def format_message(*args)
      super(*args).tap { |output| history.prepend(output) }
    end

    # Custom bot formatter
    class Formatter < ::Logger::Formatter
      FORMAT = "%s %s  %s %s %s\n".freeze

      def initialize
        @datetime_format = '%m/%d %H:%M:%S.%L'
      end

      def call(severity, time, _progname, msg)
        format(
          FORMAT,
          format('%-6s', severity),
          format_datetime(time),
          format('%-8s', msg2str(msg.delete(:stage).to_s).upcase),
          format('%-14s', msg2str(msg.delete(:step).to_s).upcase),
          msg2str(msg.delete(:details))
        )
      end
    end
  end
end
