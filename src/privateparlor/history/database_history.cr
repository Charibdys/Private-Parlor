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
      "SELECT DISTINCT senderID
      FROM message_groups
      JOIN receivers ON receivers.messageGroupID = message_groups.messageGroupID
      WHERE receivers.receiverMSID = ? OR message_groups.messageGroupID = ?",
      msid, msid,
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
      ON DELETE CASCADE
    )")
    db.exec("CREATE TABLE IF NOT EXISTS karma (
      messageGroupID BIGINT NOT NULL,
      userID BIGINT NOT NULL,
      PRIMARY KEY (messageGroupID),
      FOREIGN KEY (messageGroupID) REFERENCES receivers(receiverMSID)
      ON DELETE CASCADE
    )")
  end
end
