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

  @[YAML::Field(key: "regular_forwards")]
  getter regular_forwards : Bool? = false

  @[YAML::Field(key: "inactivity_limit")]
  getter inactivity_limit : Int32 = 0

  @[YAML::Field(key: "linked_network")]
  getter intermediary_linked_network : Hash(String, String) | String | Nil

  @[YAML::Field(ignore: true)]
  getter linked_network : Hash(String, String) = {} of String => String

  @[YAML::Field(key: "ranks")]
  getter intermediary_ranks : Array(IntermediaryRank)

  @[YAML::Field(ignore: true)]
  getter ranks : Hash(Int32, Rank) = {
    -10 => Rank.new("Banned", Set.new([] of Symbol)),
      0 => Rank.new("User", Set.new([:upvote, :downvote, :sign, :tsign])),
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

  @[YAML::Field(key: "enable_spoiler")]
  getter enable_spoiler : Array(Bool) = [false, false]

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

  @[YAML::Field(key: "spam_interval_seconds")]
  getter spam_interval_seconds : Int32 = 10

  @[YAML::Field(key: "spam_score_handler")]
  getter spam_score_handler : SpamScoreHandler

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
