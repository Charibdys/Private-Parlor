require "yaml"

module Configuration
  extend self

  MESSAGE_ENTITIES = ["mention", "hashtag", "cashtag", "bot_command", "url", "email", "phone_number", "bold",
                      "italic", "underline", "strikethrough", "spoiler", "code", "pre", "text_link", "text_mention"]

  class Config
    include YAML::Serializable

    @[YAML::Field(key: "api-token")]
    getter token : String

    @[YAML::Field(key: "database")]
    getter database : String

    @[YAML::Field(key: "log-level")]
    getter log_level : Log::Severity = Log::Severity::Info

    @[YAML::Field(key: "log-file")]
    getter log_file : String? = nil

    @[YAML::Field(key: "lifetime")]
    getter lifetime : Int32 = 24

    @[YAML::Field(key: "relay-luck")]
    getter relay_luck : Bool = true

    @[YAML::Field(key: "full-usercount")]
    getter full_usercount : Bool = false

    @[YAML::Field(key: "allow_signing")]
    getter allow_signing : Bool = false

    @[YAML::Field(key: "allow_tripcodes")]
    getter allow_tripcodes : Bool = false

    @[YAML::Field(key: "strip-format")]
    getter entities : Array(String) = ["bold", "italic", "text_link"]

    @[YAML::Field(key: "tripcode-salt")]
    getter salt : String = ""

    def initialize(@token : String, @database : String)
    end
  end

  # Parse config.yaml and returns a `Config` object.
  #
  # Values that aren't specified in the config file will be set to a default value.
  def parse_config : Config
    begin
      config = Config.from_yaml(File.open(File.expand_path("config.yaml")))
      if check_config(config) == false
        config = Config.new(config.token, config.database)
      end

      set_log(config)
      return config
    rescue ex : YAML::ParseException
      Log.error(exception: ex) { "Could not parse the given value at row #{ex.line_number}. This could be because a required value was not set or the wrong type was given." }
      exit
    rescue ex : File::NotFoundError | File::AccessDeniedError
      Log.error(exception: ex) { "Could not open \"./config.yaml\". Exiting..." }
      exit
    end
  end

  # Run additional checks on Config instance variables.
  #
  # Check bounds on `config.lifetime`.
  # Check contents of `config.entities` for mispellings or duplicates.
  def check_config(config : Config) : Bool
    if (1..48).includes?(config.lifetime) == false
      Log.notice { "Message lifetime not within range, was #{config.lifetime}; defaulting to 24 hours." }
      return false
    elsif (config.entities & MESSAGE_ENTITIES).size != config.entities.size
      Log.notice { "Could not determine strip-format, was #{config.entities}; check for duplicates or mispellings. Using defaults." }
      return false
    end
    return true
  end

  # Reset log with the severity level defined in `config.yaml`.
  #
  # A file can also be used to store log output. If the file does not exist, a new one will be made.
  def set_log(config : Config) : Nil
    # Skip setup if default values were given
    if config.log_level == Log::Severity::Info && config.log_file == nil
      return
    end

    # Reset log with log level; outputting to a file if a path was given
    begin
      if path = config.log_file
        if File.file?(path) # If log file already exists
          Log.setup(config.log_level, Log::IOBackend.new(File.open(path, "a+")))
        else # Log file does not exist, make one
          Log.setup(config.log_level, Log::IOBackend.new(File.new(path, "a+")))
        end
      else # Default to STDOUT
        Log.setup(config.log_level)
      end
    rescue ex : File::NotFoundError | File::AccessDeniedError
      Log.error(exception: ex) { "Could not open/create log file" }
    end
  end
end
