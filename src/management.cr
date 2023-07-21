require "sqlite3"
require "option_parser"
require "./management/*"

DATABASES = Hash(String, DB::Database).new

OptionParser.parse do |parser|
  parser.banner = "Usage: management [options] [subcommand] [arguments]"
  parser.separator("Options:")
  parser.on("-d PATH", "--directory=PATH", "Path to a directory to search for databases") do |path|
    find_databases(path)
  end
  parser.on("-p PATH", "--path=PATH", "Path to a database") do |path|
    find_database(path)
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit(0)
  end
  parser.separator("Subcommands:")
  parser.on("find", "Find a user by name or ID") do
    parser.banner = "Usage: find [arguments]"
    parser.on("-i [NAME|ID]", "--identity=[NAME|ID]", "Name or ID of user to search for") do |name|
      if id = name.to_i64?
        find_user(id)
      else
        find_user(name)
      end
    end
  end
  parser.on("list", "List users in database(s)") do
    parser.banner = "Usage: list [arguments]"
    parser.on("-r", "--rank", "List users with a rank") do
      list_ranked_users
    end
    parser.on("-b", "--banned", "List users who are banned") do
      list_banned_users
    end
  end
  parser.on("set", "Sets the rank of a user") do
    parser.banner = "Usage: set -i [NAME|ID] -r RANK"
    parser.on("-i [NAME|ID]", "--identity=[NAME|ID]", "Name or ID of user") do |name|
      parser.on("-r RANK", "--rank=RANK", "Rank to set user to") do |rank|
        if id = name.to_i64?
          set_user_rank(id, rank)
        else
          set_user_rank(name, rank)
        end
      end
    end
    parser.on("-r RANK", "--rank=RANK", "Rank (integer) to set user to") do |rank|
      parser.on("-i [NAME|ID]", "--identity=[NAME|ID]", "Name or ID of user") do |name|
        if id = name.to_i64?
          set_user_rank(id, rank)
        else
          set_user_rank(name, rank)
        end
      end
    end
  end
  parser.on("ban", "Ban a user") do
    parser.banner = "Usage: ban [arguments]"
    parser.on("-i [NAME|ID]", "--identity=[NAME|ID]", "Name or ID of user") do |name|
      if id = name.to_i64?
        ban_user(id)
      else
        ban_user(name)
      end
    end
  end
  parser.on("unban", "Unban a user (Assuming 0 is default rank)") do
    parser.banner = "Usage: unban [arguments]"
    parser.on("-i [NAME|ID]", "--identity=[NAME|ID]", "") do |name|
      if id = name.to_i64?
        unban_user(id)
      else
        unban_user(name)
      end
    end
  end
  parser.on("sync", "Sync blacklists across all databases") do
    parser.banner = "Usage: sync [arguments]"
    parser.on("-d INTERVAL", "--daemon=INTERVAL", "Continuously sync blacklists in the backround") do |interval|
      if repeat = interval.to_i32?
        sync_blacklists(repeat)
      else
        STDERR.puts "ERROR: Sync interval must be an integer."
        exit(1)
      end
    end
    parser.on("-o", "--once", "Sync blacklists once") do
      sync_blacklists
    end
  end
  parser.missing_option do |option|
    STDERR.puts "ERROR: #{option} requires an argument."
    STDERR.puts parser
    exit(1)
  end
  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end
end

def find_databases(path : String) : Nil
  if !File.directory?(path)
    STDERR.puts "ERROR: No directory at #{path}"
    exit(1)
  end

  db_paths = Dir.glob("#{path}/**/*.db", "#{path}./**/*.sqlite")

  if db_paths.empty?
    STDERR.puts "ERROR: No databases found"
    exit(1)
  end

  db_paths.each do |db_path|
    name = Path[db_path].stem

    DATABASES[name] = DB.open("sqlite3://#{Path.new(db_path)}")
  end
end

def find_database(path : String) : Nil
  if File.directory?(path)
    STDERR.puts "ERROR: Path to a directory was given"
    exit(1)
  end
  unless Path[path].extension == ".db" || Path[path].extension == ".sqlite"
    STDERR.puts "ERROR: Expected database path to end in \".db\" or \".sqlite\""
    exit(1)
  end

  name = Path[path].stem

  DATABASES[name] = DB.open("sqlite3://#{Path.new(path)}")
end

def find_user(identity : Int64) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    if user = DatabaseWarden.find_user(db, identity, name)
      puts "#{name} Database:"
      puts "#{user}"
      puts
    else
      puts "User not found in \"#{name}\" database"
    end
  end
end

def find_user(identity : String) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    if user = DatabaseWarden.find_user(db, identity, name)
      puts "#{name} Database:"
      puts "#{user}"
      puts
    else
      puts "User not found in \"#{name}\" database"
    end
  end
end

def list_ranked_users : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    users = DatabaseWarden.list_ranked_users(db, name)
    if users && !users.empty?
      puts "Ranked users in \"#{name}\" database:"
      users.each do |user|
        puts "#{user}"
        puts
      end
    else
      puts "No ranked users found in \"#{name}\" database"
    end
  end
end

def list_banned_users : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    users = DatabaseWarden.list_banned_users(db, name)
    if users && !users.empty?
      puts "Banned users in \"#{name}\" database:"
      users.each do |user|
        puts "#{user}"
        puts
      end
    else
      puts "No banned users found in \"#{name}\" database"
    end
  end
end

def set_user_rank(identity : Int64, rank : String) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  unless new_rank = rank.to_i32?
    STDERR.puts "ERROR: Expected rank to be an integer value"
    exit(1)
  end

  DATABASES.each do |name, db|
    result = DatabaseWarden.set_user_rank(db, identity, new_rank, name)
    if result && result.rows_affected == 0
      puts "No user with that identity found in \"#{name}\" database"
    else
      puts "Successfully set user #{identity} to rank #{rank} in \"#{name}\" database"
    end
  end
end

def set_user_rank(identity : String, rank : String) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  unless new_rank = rank.to_i32?
    STDERR.puts "ERROR: Expected rank to be an integer value"
    exit(1)
  end

  DATABASES.each do |name, db|
    result = DatabaseWarden.set_user_rank(db, identity, new_rank, name)
    if result && result.rows_affected != 0
      puts "Successfully set user #{identity} to rank #{rank} in \"#{name}\" database"
    else
      puts "No user with that identity found in \"#{name}\" database"
    end
  end
end

def ban_user(identity : Int64) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    if DatabaseWarden.find_user(db, identity, name)
      DatabaseWarden.ban_user(db, identity, name)

      puts "Banned user #{identity} in \"#{name}\" database"
    else
      DatabaseWarden.create_banned_user(db, identity, name)

      puts "Added entry for banned user #{identity} in \"#{name}\" database"
    end
  end
end

def ban_user(identity : String) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    if DatabaseWarden.find_user(db, identity, name)
      DatabaseWarden.ban_user(db, identity, name)

      puts "Banned user #{identity} in \"#{name}\" database"
    else
      STDERR.puts "ERROR: Could not find user #{identity} in \"#{name}\" database."
    end
  end
end

def unban_user(identity : Int64) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    if DatabaseWarden.find_user(db, identity, name)
      DatabaseWarden.unban_user(db, identity, name)

      puts "Unbanned user #{identity} in \"#{name}\" database"
    else
      STDERR.puts "Could not unban user #{identity} in \"#{name}\" database because user does not exist there"
    end
  end
end

def unban_user(identity : String) : Nil
  if DATABASES.empty?
    find_databases(".")
  end

  DATABASES.each do |name, db|
    if DatabaseWarden.find_user(db, identity, name)
      DatabaseWarden.unban_user(db, identity, name)

      puts "Unbanned user #{identity} in \"#{name}\" database"
    else
      STDERR.puts "Could not unban user #{identity} in \"#{name}\" database because user does not exist there"
    end
  end
end

def sync_blacklists(interval : Int32) : Nil
  if DATABASES.empty?
    find_databases(".")
  end
  unless DATABASES.size > 1
    STDERR.puts "ERROR: More than one database is required to sync blacklists."
  end

  valid_databases = DATABASES
  time_last_checked = Time.unix(0)

  loop do
    banned_users = Hash(Int64, String).new

    DATABASES.each do |name, db|
      unless users = DatabaseWarden.get_banned_users(db, name, time_last_checked)
        valid_databases.delete(name)
        next
      end
      users.each do |user|
        next if banned_users[user.id]?
        reason = "Banned in another chat" unless reason = user.blacklist_reason
        reason += " [#{name}]"
        banned_users[user.id] = reason
      end
    end

    valid_databases.each do |name, db|
      banned_users.each do |id, reason|
        if user = DatabaseWarden.find_user(db, id, name)
          next if user.rank == -10
          DatabaseWarden.ban_user(db, id, name, reason)
        else
          DatabaseWarden.create_banned_user(db, id, name, reason)
        end
        puts "Banned user #{id} in \"#{name}\" database"
      end
    end

    time_last_checked = Time.utc
    sleep(interval.minutes)
  end
end

def sync_blacklists : Nil
  if DATABASES.empty?
    find_databases(".")
  end
  unless DATABASES.size > 1
    STDERR.puts "ERROR: More than one database is required to sync blacklists."
  end

  valid_databases = DATABASES

  banned_users = Hash(Int64, String).new

  DATABASES.each do |name, db|
    unless users = DatabaseWarden.get_banned_users(db, name)
      valid_databases.delete(name)
      next
    end
    users.each do |user|
      next if banned_users[user.id]?
      reason = "Banned in another chat" unless reason = user.blacklist_reason
      reason += " [#{name}]"
      banned_users[user.id] = reason
    end
  end

  valid_databases.each do |name, db|
    banned_users.each do |id, reason|
      if user = DatabaseWarden.find_user(db, id, name)
        next if user.rank == -10
        DatabaseWarden.ban_user(db, id, name, reason)
      else
        DatabaseWarden.create_banned_user(db, id, name, reason)
      end
      puts "Banned user #{id} in \"#{name}\" database"
    end
  end
end
