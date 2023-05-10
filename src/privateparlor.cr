require "tourmaline"
require "tourmaline/src/tourmaline/extra/format.cr"
require "tasker"
require "sqlite3"
require "./privateparlor/*"

VERSION = "0.7"

bot = PrivateParlor.new(Configuration.parse_config)

Log.info { bot.replies.substitute_log(:start, {"version" => VERSION}) }

Signal::INT.trap do
  bot.stop_polling
end

Signal::TERM.trap do
  bot.stop_polling
end

# Start message sending routine
spawn(name: "private_parlor_loop") do
  loop do
    if msg = bot.queue.shift?
      bot.send_messages(msg)
    else
      break unless bot.polling
      Fiber.yield
    end
  end

  # Bot stopped polling from SIGINT/SIGTERM, shut down
  bot.database.db.close
  Log.info { "Sent last messages in queue. Shutting down..." }
  exit
end

bot.poll

sleep
