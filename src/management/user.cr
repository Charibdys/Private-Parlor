class User
  include DB::Serializable

  getter id : Int64
  getter username : String?
  getter realname : String
  getter rank : Int32
  getter joined : Time
  getter left : Time?
  @[DB::Field(key: "lastActive")]
  getter last_active : Time
  @[DB::Field(key: "cooldownUntil")]
  getter cooldown_until : Time?
  @[DB::Field(key: "blacklistReason")]
  getter blacklist_reason : String?
  getter warnings : Int32
  @[DB::Field(key: "warnExpiry")]
  getter warn_expiry : Time?
  getter karma : Int32
  @[DB::Field(key: "hideKarma")]
  getter hide_karma : Bool?
  @[DB::Field(key: "debugEnabled")]
  getter debug_enabled : Bool?
  getter tripcode : String?

  # Create an instance of `User`
  def initialize(
    @id,
    @username = nil,
    @realname = "",
    @rank = 0,
    @joined = Time.utc,
    @left = nil,
    @last_active = Time.utc,
    @cooldown_until = nil,
    @blacklist_reason = nil,
    @warnings = 0,
    @warn_expiry = nil,
    @karma = 0,
    @hide_karma = false,
    @debug_enabled = false,
    @tripcode = nil
  )
  end

  def to_s : String
    "ID: #{@id}, Username: #{@username ? @username : "N/A"}, Realname: #{@realname.empty? ? "N/A" : @realname}, " \
    "Rank: #{@rank}, Joined: #{@joined}, Left: #{@left ? @left : "N/A"}, Last Active: #{@last_active}, " \
    "Cooldown Until: #{@cooldown_until ? @cooldown_until : "N/A"}, Blacklist Reason: #{@blacklist_reason ? @blacklist_reason : "N/A"}, " \
    "Warnings: #{@warnings}, Warn Expiry: #{@warn_expiry ? @warn_expiry : "N/A"}, Karma: #{@karma}, " \
    "Hide Karma: #{@hide_karma}, Debug Enabled: #{@debug_enabled}, Tripcode: #{@tripcode ? @tripcode : "N/A"}"
  end
end