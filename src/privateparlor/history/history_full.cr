class HistoryFull < History
  class MessageGroupFull < MessageGroup
    property ratings : Set(Int64)
    property warned : Bool?

    # :inherit:
    def initialize(sender_id : Int64, msid : Int64)
      @sender = sender_id
      @origin_msid = msid
      @ratings = Set(Int64).new
      @warned = false
    end
  end

  def initialize(message_life : Time::Span)
    @lifespan = message_life
    @msid_map = {0 => MessageGroupFull.new(0, 0)} of Int64 => MessageGroup
    @msid_map.delete(0)
  end

  # Creates a new `MessageGroup` with the *sender_id* and its associated *msid*
  #
  # Returns the original msid of the new MessageGroup
  def new_message(sender_id : Int64, msid : Int64) : Int64
    message = MessageGroupFull.new(sender_id, msid)
    @msid_map.merge!({msid => message})
    msid
  end

  # Update the ratings set in the associated `MessageGroup`
  #
  # Returns true if the user was added to the ratings set; false if the user was already in it.
  def add_rating(msid : Int64, uid : Int64) : Bool
    @msid_map[msid].as(MessageGroupFull).ratings.add?(uid)
  end

  # Set the warned variable in the associated `MessageGroup`.
  def add_warning(msid : Int64) : Nil
    if msg = @msid_map[msid].as(MessageGroupFull)
      msg.warned = true
    end
  end

  # Returns true if the associated `MessageGroup` was warned; false otherwise.
  def get_warning(msid : Int64) : Bool | Nil
    if msg = @msid_map[msid].as(MessageGroupFull)
      msg.warned
    end
  end
end