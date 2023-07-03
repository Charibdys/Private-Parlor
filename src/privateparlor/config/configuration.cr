require "yaml"

module Configuration
  extend self

  # Parse config.yaml and returns a `Config` object.
  #
  # Values that aren't specified in the config file will be set to a default value.
  def parse_config : Config
    config = check_config(Config.from_yaml(File.open("config.yaml")))
  rescue ex : YAML::ParseException
    Log.error(exception: ex) { "Could not parse the given value at row #{ex.line_number}. This could be because a required value was not set or the wrong type was given." }
    exit
  rescue ex : File::NotFoundError | File::AccessDeniedError
    Log.error(exception: ex) { "Could not open \"./config.yaml\". Exiting..." }
    exit
  end

  # Run additional checks on Config instance variables.
  #
  # Check bounds on `config.lifetime`.
  # Check size of `config.smileys`; should be 4
  # Check contents of `config.entities` for mispellings or duplicates.
  #
  # Returns the given config, or an updated config if any values were invalid.
  def check_config(config : Config) : Config
    message_entities = ["mention", "hashtag", "cashtag", "bot_command", "url", "email", "phone_number", "bold", "italic",
                        "underline", "strikethrough", "spoiler", "code", "pre", "text_link", "text_mention", "custom_emoji"]

    if (1..).includes?(config.lifetime) == false
      Log.notice { "Message lifetime not within range, was #{config.lifetime}; defaulting to 24 hours." }
      config.lifetime = 24
    end

    if config.smileys.size != 4
      Log.notice { "Not enough or too many smileys. Should be four, was #{config.smileys}; defaulting to [:), :|, :/, :(]" }
      config.smileys = [":)", ":|", ":/", ":("]
    end

    if (config.entities & message_entities).size != config.entities.size
      Log.notice { "Could not determine strip_format, was #{config.entities}; check for duplicates or mispellings. Using defaults." }
      config.entities = ["bold", "italic", "text_link"]
    end

    config = check_and_init_ranks(config)
    config = check_and_init_linked_network(config)
  end

  # Checks every intermediate rank for invalid or otherwise undefined permissions
  # and initializes the Ranks hash
  #
  # Returns an updated `Config` object
  def check_and_init_ranks(config : Config) : Config
    command_keys = Set{
      :users, :upvote, :downvote, :promote, :promote_lower, :promote_same, :demote, :sign, :tsign, :spoiler,
      :ranksay, :ranksay_lower, :warn, :delete, :uncooldown, :remove, :purge, :blacklist, :motd_set, :ranked_info
    }

    promote_keys = Set{:promote, :promote_lower, :promote_same}

    ranksay_keys = Set{:ranksay, :ranksay_lower}

    config.intermediary_ranks.each do |ri|
      if (invalid = ri.permissions.to_set - command_keys.map(&.to_s)) && !invalid.empty?
        Log.notice { 
          "Rank #{ri.name} (#{ri.value}) has the following invalid permissions: [#{invalid.join(", ")}]" 
        }
      end
      if (invalid_promote = ri.permissions & promote_keys.map(&.to_s)) && invalid_promote.size > 1
        Log.notice{
          "Removed the following mutually exclusive permissions from Rank #{ri.name} (#{ri.value}): [#{invalid_promote.join(", ")}]" 
        }
        ri.permissions = ri.permissions - promote_keys.map(&.to_s)
      end
      if (invalid_ranksay = ri.permissions & ranksay_keys.map(&.to_s)) && invalid_ranksay.size > 1
        Log.notice{
          "Removed the following mutually exclusive permissions from Rank #{ri.name} (#{ri.value}): [#{invalid_ranksay.join(", ")}]" 
        }
        ri.permissions = ri.permissions - ranksay_keys.map(&.to_s)
      end

      config.ranks[ri.value] = Rank.new(
        ri.name,
        command_keys.compact_map {|key| key if ri.permissions.includes?(key.to_s)}.to_set
      )
    end

    config
  end

  # Checks the config for a hash of linked networks and initializes `linked_network` field.
  #
  # If `intermediary_linked_network` is a hash, merge it into `linked_network`
  #
  # Otherwise if it is a string, try to open the file from the path and merge 
  # the YAML dictionary there into  `linked_network`
  def check_and_init_linked_network(config : Config) : Config
    if (links = config.intermediary_linked_network) && links.is_a?(String)
      begin
        hash = {} of String => String
        File.open(links) do |file|
          yaml = YAML.parse(file)
          yaml["linked_network"].as_h.each do |k, v|
            hash[k.as_s] = v.as_s
          end
          config.linked_network.merge!(hash)
        end
      rescue ex : YAML::ParseException
        Log.error(exception: ex) { "Could not parse the given value at row #{ex.line_number}. Check that \"linked_network\" is a valid dictionary." }
      rescue ex : File::NotFoundError | File::AccessDeniedError
        Log.notice(exception: ex) { "Could not open linked network file, \"#{links}\"" }
      end
    elsif links.is_a?(Hash(String, String))
      config.linked_network.merge!(links)
    end

    config
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
