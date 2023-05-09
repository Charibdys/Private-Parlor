require "yaml"

module Configuration
  extend self

  class Config
    include YAML::Serializable

    @[YAML::Field(key: "api_token")]
    getter token : String

    @[YAML::Field(key: "database")]
    getter database : String

    @[YAML::Field(key: "locale")]
    getter locale : String = "en-US"

    @[YAML::Field(key: "log_level")]
    getter log_level : Log::Severity = Log::Severity::Info

    @[YAML::Field(key: "log_file")]
    getter log_file : String? = nil

    @[YAML::Field(key: "lifetime")]
    property lifetime : Int32 = 24

    @[YAML::Field(key: "database_history")]
    getter database_history : Bool? = false

    @[YAML::Field(key: "allow_media_spoilers")]
    getter allow_media_spoilers : Bool? = false

    @[YAML::Field(key: "ranks")]
    getter intermediary_ranks : Array(IntermediaryRank)

    @[YAML::Field(ignore: true)]
    getter ranks : Hash(Int32, Rank) = {
      -10 => Rank.new("Banned", Set.new([] of Symbol)),
      0 => Rank.new("User", Set.new([:upvote, :downvote, :sign, :tsign]))
    }

    # Command Toggles

    @[YAML::Field(key: "enable_start")]
    getter enable_start : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_stop")]
    getter enable_stop : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_info")]
    getter enable_info : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_users")]
    getter enable_users : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_version")]
    getter enable_version : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_toggle_karma")]
    getter enable_toggle_karma : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_toggle_debug")]
    getter enable_toggle_debug : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_tripcode")]
    getter enable_tripcode : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_sign")]
    getter enable_sign : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_tripsign")]
    getter enable_tripsign : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_ranksay")]
    getter enable_ranksay : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_motd")]
    getter enable_motd : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_help")]
    getter enable_help : Array(Bool) = [true, true]

    @[YAML::Field(key: "enable_upvotes")]
    getter enable_upvote : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_downvotes")]
    getter enable_downvote : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_promote")]
    getter enable_promote : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_demote")]
    getter enable_demote : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_warn")]
    getter enable_warn : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_delete")]
    getter enable_delete : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_uncooldown")]
    getter enable_uncooldown : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_remove")]
    getter enable_remove : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_purge")]
    getter enable_purge : Array(Bool) = [true, false]

    @[YAML::Field(key: "enable_blacklist")]
    getter enable_blacklist : Array(Bool) = [true, false]

    # Relay Toggles

    @[YAML::Field(key: "relay_text")]
    getter relay_text : Bool? = true

    @[YAML::Field(key: "relay_animation")]
    getter relay_animation : Bool? = true

    @[YAML::Field(key: "relay_audio")]
    getter relay_audio : Bool? = true

    @[YAML::Field(key: "relay_document")]
    getter relay_document : Bool? = true

    @[YAML::Field(key: "relay_video")]
    getter relay_video : Bool? = true

    @[YAML::Field(key: "relay_video_note")]
    getter relay_video_note : Bool? = true

    @[YAML::Field(key: "relay_voice")]
    getter relay_voice : Bool? = true

    @[YAML::Field(key: "relay_photo")]
    getter relay_photo : Bool? = true

    @[YAML::Field(key: "relay_media_group")]
    getter relay_media_group : Bool? = true

    @[YAML::Field(key: "relay_poll")]
    getter relay_poll : Bool? = true

    @[YAML::Field(key: "relay_forwarded_message")]
    getter relay_forwarded_message : Bool? = true

    @[YAML::Field(key: "relay_sticker")]
    getter relay_sticker : Bool? = true

    @[YAML::Field(key: "relay_dice")]
    getter relay_dice : Bool? = false

    @[YAML::Field(key: "relay_dart")]
    getter relay_dart : Bool? = false

    @[YAML::Field(key: "relay_basketball")]
    getter relay_basketball : Bool? = false

    @[YAML::Field(key: "relay_soccerball")]
    getter relay_soccerball : Bool? = false

    @[YAML::Field(key: "relay_slot_machine")]
    getter relay_slot_machine : Bool? = false

    @[YAML::Field(key: "relay_bowling")]
    getter relay_bowling : Bool? = false

    @[YAML::Field(key: "relay_venue")]
    getter relay_venue : Bool? = false

    @[YAML::Field(key: "relay_location")]
    getter relay_location : Bool? = false

    @[YAML::Field(key: "relay_contact")]
    getter relay_contact : Bool? = false

    # Karma/Warning Cooldown Constants

    @[YAML::Field(key: "cooldown_time_begin")]
    getter cooldown_time_begin : Array(Int32) = [1, 5, 25, 120, 720, 4320]

    @[YAML::Field(key: "cooldown_time_linear_m")]
    getter cooldown_time_linear_m : Int32 = 4320

    @[YAML::Field(key: "cooldown_time_linear_b")]
    getter cooldown_time_linear_b : Int32 = 10080

    @[YAML::Field(key: "warn_expire_hours")]
    getter warn_expire_hours : Int32 = 7 * 24

    @[YAML::Field(key: "karma_warn_penalty")]
    getter karma_warn_penalty : Int32 = 10

    # Spam limits

    @[YAML::Field(key: "spam_limit")]
    getter spam_limit : Float32 = 3.0

    @[YAML::Field(key: "spam_limit_hit")]
    getter spam_limit_hit : Float32 = 6.0

    @[YAML::Field(key: "spam_interval_seconds")]
    getter spam_interval_seconds : Int32 = 10

    # Spam Score Constants

    @[YAML::Field(key: "score_base_message")]
    getter score_base_message : Float32 = 0.75

    @[YAML::Field(key: "score_text_character")]
    getter score_text_character : Float32 = 0.002

    @[YAML::Field(key: "score_text_linebreak")]
    getter score_text_linebreak : Float32 = 0.1

    @[YAML::Field(key: "score_animation")]
    getter score_animation : Float32 = 1.0

    @[YAML::Field(key: "score_audio")]
    getter score_audio : Float32 = 1.0

    @[YAML::Field(key: "score_document")]
    getter score_document : Float32 = 1.0

    @[YAML::Field(key: "score_video")]
    getter score_video : Float32 = 1.0

    @[YAML::Field(key: "score_video_note")]
    getter score_video_note : Float32 = 1.5

    @[YAML::Field(key: "score_voice")]
    getter score_voice : Float32 = 1.5

    @[YAML::Field(key: "score_photo")]
    getter score_photo : Float32 = 1.0

    @[YAML::Field(key: "score_media_group")]
    getter score_media_group : Float32 = 2.5

    @[YAML::Field(key: "score_poll")]
    getter score_poll : Float32 = 2.5

    @[YAML::Field(key: "score_forwarded_message")]
    getter score_forwarded_message : Float32 = 1.25

    @[YAML::Field(key: "score_sticker")]
    getter score_sticker : Float32 = 1.5

    @[YAML::Field(key: "score_dice")]
    getter score_dice : Float32 = 2.0

    @[YAML::Field(key: "score_dart")]
    getter score_dart : Float32 = 2.0

    @[YAML::Field(key: "score_basketball")]
    getter score_basketball : Float32 = 2.0

    @[YAML::Field(key: "score_soccerball")]
    getter score_soccerball : Float32 = 2.0

    @[YAML::Field(key: "score_slot_machine")]
    getter score_slot_machine : Float32 = 2.0

    @[YAML::Field(key: "score_bowling")]
    getter score_bowling : Float32 = 2.0

    @[YAML::Field(key: "score_venue")]
    getter score_venue : Float32 = 2.0

    @[YAML::Field(key: "score_location")]
    getter score_location : Float32 = 2.0

    @[YAML::Field(key: "score_contact")]
    getter score_contact : Float32 = 2.0

    @[YAML::Field(key: "media_limit_period")]
    getter media_limit_period : Int32 = 0

    @[YAML::Field(key: "registration_open")]
    getter registration_open : Bool? = true

    @[YAML::Field(key: "blacklist_contact")]
    getter blacklist_contact : String? = nil

    @[YAML::Field(key: "full_usercount")]
    getter full_usercount : Bool? = false

    @[YAML::Field(key: "sign_limit_interval")]
    getter sign_limit_interval : Int32 = 600

    @[YAML::Field(key: "upvote_limit_interval")]
    getter upvote_limit_interval : Int32 = 0

    @[YAML::Field(key: "downvote_limit_interval")]
    getter downvote_limit_interval : Int32 = 0

    @[YAML::Field(key: "smileys")]
    property smileys : Array(String) = [":)", ":|", ":/", ":("]

    @[YAML::Field(key: "strip_format")]
    property entities : Array(String) = ["bold", "italic", "text_link"]

    @[YAML::Field(key: "tripcode_salt")]
    getter salt : String = ""

    def after_initialize
      Configuration.set_log(self)
    end
  end

  class IntermediaryRank
    include YAML::Serializable

    @[YAML::Field(key: "name")]
    getter name : String

    @[YAML::Field(key: "value")]
    getter value : Int32

    @[YAML::Field(key: "permissions")]
    getter permissions : Array(String)
  end

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
  end

  # Checks every intermediate rank for invalid or otherwise undefined permissions
  # and initializes the Ranks hash
  #
  # Returns an updated `Config` object
  def check_and_init_ranks(config : Config) : Config
    command_keys = %i(
      users upvote downvote promote promote_lower promote_same demote sign tsign ranksay 
      ranksay_lower warn delete uncooldown remove purge blacklist motd_set ranked_info
    )

    config.intermediary_ranks.each do |ri|
      if (invalid = ri.permissions.to_set - command_keys.map {|key| key.to_s}.to_set ) && !invalid.empty?
        Log.notice { 
          "Rank #{ri.name} (#{ri.value}) has the following invalid permissions: [#{invalid.join(", ")}]" 
        }
      end

      config.ranks[ri.value] = Rank.new(
        ri.name,
        command_keys.compact_map {|key| key if ri.permissions.includes?(key.to_s)}.to_set
      )
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
