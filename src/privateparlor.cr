require "tourmaline"
require "tourmaline/src/tourmaline/extra/format.cr"
require "tasker"
require "sqlite3"
require "./privateparlor/*"

Log.info { "Starting Private Parlor v#{VERSION}..." }

bot = PrivateParlor.new(Configuration.parse_config, parse_mode: Tourmaline::ParseMode::MarkdownV2)

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
