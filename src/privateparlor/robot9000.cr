module Robot9000
  extend self

  def ensure_r9k_schema(db : DB::Database, text : Bool?, media : Bool?) : Nil
    if text
      db.exec("
      CREATE TABLE IF NOT EXISTS text (
        line TEXT NOT NULL,
        PRIMARY KEY (line)
      )
      ")
    end
    if media
      db.exec("
      CREATE TABLE IF NOT EXISTS file_id (
        id TEXT NOT NULL,
        PRIMARY KEY (id)
      )
      ")
    end
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      sleep(10.milliseconds)
      ensure_r9k_schema(db, text, media)
    end
  end

end