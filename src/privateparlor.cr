require "tourmaline"
require "tourmaline/src/tourmaline/extra/format.cr"
require "tasker"
require "sqlite3"
require "./privateparlor/*"

bot = PrivateParlor.new(Configuration.parse_config)

Log.info { bot.replies.substitute_log(:start, {"version" => VERSION}) }

# Start message sending routine
spawn(name: "SendingQueue") do
  loop do
    if msg = bot.queue.shift?
      bot.send_messages(msg)
    else
      Fiber.yield
    end
  end
end

bot.poll
