class HistoryBase < History
  class MessageGroupBase < MessageGroup
    # :inherit:
    def initialize(sender_id : Int64, msid : Int64)
      @sender = sender_id
      @origin_msid = msid
    end
  end

  def initialize(message_life : Time::Span)
    @lifespan = message_life

    # Covariance is not fully supported in Crystal yet, so we must do this:
    @msid_map = {0 => MessageGroupBase.new(0, 0)} of Int64 => MessageGroup
    @msid_map.delete(0)
  end

  def new_message(sender_id : Int64, msid : Int64) : Int64
    message = MessageGroupBase.new(sender_id, msid)
    @msid_map.merge!({msid => message})
    msid
  end
end
