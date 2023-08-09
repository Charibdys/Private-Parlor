require "tourmaline"
require "tasker"
require "sqlite3"
require "./privateparlor/*"

VERSION = "1.0"

bot = PrivateParlor.new(Configuration.parse_config)

# 30 messages every second; going above may result in rate limits
sending_routine = Tasker.every(500.milliseconds) do
  15.times do
    break if bot.send_messages
  end
end

Signal::INT.trap do
  terminate_program(bot, sending_routine)
end

Signal::TERM.trap do
  terminate_program(bot, sending_routine)
end

begin
  bot.log_output(bot.locale.logs.start, {"version" => VERSION})
rescue ex
  Log.error(exception: ex) {
    "Failed to send message to log channel; check that the bot is an admin in the chanel and can post messages"
  }
  bot.log_channel = ""
end

bot.poll

sleep

def terminate_program(bot : PrivateParlor, routine : Tasker::Task)
  bot.stop_polling

  routine.cancel

  # Send last messages in queue
  loop do
    break if bot.send_messages == true
  end

  # Bot stopped polling from SIGINT/SIGTERM, shut down
  # Rescue if database unique constraint was encountered during runtime
  begin
    bot.database.db.close
  rescue
    nil
  end
  Log.info { "Sent last messages in queue. Shutting down..." }
  exit
end