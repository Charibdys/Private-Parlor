class History
  getter lifespan : Time::Span
  property msid_map : Hash(Int64, MessageGroup) # MSID => MessageGroup

  # Create an instance of `History`
  #
  # ## Arguments:
  #
  # `message_life`
  # :       how many hours a message may exist before expiring (should be between 1 and 48, inclusive).

  def initialize(message_life : Time::Span)
    @lifespan = message_life
    @msid_map = {} of Int64 => MessageGroup
  end

  class MessageGroup
    getter sender : Int64
    getter origin_msid : Int64
    property receivers : Hash(Int64, Int64)
    property sent : Time
    property ratings : Set(Int64)
    property warned : Bool

    # Creates an instance of `MessageGroup`
    #
    # ## Arguments:
    #
    # `sender_id`
    # :     the id of the user who originally sent this message
    #
    # `msid`
    # :     the messaage ID returned when the new message was sent successfully
    def initialize(sender_id : Int64, msid : Int64)
      @sender = sender_id
      @origin_msid = msid
      @receivers = {} of Int64 => Int64
      @sent = Time.utc
      @ratings = Set(Int64).new
      @warned = false
    end
  end

  # Creates a new `MessageGroup` with the *sender_id* and its associated *msid*
  #
  # Returns the original msid of the new MessageGroup
  def new_message(sender_id : Int64, msid : Int64) : Int64
    message = MessageGroup.new(sender_id, msid)
    @msid_map.merge!({msid => message})
    msid
  end

  # Adds receiver_id and its associated msid to an existing `MessageGroup`
  def add_to_cache(origin_msid : Int64, msid : Int64, receiver_id : Int64) : Nil
    @msid_map.merge!({msid => @msid_map[origin_msid]})
    @msid_map[origin_msid].receivers.merge!({receiver_id => msid})
  end

  # Update the ratings set in the associated `MessageGroup`
  #
  # Returns true if the user was added to the ratings set; false if the user was already in it.
  def add_rating(msid : Int64, uid : Int64) : Bool
    @msid_map[msid].ratings.add?(uid)
  end

  # Set the warned variable in the associated `MessageGroup`.
  def add_warning(msid : Int64) : Nil
    if msg = @msid_map[msid]
      msg.warned = true
    end
  end

  # Returns true if the associated `MessageGroup` was warned; false otherwise.
  def get_warning(msid : Int64) : Bool | Nil
    if msg = @msid_map[msid]
      msg.warned
    end
  end

  # Returns the original MSID of the associated `MessageGroup`
  def get_origin_msid(msid : Int64) : Int64 | Nil
    if msg = @msid_map[msid]
      msg.origin_msid
    end
  end

  # Returns the receivers hash found in the associated `MessageGroup`
  def get_all_msids(msid : Int64) : Hash
    if msg = @msid_map[msid]?
      msg.receivers
    else
      {} of Int64 => Int64
    end
  end

  # Returns the receivers *msid* found in the associated `MessageGroup`
  def get_msid(msid : Int64, receiver_id : Int64) : Int64 | Nil
    if msg = @msid_map[msid]?
      msg.receivers[receiver_id]?
    end
  end

  # Returns the *sender* of a specific `MessageGroup`
  def get_sender_id(msid : Int64) : Int64 | Nil
    if msg = @msid_map[msid]?
      msg.sender
    end
  end

  # Retuns a set containing all msids sent by a given user.
  def get_msids_from_user(uid : Int64) : Set(Int64)
    user_msgs = Set(Int64).new
    @msid_map.each_value do |msg|
      if msg.sender != uid
        next
      end

      user_msgs.add(msg.receivers[uid])
    end
    return user_msgs
  end

  # Deletes a `MessageGroup` from `msid_map`,
  # including any msids that reference this `MessageGroup`
  #
  # Returns the `origin_msid` of the given `MessageGroup`
  def del_message_group(msid : Int64) : Int64
    message = @msid_map[msid]

    message.receivers.each_value do |cached_msid|
      @msid_map.delete(cached_msid)
    end
    @msid_map.delete(message.origin_msid)

    message.origin_msid
  end

  # Returns `true` if message is currently older than the given `lifespan`.
  #
  # Returns `false` otherwise.
  def expired?(message : MessageGroup) : Bool
    message.sent <= Time.utc - @lifespan
  end

  # Delete messages which have expired.
  # Grabs MSIDs from `MessageGroup` receivers and deletes the messages from the history.
  def expire : Nil
    msids = [] of Int64
    count = 0
    @msid_map.each_value do |value|
      if !expired?(value)
        next
      end

      msids << value.receivers.first_value
      count += value.receivers.size
    end

    msids.each do |msid|
      del_message_group(msid)
    end

    if count > 0
      Log.debug { "Expired #{count} messages from the cache" }
    end
  end
end
