class Database
  getter db : DB::Database

  # Create an instance of Database and create the appropriate schema in the SQLite database.
  def initialize(database : DB::Database)
    @db = database
    ensure_schema()
  end

  ATTRIBUTES = ["id", "username", "realname", "rank", "joined", "left", "lastActive", "cooldownUntil",
                "blacklistReason", "warnings", "warnExpiry", "karma", "hideKarma", "debugEnabled", "tripcode"]

  class User
    DB.mapping({id: Int64, username: String?, realname: String, rank: Int32, joined: Time,
                left: Time?, lastActive: Time, cooldownUntil: Time?, blacklistReason: String?,
                warnings: Int32, warnExpiry: Time?, karma: Int32, hideKarma: Bool, debugEnabled: Bool,
                tripcode: String?,
    })

    # Create an instance of `User` from a hash with an `:id` key.
    #
    # If the hash does not contain any other key/value pairs, initialize using default values.
    #
    # Keys not found in `defaults` will default to `nil`.
    def initialize(user = {:id})
      defaults = {realname: "", rank: 0, joined: Time.utc, lastActive: Time.utc, warnings: 0,
                  karma: 0, hideKarma: false, debugEnabled: false}

      defaults = defaults.merge(user)

      @id = defaults[:id]
      @username = defaults[:username]?
      @realname = defaults[:realname]
      @rank = defaults[:rank]
      @joined = defaults[:joined]
      @left = defaults[:left]?
      @lastActive = defaults[:lastActive]
      @cooldownUntil = defaults[:cooldownUntil]?
      @blacklistReason = defaults[:blacklistReason]?
      @warnings = defaults[:warnings]
      @warnExpiry = defaults[:warnExpiry]?
      @karma = defaults[:karma]
      @hideKarma = defaults[:hideKarma]
      @debugEnabled = defaults[:debugEnabled]
      @tripcode = defaults[:tripcode]?
    end

    # Returns an array with all the values in `User`. Used for Database query arguments.
    #
    # Values in the array must be in order according to the attributes in the database schema.
    def to_array : Array
      [@id, @username, @realname, @rank, @joined, @left, @lastActive, @cooldownUntil, @blacklistReason,
       @warnings, @warnExpiry, @karma, @hideKarma, @debugEnabled, @tripcode]
    end

    # Returns a string containing the username with an "@" appended to it if the user has a username.
    #
    # Otherwise, the user's realname is returned.
    def get_formatted_name : String
      if at = @username
        at = "@" + at
      else
        @realname
      end
    end

    # Get the user's obfuscated ID
    def get_obfuscated_id : String
      return Random.new(@id + Time.utc.at_beginning_of_day.to_unix).base64(3)
    end

    # Get the user's obfuscated karma
    def get_obfuscated_karma : Int32
      offset = ((@karma * 0.2).abs + 2).round.to_i
      return @karma + Random.rand(0..(offset + 1)) - offset
    end

    # Set *left* to nil, meaning that User has joined the chat.
    def rejoin : Nil
      @left = nil
    end

    # Set *lastActive* to the current time.
    def set_active : Nil
      @lastActive = Time.utc
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

    # Set *hideKarma* to its opposite value.
    def toggle_karma
      @hideKarma = !hideKarma
    end

    # Set *debugEnabled* to its opposite value.
    def toggle_debug
      @debugEnabled = !debugEnabled
    end

    # Increment the user's karma by a given amount (1 by default)
    def increment_karma(amount : Int32 = 1)
      @karma += amount
    end

    # Decrement the user's karma by a given amount (1 by default)
    def decrement_karma(amount : Int32 = 1)
      @karma -= amount
    end

    # Sets user's cooldown and increments total warnings
    def cooldown_and_warn
      if @warnings < COOLDOWN_TIME_BEGIN.size
        cooldown_time = COOLDOWN_TIME_BEGIN[@warnings]
      else
        cooldown_time = COOLDOWN_TIME_LINEAR_M * (@warnings - COOLDOWN_TIME_BEGIN.size) + COOLDOWN_TIME_LINEAR_B
      end

      @cooldownUntil = Time.utc + cooldown_time.minutes
      @warnings += 1
      @warnExpiry = Time.utc + WARN_EXPIRE_HOURS.hours
      cooldown_time.minutes
    end

    # Set user's rank to blacklisted, force leave, and update blacklist reason.
    def blacklist(reason : String | Nil) : Nil
      @rank = -10
      self.set_left
      @blacklistReason = reason
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

  # Queries the database for a user with a given *username*.
  #
  # Returns a `User` object or Nil if no user was found.
  def get_user_by_name(username) : User | Nil
    db.query_one?("SELECT * FROM users WHERE LOWER(username) = ?", username.downcase, as: User)
  end

  # Queries the database for all user ids, ordered by highest ranking users first then most active users.
  def get_prioritized_users : Array(Int64)
    db.query_all("SELECT id FROM users WHERE left IS NULL ORDER BY rank DESC, lastActive DESC", &.read(Int64))
  end

  # Inserts a user with the given *id*, *username*, and *realname* into the database.
  #
  # Returns the new `User`.
  def add_user(id, username, realname, rank = 0) : User
    # Prepare values
    user = User.new({id: id, username: username, realname: realname, rank: rank})
    args = user.to_array

    sql = String.build do |str|
      str << "INSERT INTO users VALUES (" << "?, " * (args.size - 1) << "?)"
    end

    # Add user to database
    db.exec(sql, args: args)

    user
  end

  # Updates a user record in the database with the current state of *user*.
  def modify_user(user : User) : Nil
    args = user.to_array

    sql = String.build do |str|
      str << "UPDATE users SET "
      ATTRIBUTES.each(within: 1..-2) do |atr|
        str << atr << " = ?, "
      end
      str << ATTRIBUTES.last << " = ? WHERE id = ?"
    end

    # Modify user
    db.exec(sql, args: args[1..] << args[0])
  end

  # Queries the database for any rows in the user table
  #
  # Returns true if can't move to next row (table is empty). False otherwise.
  def no_users? : Bool
    !db.query("SELECT id FROM users") do |rs|
      rs.move_next
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
