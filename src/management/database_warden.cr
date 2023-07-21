module DatabaseWarden
  extend self

  def find_user(db : DB::Database, id : Int64, db_name : String) : User?
    return db.query_one?("SELECT * FROM users WHERE id = ?", id, as: User)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      find_user(db, id, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def find_user(db : DB::Database, name : String, db_name : String) : User?
    return db.query_one?("SELECT * FROM users WHERE realname = ? OR username = ?", name, name, as: User)
  rescue DB::Error
    STDERR.puts "ERROR: Querying \"#{db_name}\" database for user #{name} returned multiple users. Please use a user ID for this operation."
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      find_user(db, name, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def list_ranked_users(db : DB::Database, db_name : String) : Array(User)?
    return db.query_all("SELECT * FROM users WHERE rank > 0", as: User)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      list_ranked_users(db, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def list_banned_users(db : DB::Database, db_name : String) : Array(User)?
    return db.query_all("SELECT * FROM users WHERE rank = -10", as: User)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      list_banned_users(db, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def set_user_rank(db : DB::Database, id : Int64, rank : Int32, db_name : String) : DB::ExecResult?
    return db.exec("UPDATE users SET rank = ? WHERE id = ?", rank, id)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      set_user_rank(db, id, rank, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def set_user_rank(db : DB::Database, name : String, rank : Int32, db_name : String) DB::ExecResult?
    return db.exec("UPDATE users SET rank = ? WHERE realname = ? OR username = ?", rank, name, name)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      set_user_rank(db, name, rank, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def ban_user(db : DB::Database, id : Int64, db_name : String) DB::ExecResult?
    return db.exec("UPDATE users SET rank = ?, left = ? WHERE id = ?", -10, Time.utc, id)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      ban_user(db, id, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def ban_user(db : DB::Database, id : Int64, db_name : String, reason : String = "") DB::ExecResult?
    return db.exec("UPDATE users SET rank = ?, left = ?, blacklistReason = ? WHERE id = ?", -10, Time.utc, reason, id)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      ban_user(db, id, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def ban_user(db : DB::Database, name : String, db_name : String) DB::ExecResult?
    return db.exec("UPDATE users SET rank = ?, left = ? WHERE realname = ? OR username = ?", -10, Time.utc, name, name)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      ban_user(db, name, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def create_banned_user(db : DB::Database, id : Int64, db_name : String, reason : String = "") DB::ExecResult?
    return db.exec(
      "INSERT INTO users (id, realname, rank, joined, left, lastActive, warnings, karma, hideKarma, debugEnabled, blacklistReason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", 
      id, "BLACKLISTED", -10, Time.utc, Time.utc, Time.utc, 0, 0, 0, 0, reason,
    )
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      create_banned_user(db, id, db_name, reason)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def unban_user(db : DB::Database, id : Int64, db_name : String) DB::ExecResult?
    return db.exec("UPDATE users SET rank = ? WHERE id = ?", 0, id)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      unban_user(db, id, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def unban_user(db : DB::Database, name : String, db_name : String) DB::ExecResult?
    return db.exec("UPDATE users SET rank = ? WHERE realname = ? OR username = ?", 0, name, name)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      unban_user(db, name, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def get_banned_users(db : DB::Database, db_name : String) Array(User)?
    return db.query_all("SELECT * FROM users WHERE rank = -10", as: User)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      get_banned_users(db, db_name)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end

  def get_banned_users(db : DB::Database, db_name : String, time : Time) Array(User)?
    return db.query_all("SELECT * FROM users WHERE rank = -10 AND left >= ?", time, as: User)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      get_banned_users(db, db_name, time)
    else
      STDERR.puts "ERROR: Exception occurred when querying the \"#{db_name}\" database; ensure that it contains a valid Private Parlor schema"
    end
  end
end