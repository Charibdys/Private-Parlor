require "tourmaline"
require "tasker"
require "yaml"
require "sqlite3"
require "./privateparlor/*"


# Parse config.yaml and return the values as a hash
#
# Values that aren't specified in the config file or are specified as the wrong type
# will be set to a default value
def parse_config : Hash
  defaults = {:log_level => "info", :lifetime => "24", :relay_luck => "false"} 
  values = {} of Symbol => String
  begin 
    config = File.open(File.expand_path("config.yaml")) do |file|
      YAML.parse(file)
    end

    # Read config and put values into a hash
    temp = config.as_h

    # Run checks; we cannot proceed without token or database
    if !temp["api-token"]? || !temp["api-token"].as_s?
      Log.error {"Could not get api-token. Check your configuration. Exiting..."}
      exit
    elsif !temp["database"]? || !temp["database"].as_s?
      Log.error {"Could not get database path. Check your configuration. Exiting..."}
      exit
    else
      values.merge!({:token => temp["api-token"].as_s, :database => temp["database"].as_s})
    end

    # Get every other value in config; add to hash
    if (log_level = temp["log-level"]?) && log_level.as_s?
      values.merge!({:log_level => log_level.as_s})
    else
      Log.notice{"No log level specified; defaulting to INFO."}
    end

    if (log_path = temp["log-file"]?) && log_path.as_s?
      values.merge!({:log_path => log_path.as_s})
    else
      Log.notice{"No log path specified; defaulting to STDOUT."}
    end

    if (lifetime = temp["lifetime"]?) && lifetime.as_i?
      if lifetime.as_i >= 1 && lifetime.as_i <= 48
        values.merge!({:lifetime => lifetime.to_s})
      else
        Log.notice{"Message lifetime not within range, was #{lifetime}; defaulting to 24 hours."}
      end
    end

    if relay_luck = temp["relay-luck"]?
      if relay_luck.as_bool?.is_a?(Bool)
        values.merge!({:relay_luck => relay_luck.to_s})
      end
    else
      Log.notice{"Relay-luck was not specified, not sending luck-based emojis (dice, darts, etc)."}
    end

  rescue ex
    Log.error(exception: ex) {"Could not open \"./config.yaml\". Exiting..."}
    exit
  end

  defaults = defaults.merge(values)
end

# Reset log with the severity level defined in `config.yaml`.
#
# A file can also be used to store log output. If the file does not exist, a new one will be made.
#
# If there is an error in the configuration, the log outputs to `STDOUT` with the `INFO` severity.
def set_log(config : Hash) : Nil
  # Skip setup if default values were given
  if config[:log_level] == "info" && !config[:log_path]?
    return
  end

  # Get log level
  if level = config[:log_level]?.to_s
    severity = Log::Severity.parse(level)
  else
    severity = Log::Severity::Info
  end

  # Reset log with log level; outputting to a file if a path was given
  begin
    if (path = config[:log_path]?.to_s) && (!path.empty?)
      if File.file?(path) # If log file already exists
        Log.setup(severity, Log::IOBackend.new(File.open(path, "a+")))
      else # Log file does not exist, make one
        Log.setup(severity, Log::IOBackend.new(File.new(path, "a+")))
      end
    else # Default to STDOUT
      Log.setup(severity)
    end
  rescue ex
    Log.error(exception: ex) {"Could not open/create log file"}
  end
end

####################
# MAIN STARTS HERE #
####################

config = parse_config()
set_log(config)

Log.info{"Starting Private Parlor v#{Version::VERSION}..."}

token = config[:token].to_s
db_path = Path.new(config[:database].to_s) # TODO: We'll want check if this works on Windows later

db = DB.open("sqlite3://#{db_path}")

bot = PrivateParlor.new(bot_token: token, config: config, connection: db)

# Start message sending routine
spawn(name: "SendingQueue") do
  loop do
    bot.send_messages
  end
end

bot.poll