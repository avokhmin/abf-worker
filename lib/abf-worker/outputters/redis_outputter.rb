require 'log4r/outputter/outputter'

module AbfWorker
  module Outputters
    class RedisOutputter < Log4r::Outputter

      def initialize(name, hash={})
        super(name, hash)
        @name = name
        @worker = hash[:worker]
        @buffer = []
        @buffer_limit = hash[:buffer_limit] || 100
        @time_interval = hash[:time_interval] || 10
        init_thread
      end


      private

      # perform the write
      def write(data)
        line = data.to_s
        unless line.empty?
          last_line = @buffer.last
          if last_line && (line.strip =~ /^[\#]+$/) && (line[-1, 1] == last_line[-1, 1])
            last_line.rstrip!
            last_line << line.lstrip
          else
            @buffer.shift if @buffer.size > @buffer_limit
            @buffer << line
          end
        end
      end

      def init_thread
        @thread = Thread.new do
          while true
            begin
              sleep @time_interval
              Resque.redis.setex(
                @name,
                (@time_interval + 5),
                @buffer.join
              )
            rescue => e
            end
          end # while
        end
        @thread.run
      end

    end
  end
end