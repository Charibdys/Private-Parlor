require "tourmaline"
require "tasker"
require "yaml"
require "sqlite3"
require "./privateparlor/*"


# Parse config.yaml and return the values as a NamedTuple
#
# Values that aren't specified in the config file or are specified as the wrong type
# will be set to a default value.
def parse_config : NamedTuple
  tuple = {token: "", database: "", log_level: "info", log_path: "", lifetime: 24.hours, relay_luck: false} 

  begin 
    config = File.open(File.expand_path("config.yaml")) do |file|
      YAML.parse(file).as_h
    end

    # Run checks; we cannot proceed without token or database
    if !config["api-token"]? || !config["api-token"].as_s?
      Log.error {"Could not get api-token. Check your configuration. Exiting..."}
      exit
    elsif !config["database"]? || !config["database"].as_s?
      Log.error {"Could not get database path. Check your configuration. Exiting..."}
      exit
    else
      tuple = tuple.merge({token: config["api-token"].as_s, database: config["database"].as_s})
    end

    # Get every other value in config; add to tuple
    if (log_level = config["log-level"]?) && (log_level = log_level.as_s?)
      tuple = tuple.merge({log_level: log_level})
    else
      Log.notice{"No log level specified; defaulting to INFO."}
    end

    if (log_path = config["log-file"]?) && (log_path = log_path.as_s?)
      tuple = tuple.merge({log_path: log_path})
    else
      Log.notice{"No log path specified; defaulting to STDOUT."}
    end

    if (lifetime = config["lifetime"]?) && (lifetime = lifetime.as_i?)
      if lifetime >= 1 && lifetime <= 48
        tuple = tuple.merge({lifetime: lifetime.hours})
      else
        Log.notice{"Message lifetime not within range, was #{lifetime}; defaulting to 24 hours."}
      end
    end

    if (relay_luck = config["relay-luck"]?) && (relay_luck = relay_luck.as_bool?)
      tuple = tuple.merge({relay_luck: relay_luck})
    else
      Log.notice{"Relay-luck was not specified, not sending luck-based emojis (dice, darts, etc)."}
    end

  rescue ex
    Log.error(exception: ex) {"Could not open \"./config.yaml\". Exiting..."}
    exit
  end

  config = tuple
end

# Reset log with the severity level defined in `config.yaml`.
#
# A file can also be used to store log output. If the file does not exist, a new one will be made.
#
# If there is an error in the configuration, the log outputs to `STDOUT` with the `INFO` severity.
def set_log(config : NamedTuple) : Nil
  # Skip setup if default values were given
  if config[:log_level] == "info" && config[:log_path].empty?
    return
  end

  # Get log level
  begin
    if level = config[:log_level]
      severity = Log::Severity.parse(level)
    end
  rescue ex : ArgumentError
    severity = Log::Severity::Info
    Log.error{"\"#{config[:log_level]}\" is not a possible log level; defaulting to INFO."}
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

db_path = Path.new(config[:database].to_s) # TODO: We'll want check if this works on Windows later
db = DB.open("sqlite3://#{db_path}")

bot = PrivateParlor.new(bot_token: config[:token], config: config, connection: db)

# Start message sending routine
spawn(name: "SendingQueue") do
  loop do
    bot.send_messages
  end
end

bot.poll