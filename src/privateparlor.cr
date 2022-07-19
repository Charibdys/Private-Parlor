require "tourmaline"
require "tourmaline/src/tourmaline/extra/format.cr"
require "tasker"
require "sqlite3"
require "./privateparlor/*"

Log.info { "Starting Private Parlor v#{Version::VERSION}..." }

bot = PrivateParlor.new(Configuration.parse_config, parse_mode: Tourmaline::ParseMode::MarkdownV2)

# Start message sending routine
spawn(name: "SendingQueue") do
  loop do
    bot.send_messages
  end
end

bot.poll
