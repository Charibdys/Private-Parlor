class HistoryRatings < History
  class MessageGroupRatings < MessageGroup
    property ratings : Set(Int64)

    # :inherit:
    def initialize(sender_id : Int64, msid : Int64)
      @sender = sender_id
      @origin_msid = msid
      @ratings = Set(Int64).new
    end
  end

  def initialize(message_life : Time::Span)
    @lifespan = message_life
    @msid_map = {0 => MessageGroupRatings.new(0, 0)} of Int64 => MessageGroup
    @msid_map.delete(0)
  end

  # Creates a new `MessageGroup` with the *sender_id* and its associated *msid*
  #
  # Returns the original msid of the new MessageGroup
  def new_message(sender_id : Int64, msid : Int64) : Int64
    message = MessageGroupRatings.new(sender_id, msid)
    @msid_map.merge!({msid => message})
    msid
  end

  # Update the ratings set in the associated `MessageGroup`
  #
  # Returns true if the user was added to the ratings set; false if the user was already in it.
  def add_rating(msid : Int64, uid : Int64) : Bool
    @msid_map[msid].as(MessageGroupRatings).ratings.add?(uid)
  end
end
