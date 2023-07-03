require "yaml"

class SpamScoreHandler
  include YAML::Serializable

  getter scores : Hash(Int64, Float32) = {} of Int64 => Float32
  getter sign_last_used : Hash(Int64, Time) = {} of Int64 => Time
  getter upvote_last_used : Hash(Int64, Time) = {} of Int64 => Time
  getter downvote_last_used : Hash(Int64, Time) = {} of Int64 => Time

  @[YAML::Field(key: "spam_limit")]
  getter spam_limit : Float32 = 3.0

  @[YAML::Field(key: "spam_limit_hit")]
  getter spam_limit_hit : Float32 = 6.0

  @[YAML::Field(key: "score_base_message")]
  getter score_base_message : Float32 = 0.75

  @[YAML::Field(key: "score_text_character")]
  getter score_text_character : Float32 = 0.002

  @[YAML::Field(key: "score_text_linebreak")]
  getter score_text_linebreak : Float32 = 0.1

  @[YAML::Field(key: "score_animation")]
  getter score_animation : Float32 = 1.0

  @[YAML::Field(key: "score_audio")]
  getter score_audio : Float32 = 1.0

  @[YAML::Field(key: "score_document")]
  getter score_document : Float32 = 1.0

  @[YAML::Field(key: "score_video")]
  getter score_video : Float32 = 1.0

  @[YAML::Field(key: "score_video_note")]
  getter score_video_note : Float32 = 1.5

  @[YAML::Field(key: "score_voice")]
  getter score_voice : Float32 = 1.5

  @[YAML::Field(key: "score_photo")]
  getter score_photo : Float32 = 1.0

  @[YAML::Field(key: "score_media_group")]
  getter score_media_group : Float32 = 2.5

  @[YAML::Field(key: "score_poll")]
  getter score_poll : Float32 = 2.5

  @[YAML::Field(key: "score_forwarded_message")]
  getter score_forwarded_message : Float32 = 1.25

  @[YAML::Field(key: "score_sticker")]
  getter score_sticker : Float32 = 1.5

  @[YAML::Field(key: "score_dice")]
  getter score_dice : Float32 = 2.0

  @[YAML::Field(key: "score_dart")]
  getter score_dart : Float32 = 2.0

  @[YAML::Field(key: "score_basketball")]
  getter score_basketball : Float32 = 2.0

  @[YAML::Field(key: "score_soccerball")]
  getter score_soccerball : Float32 = 2.0

  @[YAML::Field(key: "score_slot_machine")]
  getter score_slot_machine : Float32 = 2.0

  @[YAML::Field(key: "score_bowling")]
  getter score_bowling : Float32 = 2.0

  @[YAML::Field(key: "score_venue")]
  getter score_venue : Float32 = 2.0

  @[YAML::Field(key: "score_location")]
  getter score_location : Float32 = 2.0

  @[YAML::Field(key: "score_contact")]
  getter score_contact : Float32 = 2.0

  # Check if user's spam score triggers the spam filter
  #
  # Returns true if score is greater than spam limit, false otherwise.
  def spammy?(user : Int64, increment : Float32) : Bool
    score = 0 unless score = @scores[user]?

    if score > spam_limit
      return true
    elsif score + increment > spam_limit
      @scores[user] = spam_limit_hit
      return score + increment >= spam_limit_hit
    end

    @scores[user] = score + increment

    false
  end

  # Check if user has signed within an interval of time
  #
  # Returns true if so (user is sign spamming), false otherwise.
  def spammy_sign?(user : Int64, interval : Int32) : Bool
    unless interval == 0
      if last_used = @sign_last_used[user]?
        if (Time.utc - last_used) < interval.seconds
          return true
        else
          @sign_last_used[user] = Time.utc
        end
      else
        @sign_last_used[user] = Time.utc
      end
    end

    false
  end

  # Check if user has upvoted within an interval of time
  #
  # Returns true if so (user is upvoting too often), false otherwise.
  def spammy_upvote?(user : Int64, interval : Int32) : Bool
    unless interval == 0
      if last_used = @upvote_last_used[user]?
        if (Time.utc - last_used) < interval.seconds
          return true
        else
          @upvote_last_used[user] = Time.utc
        end
      else
        @upvote_last_used[user] = Time.utc
      end
    end

    false
  end

  # Check if user has downvoted within an interval of time
  #
  # Returns true if so (user is downvoting too often), false otherwise.
  def spammy_downvote?(user : Int64, interval : Int32) : Bool
    unless interval == 0
      if last_used = @downvote_last_used[user]?
        if (Time.utc - last_used) < interval.seconds
          return true
        else
          @downvote_last_used[user] = Time.utc
        end
      else
        @downvote_last_used[user] = Time.utc
      end
    end

    false
  end

  # Returns the associated spam score contant from a given type
  def calculate_spam_score(type : Symbol) : Float32
    case type
    when :animation
      score_animation
    when :audio
      score_audio
    when :document
      score_document
    when :video
      score_video
    when :video_note
      score_video_note
    when :voice
      score_voice
    when :photo
      score_photo
    when :album
      score_media_group
    when :poll
      score_poll
    when :forward
      score_forwarded_message
    when :sticker
      score_sticker
    when :dice
      score_dice
    when :dart
      score_dart
    when :basketball
      score_basketball
    when :soccerball
      score_soccerball
    when :slot_machine
      score_slot_machine
    when :bowling
      score_bowling
    when :venue
      score_venue
    when :location
      score_location
    when :contact
      score_contact
    else
      score_base_message
    end
  end

  def calculate_spam_score_text(text : String) : Float32
    score_base_message + (text.size * score_text_character) + (text.count('\n') * score_text_linebreak)
  end

  def expire
    @scores.each do |user, score|
      if (score - 1) <= 0
        @scores.delete(user)
      else
        @scores[user] = score - 1
      end
    end
  end
end