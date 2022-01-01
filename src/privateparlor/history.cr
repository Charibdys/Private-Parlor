class History
  getter lifespan : Int8
  # MSID => MessageGroup hashcode
  property msid_map : Hash(Int64, UInt64)
  # MessageGroup hashcode => MessageGroup
  property message_history : Hash(UInt64, MessageGroup)

  # Create an instance of `History` with a `message_life` for expiring messages.
  def initialize(message_life : Int8)
    @lifespan = message_life
    @msid_map = {} of Int64 => UInt64
    @message_history = {} of UInt64 => MessageGroup
  end

  struct MessageGroup
    getter sender : Int64
    property receivers : Hash(Int64, Int64)
    property sent : Time

    # Create an instance of `MessageGroup`
    def initialize(sender_id : Int64, msid : Int64)
      @sender = sender_id
      @receivers = {sender_id => msid} of Int64 => Int64
      @sent = Time.local
    end

  end

  # Creates a new `MessageGroup` with the *sender_id* and its associated *msid*
  #
  # Returns the initial hashcode of the new MessageGroup
  def new_message(sender_id : Int64, msid : Int64) : UInt64
    message = MessageGroup.new(sender_id, msid)
    hashcode = message.hash
    @message_history.merge!({hashcode => message})
    @msid_map.merge!({msid => hashcode})
    hashcode
  end

  # Adds receiver_id and its associated msid to an existing `MessageGroup`
  def add_to_cache(hashcode : UInt64, msid : Int64, receiver_id : Int64) : Nil
    @msid_map.merge!({msid => hashcode})
    @message_history[hashcode].receivers.merge!({receiver_id => msid})
  end

  # Returns the receivers hash found in the associated `MessageGroup`
  def get_all_msids(msid : Int64) : Hash
    @message_history[@msid_map[msid]].receivers
  end

  # Returns the receivers *msid* found in the associated `MessageGroup`
  def get_msid(msid : Int64, receiver_id : Int64) : Int64
    @message_history[@msid_map[msid]].receivers[receiver_id]
  end

  # Delete message from cache with a hashcode associated with the given *msid*.
  def del_message_group(msid : Int64) : Nil
    hash = @msid_map[msid]
    # Delete message group from history
    @message_history.delete(hash)
    # Delete references from msid_map
    @msid_map.each do |key, value|
      if value == hash
        @msid_map.delete(key)
      end
    end
  end

  # Returns `true` if message is currently older than the given `lifespan`.
  #
  # Returns `false` otherwise.
  def expired?(message : MessageGroup)
    message.sent <= Time.local - @lifespan.hours
  end

  # Delete messages which have expired. 
  # Grabs MSIDs from `MessageGroup` receivers and deletes the messages from the history.
  def expire
    msids = [] of Int64
    count = 0;
    @message_history.each_value do |value|
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
      Log.debug{"Expired #{count} messages from the cache"}
    end
  end

end