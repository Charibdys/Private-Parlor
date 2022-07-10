class Database
  getter db : DB::Database

  # Create an instance of Database and create the appropriate schema in the SQLite database.
  def initialize(database : DB::Database)
    @db = database
    ensure_schema()
  end

  # Array of symbols used for making hashes.
  ATTRIBUTES = %i(id username realname rank joined 
  left lastActive cooldownUntil blacklistReason warnings 
  warnExpiry karma hideKarma debugEnabled tripcode)

  struct User
    getter id : Int64
    property rank : Int32, warnings : Int32, karma : Int32 
    property username : String?, realname : String, blacklist_text : String?, tripcode : String?
    property joined : Time, left : Time?, last_active : Time, cooldown_until : Time?, warn_expiry : Time?
    property hide_karma : Bool, debug_enabled : Bool 

    # Create an instance of `User` from a hash with an `:id` key.
    #
    # If the hash does not contain any other key/value pairs, initialize using default values.
    #
    # Keys not found in `defaults` will default to `nil`.
    def initialize(user = {:id})
      defaults = {realname: "", rank: 0, joined: Time.local, last_active: Time.local, warnings: 0, 
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
      @blacklist_text = defaults[:blacklist_text]?
      @warnings = defaults[:warnings]
      @warn_expiry = defaults[:warn_expiry]?
      @karma = defaults[:karma]
      @hide_karma = defaults[:hide_karma]
      @debug_enabled = defaults[:debug_enabled]
      @tripcode = defaults[:tripcode]?
    end

    # Returns an array with all the values in `User`. Used for Database query arguments.
    #
    # Values in the array must be in order according to the attributes in the database schema.
    def to_array : Array
      [@id, @username, @realname, @rank, @joined, @left, @last_active, @cooldown_until, @blacklist_text,
       @warnings, @warn_expiry, @karma, @hide_karma, @debug_enabled, @tripcode]
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

    # Set *left* to nil, meaning that User has joined the chat.
    def rejoin : Nil
      @left = nil
      Log.info{"User #{@id}, aka #{self.get_formatted_name}, rejoined the chat."}
    end

    # Set *last_active* to the current time.
    def set_active : Nil
      @last_active = Time.local
    end
    
    # Set *left* to the current time; user has left the chat.
    def set_left : Nil
      @left = Time.local
      Log.info{"User #{@id}, aka #{self.get_formatted_name}, left the chat."}
    end

    def blacklist(reason : String | Nil) : Nil
      @rank = -10
      self.set_left
      @blacklist_text = reason
      Log.info{"User #{@id}, aka #{self.get_formatted_name}, has been blacklisted#{reason ? " for: #{reason}" : "."}"}
    end

    def set_rank(rank : Ranks) : Nil
      if @rank <= rank.value
        @rank = rank.value
        Log.info{"User #{@id}, aka #{self.get_formatted_name}, has been promoted to #{rank.to_s.downcase()}."}
      else
        @rank = rank.value
        Log.info{"User #{@id}, aka #{self.get_formatted_name}, has been demoted."}
      end
    end

    #####################
    # Predicate methods #
    #####################

    # Returns `true` if *rank* is -10; user is blacklisted.
    #
    # Returns `false` otherwise.
    def blacklisted?
      @rank == -10
    end

    # Returns `true` if *left* is not nil; user has left the chat.
    #
    # Returns `false` otherwise.
    def left?
      @left != nil
    end

  end

  # Queries the database for a user record with the given *id*.
  #
  # Returns a `User` object.
  def get_user(id) : User | Nil
    # This query returns a NamedTuple, the keys must be in order according to the attributes in the schema.
    if result = db.query_one?("SELECT * FROM users WHERE id = ?", id, as: {
        id: Int64, username: String?, realname: String, rank: Int32, joined: Time, left: Time?, 
        last_active: Time, cooldown_until: Time?, blacklist_text: String?, warnings: Int32, 
        warn_expiry: Time?, karma: Int32, hide_karma: Bool, debug_enabled: Bool, tripcode: String?
      })

      User.new(result)
    end
  end

  # Queries the database for blacklisted users who have been banned within the past 48 hours.
  #
  # Returns an array of `User` or `Nil` if no users were found.
  def get_blacklisted_users() : Array(User) | Nil
    users = [] of User
    if result = db.query_all("SELECT * FROM users WHERE rank = -10 AND left > (?)", (Time.local - 48.hours), as: {
      id: Int64, username: String?, realname: String, rank: Int32, joined: Time, left: Time?, 
      last_active: Time, cooldown_until: Time?, blacklist_text: String?, warnings: Int32, 
      warn_expiry: Time?, karma: Int32, hide_karma: Bool, debug_enabled: Bool, tripcode: String?
    }) 
      result.each do |output|
        users << User.new(output)
      end
    end

    return users
  end

  # Queries the database for a user with a given *username*.
  #
  # Returns a `User` object or Nil if no user was found.
  def get_user_by_name(username) : User | Nil
    if result = db.query_one?("SELECT * FROM users WHERE LOWER(username) = ?", username, as: {
        id: Int64, username: String?, realname: String, rank: Int32, joined: Time, left: Time?, 
        last_active: Time, cooldown_until: Time?, blacklist_text: String?, warnings: Int32, 
        warn_expiry: Time?, karma: Int32, hide_karma: Bool, debug_enabled: Bool, tripcode: String?
      })

      User.new(result)
    end
  end

  # Queries the database for all user ids, ordered by highest ranking users first then most active users.
  def get_prioritized_users() : Array(Int64)
    sql = "SELECT id
    FROM users
    WHERE left IS NULL
    ORDER BY rank DESC, lastActive DESC"

    db.query_all(sql, &.read(Int64))
  end
  
  # Inserts a user with the given *id*, *username*, and *realname* into the database.
  #
  # Returns the new `User`.
  def add_user(id, username, realname, rank = 0) : User
    # Prepare values
    user = User.new({id: id, username: username, realname: realname, rank: rank})
    args = user.to_array

    # Prepare query
    sql = "INSERT INTO users VALUES ("
    (args.size - 1).times do 
      sql += "?, "
    end
    sql += "?)"

    # Add user to database
    db.exec(sql, args: args)

    Log.info{"User #{user.id}, aka #{user.get_formatted_name}, joined the chat."}
    user
  end

  # Updates a user record in the database with the current state of *user*.
  def modify_user(user : User)
    # Make a hash with ATTRIBUTES as keys to user values
    args = Hash.zip(ATTRIBUTES, user.to_array)

    # Get ID, delete that key-value from the hash
    id = args.delete(:id)

    # Prepare query
    sql = "UPDATE users SET "
    args.each_key do |key|
      sql += key.to_s + " = ?"
      if key != args.last_key
        sql += ", " 
      end
    end
    sql += " WHERE id = ?"

    # Modify user
    db.exec(sql, args: args.values << id)
  end

  # Yields a `ResultSet` containing the ids of each user in the database.
  def get_ids
    db.query("SELECT id FROM users") do |rs|
      yield rs
    end
  end

  def no_users?
    if(get_ids() do |set| set.move_next end)
      return false
    else
      return true
    end
  end

  # Sets the motd/rules to the given string.
  def set_motd(text : String)
    db.exec("REPLACE INTO system_config VALUES ('motd', ?)", text)
  end

  # Retrieves the motd/rules from the database.
  #
  # Returns the motd as a string, or returns nil if the motd could not be retrieved.
  def get_motd() : String | Nil
    db.query_one?("SELECT value FROM system_config WHERE name = 'motd'", as: String)
  end
  
  # Ensures that the DB schema is usable by the program.
  #
  # This is the same schema used in secretlounge-ng SQLite databases.
  def ensure_schema()
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