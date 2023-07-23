require "tourmaline"
require "tasker"
require "sqlite3"
require "./privateparlor/*"

VERSION = "1.0"

bot = PrivateParlor.new(Configuration.parse_config)

begin
  bot.log_output(bot.locale.logs.start, {"version" => VERSION})
rescue ex
  Log.error(exception: ex) {
    "Failed to send message to log channel; check that the bot is an admin in the chanel and can post messages"
  }
  bot.log_channel = ""
end

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
