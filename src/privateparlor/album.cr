class Album
  property message_ids : Array(Int64)
  property media_ids : Array(Tourmaline::InputMediaPhoto | Tourmaline::InputMediaVideo | Tourmaline::InputMediaAudio | Tourmaline::InputMediaDocument)

  # Creates and instance of `Album`, representing a prepared media group to queue and relay
  #
  # ## Arguments:
  #
  # `msid`
  # :     the message ID of the first media file in the album
  #
  # `media`
  # :     the media type corresponding with the given MSID
  def initialize(msid : Int64, media : Tourmaline::InputMediaPhoto | Tourmaline::InputMediaVideo | Tourmaline::InputMediaAudio | Tourmaline::InputMediaDocument)
    @message_ids = [msid]
    @media_ids = [media]
  end
end
