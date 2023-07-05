require "tourmaline"
require "tasker"
require "sqlite3"
require "./privateparlor/*"

VERSION = "0.8"

bot = PrivateParlor.new(Configuration.parse_config)

Log.info { Format.substitute_log(bot.locale.logs.start, bot.locale, {"version" => VERSION}) }

Signal::INT.trap do
  bot.stop_polling
end

Signal::TERM.trap do
  bot.stop_polling
end

# Start message sending routine
spawn(name: "private_parlor_loop") do
  loop do
    break unless bot.polling

    bot.send_messages
    sleep(0.5)
  end

  # Send last messages in queue
  loop do
    break if bot.send_messages == true
  end

  # Bot stopped polling from SIGINT/SIGTERM, shut down
  bot.database.db.close
  Log.info { "Sent last messages in queue. Shutting down..." }
  exit
end

bot.poll

sleep
