require "tourmaline"
require "tasker"
require "yaml"
require "sqlite3"
require "./privateparlor/*"

# Reset log with the severity level defined in `config.yaml`.
#
# A file can also be used to store log output. If the file does not exist, a new one will be made.
#
# If there is an error in the configuration, the log outputs to `STDOUT` with the `INFO` severity.
def set_log()
  if CONFIG["log"]?
    begin
      begin
        severity = Log::Severity.parse(CONFIG["log"][0].to_s)
      rescue ex : ArgumentError
        Log.error(exception: ex) {"Could not get log level; defaulting to INFO. Check your configuration"}
        severity = Log::Severity::Info
      end
      if File.file?(CONFIG["log"][1].to_s) # If log file already exists
        Log.setup(severity, Log::IOBackend.new(File.open(CONFIG["log"][1].to_s, "a+")))
      else # Log file does not exist, make one
        Log.setup(severity, Log::IOBackend.new(File.new(CONFIG["log"][1].to_s, "a+")))
      end
    rescue ex
      Log.error(exception: ex) {"Could not get log file path. Check your configuration."}
    end
  end
end

# MAIN STARTS HERE

CONFIG = File.open(File.expand_path("config.yaml")) do |file|
  YAML.parse(file)
end

set_log()
Log.info{"Starting Private Parlor v#{Version::VERSION}..."}

TOKEN = CONFIG["api-token"].to_s
DB_PATH = Path.new(CONFIG["database"].to_s) # TODO: We'll want check if this works on Windows later

db = DB.open("sqlite3://#{DB_PATH}")

bot = PrivateParlor.new(bot_token: TOKEN, config: CONFIG, connection: db)
bot.poll