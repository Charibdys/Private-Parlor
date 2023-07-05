abstract class History
  abstract class MessageGroup
    getter sender : Int64 = 0
    getter origin_msid : Int64 = 0
    property receivers : Hash(Int64, Int64) = {} of Int64 => Int64
    property sent : Time = Time.utc

    # Creates an instance of `MessageGroup`
    #
    # ## Arguments:
    #
    # `sender_id`
    # :     the id of the user who originally sent this message
    #
    # `msid`
    # :     the messaage ID returned when the new message was sent successfully
    abstract def initialize(sender_id : Int64, msid : Int64)
  end

  getter lifespan : Time::Span = 24.hours
  getter msid_map : Hash(Int64, MessageGroup) = {} of Int64 => MessageGroup

  abstract def initialize(message_life : Time::Span)

  # Creates a new `MessageGroup` with the *sender_id* and its associated *msid*
  #
  # Returns the original msid of the new MessageGroup
  abstract def new_message(sender_id : Int64, msid : Int64) : Int64

  # Adds receiver_id and its associated msid to an existing `MessageGroup`
  def add_to_cache(origin_msid : Int64, msid : Int64, receiver_id : Int64) : Nil
    @msid_map.merge!({msid => @msid_map[origin_msid]})
    @msid_map[origin_msid].receivers.merge!({receiver_id => msid})
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
      {msg.sender => msg.origin_msid}.merge!(msg.receivers)
    else
      {} of Int64 => Int64
    end
  end

  # Returns the receivers *msid* found in the associated `MessageGroup`
  def get_msid(msid : Int64, receiver_id : Int64) : Int64 | Nil
    get_all_msids(msid)[receiver_id]?
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

    user_msgs
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
