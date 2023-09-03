require "yaml"

module Configuration
  extend self

  # Parse config.yaml and returns a `Config` object.
  #
  # Values that aren't specified in the config file will be set to a default value.
  def parse_config : Config
    check_config(Config.from_yaml(File.open("config.yaml")))
  rescue ex : YAML::ParseException
    Log.error(exception: ex) { "Could not parse the given value at row #{ex.line_number}. This could be because a required value was not set or the wrong type was given." }
    exit
  rescue ex : File::NotFoundError | File::AccessDeniedError
    Log.error(exception: ex) { "Could not open \"./config.yaml\". Exiting..." }
    exit
  end

  # Run additional checks on Config instance variables.
  #
  # Check size of `config.smileys`; should be 4
  # Check contents of `config.entities` for mispellings or duplicates.
  #
  # Returns the given config, or an updated config if any values were invalid.
  def check_config(config : Config) : Config
    message_entities = ["mention", "hashtag", "cashtag", "bot_command", "url", "email", "phone_number", "bold", "italic",
                        "underline", "strikethrough", "spoiler", "code", "pre", "text_link", "text_mention", "custom_emoji"]

    if config.smileys.size != 4
      Log.notice { "Not enough or too many smileys. Should be four, was #{config.smileys}; defaulting to [:), :|, :/, :(]" }
      config.smileys = [":)", ":|", ":/", ":("]
    end

    if (config.entities & message_entities).size != config.entities.size
      Log.notice { "Could not determine strip_format, was #{config.entities}; check for duplicates or mispellings. Using defaults." }
      config.entities = ["bold", "italic", "text_link"]
    end

    unless config.karma_levels.empty? || (config.karma_levels.keys.sort! == config.karma_levels.keys)
      Log.notice { "Karma level keys were not in ascending order; defaulting to no karma levels." }
      config.karma_levels = {} of Int32 => String
    end

    config = check_and_init_ranks(config)
    config = init_valid_codepoints(config)
    config = check_and_init_linked_network(config)
  end

  # Checks every intermediate rank for invalid or otherwise undefined permissions
  # and initializes the Ranks hash
  #
  # Returns an updated `Config` object
  def check_and_init_ranks(config : Config) : Config
    promote_keys = Set{
      CommandPermissions::Promote,
      CommandPermissions::PromoteLower,
      CommandPermissions::PromoteSame,
    }

    ranksay_keys = Set{
      CommandPermissions::Ranksay,
      CommandPermissions::RanksayLower,
    }

    if config.ranks[config.default_rank]? == nil
      Log.notice { "Default rank #{config.default_rank} does not exist in ranks, using User with rank 0 as default" }
      config.default_rank = 0

      config.ranks[0] = Rank.new(
        "User",
        Set{
          CommandPermissions::Upvote, CommandPermissions::Downvote, CommandPermissions::Sign, CommandPermissions::TSign,
        },
        Set{
          MessagePermissions::Text, MessagePermissions::Animation, MessagePermissions::Audio, MessagePermissions::Document,
          MessagePermissions::Video, MessagePermissions::VideoNote, MessagePermissions::Voice, MessagePermissions::Photo,
          MessagePermissions::MediaGroup, MessagePermissions::Poll, MessagePermissions::Forward, MessagePermissions::Sticker,
          MessagePermissions::Dice, MessagePermissions::Dart, MessagePermissions::Basketball, MessagePermissions::Soccerball,
          MessagePermissions::SlotMachine, MessagePermissions::Bowling, MessagePermissions::Venue,
          MessagePermissions::Location, MessagePermissions::Contact,
        }
      )
    end

    config.ranks.each do |key, rank|
      permissions = rank.command_permissions
      if (invalid_promote = rank.command_permissions & promote_keys) && invalid_promote.size > 1
        Log.notice {
          "Removed the following mutually exclusive permissions from Rank #{rank.name}: [#{invalid_promote.join(", ")}]"
        }
        permissions = rank.command_permissions - promote_keys
      end
      if (invalid_ranksay = rank.command_permissions & ranksay_keys) && invalid_ranksay.size > 1
        Log.notice {
          "Removed the following mutually exclusive permissions from Rank #{rank.name}: [#{invalid_ranksay.join(", ")}]"
        }
        permissions = rank.command_permissions - ranksay_keys
      end

      config.ranks[key] = Rank.new(rank.name, permissions, rank.message_permissions)
    end

    config
  end

  def init_valid_codepoints(config : Config) : Config
    unless codepoint_tuples = config.intermediate_valid_codepoints
      return config
    end

    ranges = [] of Range(Int32, Int32)
    codepoint_tuples.each do |tuple|
      ranges << Range.new(tuple[0], tuple[1])
    end

    config.valid_codepoints = ranges

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
    Log.setup do |log|
      if path = config.log_file
        begin
          if File.file?(path) # If log file already exists
            file = Log::IOBackend.new(File.open(path, "a+"))
          else # Log file does not exist, make one
            file = Log::IOBackend.new(File.new(path, "a+"))
          end
        rescue ex : File::NotFoundError | File::AccessDeniedError
          Log.error(exception: ex) { "Could not open/create log file" }
        end

        log.bind("*", config.log_level, file) if file
      end

      log.bind("*", config.log_level, Log::IOBackend.new())
    end
  end
end
