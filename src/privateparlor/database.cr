class Database
  getter db : DB::Database

  # Create an instance of Database and create the appropriate schema in the SQLite database.
  def initialize(database : DB::Database)
    @db = database
    ensure_schema()
  end

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

    # Create an instance of `User` from a hash with an `:id` key.
    #
    # If the hash does not contain any other key/value pairs, initialize using default values.
    #
    # Keys not found in `defaults` will default to `nil`.
    def initialize(user = {:id})
      defaults = {realname: "", rank: 0, joined: Time.utc, last_active: Time.utc, warnings: 0,
                  karma: 0, hide_karma: false, debug_enabled: false}

      defaults = defaults.merge(user)

      @id = defaults[:id]
      @username = defaults[:username]?
      @realname = defaults[:realname]
      @rank = defaults[:rank]
      @joined = defaults[:joined]
      @left = defaults[:left]?
      @last_active = defaults[:last_active]
      @cooldown_until = defaults[:cooldown_until]?
      @blacklist_reason = defaults[:blacklist_reason]?
      @warnings = defaults[:warnings]
      @warn_expiry = defaults[:warn_expiry]?
      @karma = defaults[:karma]
      @hide_karma = defaults[:hide_karma]
      @debug_enabled = defaults[:debug_enabled]
      @tripcode = defaults[:tripcode]?
    end

    # Returns an array with all the values in `User`. Used for Database query arguments.
    def to_array
      {% begin %}
        [
        {% for var in User.instance_vars[0..-2] %}
          @{{var.id}},
        {% end %}
          @{{User.instance_vars.last.id}}
        ]
      {% end %}
    end

    # Returns a string containing the username with an "@" appended to it if the user has a username.
    #
    # Otherwise, the user's realname is returned.
    def get_formatted_name : String
      if username = @username
        "@" + username
      else
        @realname
      end
    end

    # Get the user's obfuscated ID
    def get_obfuscated_id : String
      Random.new(@id + Time.utc.at_beginning_of_day.to_unix).base64(3)
    end

    # Get the user's obfuscated karma
    def get_obfuscated_karma : Int32
      offset = ((@karma * 0.2).abs + 2).round.to_i
      @karma + Random.rand(0..(offset + 1)) - offset
    end

    # Set *left* to nil, meaning that User has joined the chat.
    def rejoin : Nil
      @left = nil
    end

    # Set *last_active* to the current time and update names
    def set_active(username : String | Nil, fullname : String) : Nil
      @username = username
      @realname = fullname
      @last_active = Time.utc
    end

    # Set *left* to the current time; user has left the chat.
    def set_left : Nil
      @left = Time.utc
    end

    # Set *rank* to the given `Ranks` value.
    def set_rank(rank : Ranks) : Nil
      if @rank <= rank.value
        @rank = rank.value
      else
        @rank = rank.value
      end
    end

    def set_tripcode(tripcode : String) : Nil
      @tripcode = tripcode
    end

    # Set *hide_karma* to its opposite value.
    def toggle_karma : Nil
      @hide_karma = !hide_karma
    end

    # Set *debug_enabled* to its opposite value.
    def toggle_debug : Nil
      @debug_enabled = !debug_enabled
    end

    # Increment the user's karma by a given amount (1 by default)
    def increment_karma(amount : Int32 = 1) : Nil
      @karma += amount
    end

    # Decrement the user's karma by a given amount (1 by default)
    def decrement_karma(amount : Int32 = 1) : Nil
      @karma -= amount
    end

    # Sets user's cooldown and increments total warnings
    def cooldown_and_warn : Time::Span
      if @warnings < COOLDOWN_TIME_BEGIN.size
        cooldown_time = COOLDOWN_TIME_BEGIN[@warnings]
      else
        cooldown_time = COOLDOWN_TIME_LINEAR_M * (@warnings - COOLDOWN_TIME_BEGIN.size) + COOLDOWN_TIME_LINEAR_B
      end

      @cooldown_until = Time.utc + cooldown_time.minutes
      @warnings += 1
      @warn_expiry = Time.utc + WARN_EXPIRE_HOURS.hours
      self.decrement_karma(KARMA_WARN_PENALTY)
      cooldown_time.minutes
    end

    # Removes a cooldown from a user if it has expired.
    #
    # Returns true if the cooldown can be expired, false otherwise
    def remove_cooldown(override : Bool = false) : Bool
      if cooldown = @cooldown_until
        if cooldown < Time.utc || override
          @cooldown_until = nil
        else
          return false
        end
      end

      true
    end

    # Removes one or multiple warnings from a user and resets the `warn_expiry`
    def remove_warning(amount : Int32 = 1) : Nil
      @warnings -= amount

      if @warnings > 0
        @warn_expiry = Time.utc + WARN_EXPIRE_HOURS.hours
      else
        @warn_expiry = nil
      end
    end

    # Set user's rank to blacklisted, force leave, and update blacklist reason.
    def blacklist(reason : String | Nil) : Nil
      @rank = -10
      self.set_left
      @blacklist_reason = reason
    end

    # Returns `true` if *rank* is -10; user is blacklisted.
    #
    # Returns `false` otherwise.
    def blacklisted? : Bool
      @rank == -10
    end

    # Returns `true` if *left* is not nil; user has left the chat.
    #
    # Returns `false` otherwise.
    def left? : Bool
      @left != nil
    end

    # Returns `true` if user's rank is greater than or equal to the given rank; user is authorized.
    #
    # Returns `false` otherwise.
    def authorized?(rank : Ranks) : Bool
      @rank >= rank.value
    end

    # Returns `true` if user is joined, not in cooldown, and not blacklisted; user can chat
    #
    # Returns false otherwise.
    def can_chat? : Bool
      self.remove_cooldown && !self.blacklisted? && !self.left?
    end

    # Returns `true` if user is joined, not in cooldown, not blacklisted, and not limited; user can chat
    #
    # Returns false otherwise.
    def can_chat?(limit : Time::Span) : Bool
      if self.rank > 0
        self.can_chat?
      else
        self.remove_cooldown && !self.blacklisted? && !self.left? && (Time.utc - self.joined > limit)
      end
    end

    # Returns `true` if user is joined and not blacklisted; user can use commands
    #
    # Returns false otherwise.
    def can_use_command? : Bool
      !self.blacklisted? && !self.left?
    end
  end

  # Queries the database for a user record with the given *id*.
  #
  # Returns a `User` object.
  def get_user(id) : User | Nil
    db.query_one?("SELECT * FROM users WHERE id = ?", id, as: User)
  end

  def get_user_counts : NamedTuple
    db.query_one("SELECT COUNT(id), COUNT(left), (SELECT COUNT(id) FROM users WHERE rank = -10) FROM users",
      as: {total: Int32, left: Int32, blacklisted: Int32})
  end

  # Queries the database for blacklisted users who have been banned within the past 48 hours.
  #
  # Returns an array of `User` or `Nil` if no users were found.
  def get_blacklisted_users : Array(User) | Nil
    db.query_all("SELECT * FROM users WHERE rank = -10 AND left > (?)", (Time.utc - 48.hours), as: User)
  end

  # Queries the database for all warned users that are in the chat.
  #
  # Returns an array of `User` or `Nil` if no users were found.
  def get_warned_users : Array(User) | Nil
    db.query_all("SELECT * FROM users WHERE warnings > 0 AND left is NULL", as: User)
  end

  # Queries the database for a user with a given *username*.
  #
  # Returns a `User` object or Nil if no user was found.
  def get_user_by_name(username) : User | Nil
    if username.starts_with?("@")
      username = username[1..]
    end
    db.query_one?("SELECT * FROM users WHERE LOWER(username) = ?", username.downcase, as: User)
  end

  def get_user_by_oid(oid : String) : User | Nil
    db.query_all("SELECT * FROM users WHERE left IS NULL ORDER BY lastActive DESC", as: User).each do |user|
      if user.get_obfuscated_id == oid
        return user
      end
    end
  end

  # Queries the database for all user ids, ordered by highest ranking users first then most active users.
  def get_prioritized_users : Array(Int64)
    db.query_all("SELECT id FROM users WHERE left IS NULL ORDER BY rank DESC, lastActive DESC", &.read(Int64))
  end

  # Inserts a user with the given *id*, *username*, and *realname* into the database.
  #
  # Returns the new `User`.
  def add_user(id, username, realname, rank = 0) : User
    user = User.new({id: id, username: username, realname: realname, rank: rank})

    {% begin %}
      {% arr = [] of ArrayLiteral %}
      {% for var in User.instance_vars %}
        {% arr << "?" %}
      {% end %}
      {% arr = arr.join(", ") %}

      # Add user to database
      db.exec("INSERT INTO users VALUES (#{{{arr}}})", args: user.to_array)
    {% end %}

    user
  end

  # Updates a user record in the database with the current state of *user*.
  def modify_user(user : User) : Nil
    {% begin %}
      {% arr = [] of ArrayLiteral %}
      {% for var in User.instance_vars[1..-1] %}
        {% arr << "#{var.name.camelcase(lower: true)} = ?" %}
      {% end %}
      {% arr = arr.join(", ") %}
      # Modify user
      db.exec("UPDATE users SET #{{{arr}}} WHERE id = ?", args: user.to_array.rotate)
    {% end %}
  end

  # Queries the database for any rows in the user table
  #
  # Returns true if can't move to next row (table is empty). False otherwise.
  def no_users? : Bool
    !db.query("SELECT id FROM users") do |rs|
      rs.move_next
    end
  end

  # Queries the database for warned users and removes warnings they have expired.
  def expire_warnings : Nil
    get_warned_users.each do |user|
      if expiry = user.warn_expiry
        if expiry <= Time.utc
          user.remove_warning
          modify_user(user)
        end
      end
    end
  end

  # Sets the motd/rules to the given string.
  def set_motd(text : String) : Nil
    db.exec("REPLACE INTO system_config VALUES ('motd', ?)", text)
  end

  # Retrieves the motd/rules from the database.
  #
  # Returns the motd as a string, or returns nil if the motd could not be retrieved.
  def get_motd : String | Nil
    db.query_one?("SELECT value FROM system_config WHERE name = 'motd'", as: String)
  end

  # Ensures that the DB schema is usable by the program.
  #
  # This is the same schema used in secretlounge-ng SQLite databases.
  def ensure_schema : Nil
    db.exec("CREATE TABLE IF NOT EXISTS system_config (
      name TEXT NOT NULL,
      value TEXT NOT NULL,
      PRIMARY KEY (name)
    )")
    db.exec("CREATE TABLE IF NOT EXISTS users (
      id BIGINT NOT NULL,
      username TEXT,
      realname TEXT NOT NULL,
      rank INTEGER NOT NULL,
      joined TIMESTAMP NOT NULL,
      left TIMESTAMP,
      lastActive TIMESTAMP NOT NULL,
      cooldownUntil TIMESTAMP,
      blacklistReason TEXT,
      warnings INTEGER NOT NULL,
      warnExpiry TIMESTAMP,
      karma INTEGER NOT NULL,
      hideKarma TINYINT NOT NULL,
      debugEnabled TINYINT NOT NULL,
      tripcode TEXT,
      PRIMARY KEY(id)
    )")
  end
end

class DatabaseHistory
  getter db : DB::Database
  getter lifespan : Time::Span = 24.hours

  # Create an instance of DatabaseHistory and create the appropriate schema in the SQLite database.
  def initialize(database : DB::Database, message_life : Time::Span)
    @db = database
    @lifespan = message_life
    ensure_schema()
  end

  # Adds a new entry to the message_groups table with the *sender_id* and its associated *msid*
  #
  # Returns the original msid of this message group
  def new_message(sender_id : Int64, msid : Int64) : Int64
    db.exec(
      "INSERT INTO message_groups VALUES (?, ?, ?, ?)",
      args: [msid, sender_id, Time.utc, false]
    )
    msid
  end

  # Adds receiver_id and its associated msid to the receivers table
  def add_to_cache(origin_msid : Int64, msid : Int64, receiver_id : Int64) : Nil
    db.exec(
      "INSERT INTO receivers VALUES (?, ?, ?)",
      args: [msid, receiver_id, origin_msid]
    )
  end

  # Returns the messageGroupID from the given MSID, which may or may not be in in the receivers table
  def get_origin_msid(msid : Int64) : Int64 | Nil
    db.query_one?(
      "SELECT messageGroupID
      FROM receivers
      where receiverMSID = ?
      UNION
      select messageGroupID
      FROM message_groups
      WHERE messageGroupID = ?",
      msid, msid,
      as: Int64
    )
  end

  # Get all receivers for a message group associated with the given MSID
  def get_all_msids(msid : Int64) : Hash
    origin_msid = get_origin_msid(msid)

    db.query_all(
      "SELECT senderID, messageGroupID
      FROM message_groups
      WHERE messageGroupID = ?
      UNION
      SELECT receiverID, receiverMSID
      FROM receivers
      WHERE messageGroupID = ?",
      origin_msid, origin_msid,
      as: {Int64, Int64}
    ).to_h
  end

  # Get receiver msid from the given MSID and receiver ID
  def get_msid(msid : Int64, receiver_id : Int64) : Int64 | Nil
    get_all_msids(msid)[receiver_id]?
  end

  # Get sender_id of a specific message group
  def get_sender_id(msid : Int64) : Int64 | Nil
    db.query_one?(
      "SELECT senderID
      FROM message_groups
      JOIN receivers ON receivers.receiverMSID = ? AND receivers.messageGroupID = message_groups.messageGroupID",
      msid,
      as: Int64
    )
  end

  # Get all MSIDs sent by a user
  def get_msids_from_user(uid : Int64) : Set(Int64)
    db.query_all(
      "SELECT messageGroupID
      FROM message_groups
      WHERE senderID = ?",
      uid,
      as: Int64
    ).to_set
  end

  # Adds a rating entry to the karma table with the given data
  #
  # Returns true if the user was successfully added to the karma table; false if the user was already in it.
  def add_rating(msid : Int64, uid : Int64) : Bool
    db.exec("INSERT INTO karma VALUES (?, ?)", args: [msid, uid])
    true
  rescue SQLite3::Exception
    false
  end

  # Set the warned attribute to true in message group associated with the given MSID.
  def add_warning(msid : Int64) : Nil
    db.exec(
      "UPDATE message_groups
      SET warned = TRUE
      WHERE messageGroupID = ?",
      get_origin_msid(msid)
    )
  end

  # Returns true if the associated message group was warned; false otherwise.
  def get_warning(msid : Int64) : Bool | Nil
    db.query_one?(
      "SELECT warned
      FROM message_groups
      WHERE messageGroupID = ?",
      get_origin_msid(msid),
      as: Bool
    )
  end

  # Delete message group
  def del_message_group(msid : Int64) : Int64?
    origin_msid = get_origin_msid(msid)

    db.exec("DELETE FROM message_groups WHERE messageGroupID = ?", origin_msid)

    origin_msid
  end

  # Expire messages
  def expire : Nil
    count = db.query_one(
      "SELECT COUNT(messageGroupID)
      FROM message_groups
      WHERE sentTime <= ?",
      Time.utc - @lifespan,
      as: Int32
    )

    db.exec("DELETE FROM message_groups WHERE sentTime <= ?", Time.utc - @lifespan)

    if count > 0
      Log.debug { "Expired #{count} messages from the cache" }
    end
  end

  # Ensures that the DB schema for persisting message history is usable by the program.
  def ensure_schema : Nil
    db.exec("PRAGMA foreign_keys = ON")
    db.exec("CREATE TABLE IF NOT EXISTS message_groups (
      messageGroupID BIGINT NOT NULL,
      senderID BIGINT NOT NULL,
      sentTime TIMESTAMP NOT NULL,
      warned TINYINT NOT NULL,
      PRIMARY KEY (messageGroupID)
    )")
    db.exec("CREATE TABLE IF NOT EXISTS receivers (
      receiverMSID BIGINT NOT NULL,
      receiverID BIGINT NOT NULL,
      messageGroupID BIGINT NOT NULL,
      PRIMARY KEY (receiverMSID),
      FOREIGN KEY (messageGroupID) REFERENCES message_groups(messageGroupID)
    )")
    db.exec("CREATE TABLE IF NOT EXISTS karma (
      messageGroupID BIGINT NOT NULL,
      userID BIGINT NOT NULL,
      PRIMARY KEY (messageGroupID),
      FOREIGN KEY (messageGroupID) REFERENCES receivers(receiverMSID)
    )")
  end
end
