alias MessageProc = Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message))

class PrivateParlor < Tourmaline::Client
  getter database : Database
  getter history : History | DatabaseHistory
  getter queue : Deque(QueuedMessage)
  getter replies : Replies
  getter tasks : Hash(Symbol, Tasker::Task)
  getter albums : Hash(String, Album)
  getter spam_handler : SpamScoreHandler | Nil

  getter cooldown_time_begin : Array(Int32)
  getter cooldown_time_linear_m : Int32
  getter cooldown_time_linear_b : Int32
  getter warn_expire_hours : Int32
  getter karma_warn_penalty : Int32

  getter allow_media_spoilers : Bool?
  getter media_limit_period : Int32
  getter registration_open : Bool?
  getter full_usercount : Bool?
  getter enable_sign : Bool?
  getter enable_tripsign : Bool?
  getter enable_ranksay : Bool?
  getter sign_limit_interval : Int32
  getter upvote_limit_interval : Int32
  getter downvote_limit_interval : Int32

  # Creates a new instance of `PrivateParlor`.
  #
  # ## Arguments:
  #
  # `config`
  # :     a `Configuration::Config` from parsing the `config.yaml` file
  def initialize(config : Configuration::Config)
    super(bot_token: config.token, set_commands: true)
    Client.default_parse_mode = (Tourmaline::ParseMode::MarkdownV2)

    # Init warn/karma variables
    @cooldown_time_begin = config.cooldown_time_begin
    @cooldown_time_linear_m = config.cooldown_time_linear_m
    @cooldown_time_linear_b = config.cooldown_time_linear_b
    @warn_expire_hours = config.warn_expire_hours
    @karma_warn_penalty = config.karma_warn_penalty

    @allow_media_spoilers = config.allow_media_spoilers
    @media_limit_period = config.media_limit_period
    @registration_open = config.registration_open
    @full_usercount = config.full_usercount
    @enable_sign = config.enable_sign[0]
    @enable_tripsign = config.enable_tripsign[0]
    @enable_ranksay = config.enable_ranksay[0]
    @sign_limit_interval = config.sign_limit_interval
    @upvote_limit_interval = config.upvote_limit_interval
    @downvote_limit_interval = config.downvote_limit_interval

    db = DB.open("sqlite3://#{Path.new(config.database)}") # TODO: We'll want check if this works on Windows later
    @database = Database.new(db, config.ranks)
    @history = get_history_type(db, config)
    @queue = Deque(QueuedMessage).new
    @replies = Replies.new(config.entities, config.locale, config.smileys, config.blacklist_contact, config.salt)
    @spam_handler = SpamScoreHandler.new(config) if config.spam_interval_seconds != 0
    @tasks = register_tasks(config.spam_interval_seconds)
    @albums = {} of String => Album

    initialize_handlers(@replies.command_descriptions, config)
  end

  class QueuedMessage
    getter origin_msid : Int64 | Array(Int64) | Nil
    getter sender : Int64 | Nil
    getter receiver : Int64
    getter reply_to : Int64 | Nil
    getter function : MessageProc

    # Creates an instance of `QueuedMessage`.
    #
    # ## Arguments:
    #
    # `hash`
    # :     a hashcode that refers to the associated `MessageGroup` stored in the message history.
    #
    # `sender`
    # :     the ID of the user who sent this message.
    #
    # `receiver_id`
    # :     the ID of the user who will receive this message.
    #
    # `reply_msid`
    # :     the MSID of a message to reply to. May be `nil` if this message isn't a reply.
    #
    # `function`
    # :     a proc that points to a Tourmaline CoreMethod send function and takes a user ID and MSID as its arguments
    def initialize(
      @origin_msid : Int64 | Array(Int64) | Nil,
      @sender : Int64 | Nil,
      @receiver : Int64,
      @reply_to : Int64 | Nil,
      @function : MessageProc
    )
    end
  end

  class Album
    property message_ids : Array(Int64)
    property media_ids : Array(InputMediaPhoto | InputMediaVideo | InputMediaAudio | InputMediaDocument)

    # Creates and instance of `Album`, representing a prepared media group to queue and relay
    #
    # ## Arguments:
    #
    # `msid`
    # :     the message ID of the first media file in the album
    #
    # `media`
    # :     the media type corresponding with the given MSID
    def initialize(msid : Int64, media : InputMediaPhoto | InputMediaVideo | InputMediaAudio | InputMediaDocument)
      @message_ids = [msid]
      @media_ids = [media]
    end
  end

  class SpamScoreHandler
    getter scores : Hash(Int64, Float32)
    getter sign_last_used : Hash(Int64, Time)
    getter upvote_last_used : Hash(Int64, Time)
    getter downvote_last_used : Hash(Int64, Time)

    getter spam_limit : Float32
    getter spam_limit_hit : Float32

    getter score_base_message : Float32
    getter score_text_character : Float32
    getter score_text_linebreak : Float32
    getter score_animation : Float32
    getter score_audio : Float32
    getter score_document : Float32
    getter score_video : Float32
    getter score_video_note : Float32
    getter score_voice : Float32
    getter score_photo : Float32
    getter score_media_group : Float32
    getter score_poll : Float32
    getter score_forwarded_message : Float32
    getter score_sticker : Float32
    getter score_dice : Float32
    getter score_dart : Float32
    getter score_basketball : Float32
    getter score_soccerball : Float32
    getter score_slot_machine : Float32
    getter score_bowling : Float32
    getter score_venue : Float32
    getter score_location : Float32
    getter score_contact : Float32

    # Creates a new instance of a `SpamScoreHandler`.
    #
    # ## Arguments:
    #
    # `config`
    # :     a `Configuration::Config` passed from initializing a `PrivateParlor`
    def initialize(config : Configuration::Config)
      @scores = {} of Int64 => Float32
      @sign_last_used = {} of Int64 => Time
      @upvote_last_used = {} of Int64 => Time
      @downvote_last_used = {} of Int64 => Time

      # Init spam score constants
      @spam_limit = config.spam_limit
      @spam_limit_hit = config.spam_limit_hit

      @score_base_message = config.score_base_message
      @score_text_character = config.score_text_character
      @score_text_linebreak = config.score_text_linebreak
      @score_animation = config.score_animation
      @score_audio = config.score_audio
      @score_document = config.score_document
      @score_video = config.score_video
      @score_video_note = config.score_video_note
      @score_voice = config.score_voice
      @score_photo = config.score_photo
      @score_media_group = config.score_media_group
      @score_poll = config.score_poll
      @score_forwarded_message = config.score_forwarded_message
      @score_sticker = config.score_sticker
      @score_dice = config.score_dice
      @score_dart = config.score_dart
      @score_basketball = config.score_basketball
      @score_soccerball = config.score_soccerball
      @score_slot_machine = config.score_slot_machine
      @score_bowling = config.score_bowling
      @score_venue = config.score_venue
      @score_location = config.score_location
      @score_contact = config.score_contact
    end

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

  # Determine appropriate `History` type based on given config variables
  def get_history_type(db : DB::Database, config : Configuration::Config) : History | DatabaseHistory
    if config.database_history
      DatabaseHistory.new(db, config.lifetime.hours)
    elsif (config.enable_downvote || config.enable_upvote) && config.enable_warn
      HistoryRatingsAndWarnings.new(config.lifetime.hours)
    elsif config.enable_downvote || config.enable_upvote
      HistoryRatings.new(config.lifetime.hours)
    elsif config.enable_warn
      HistoryWarnings.new(config.lifetime.hours)
    else
      HistoryBase.new(config.lifetime.hours)
    end
  end

  # Initializes CommandHandlers and UpdateHandlers
  # Also checks whether or not a command or media type is enabled via the config, and registers commands with BotFather
  def initialize_handlers(descriptions : Hash(Symbol, String), config : Configuration::Config) : Nil
    {% for command in [
                        "start", "stop", "info", "users", "version", "toggle_karma", "toggle_debug", "tripcode", "motd", "help",
                        "upvote", "downvote", "promote", "demote", "warn", "delete", "uncooldown", "remove", "purge", "blacklist",
                      ] %}

    if config.enable_{{command.id}}[0]
      add_event_handler(
        CommandHandler.new(
          {% if command == "stop" %}
          ["stop", "leave"],
          {% elsif command == "toggle_karma" %}
          ["togglekarma", "toggle_karma"],
          {% elsif command == "toggle_debug" %}
          ["toggledebug", "toggle_debug"],
          {% elsif command == "motd" %}
          ["rules", "motd"],
          {% elsif command == "upvote" %}
          "1", "+",
          {% elsif command == "downvote" %}
          "1", "-",
          {% elsif command == "blacklist" %}
          ["blacklist", "ban"],
          {% else %}
          "{{command.id}}",
          {% end %}
           register: config.enable_{{command.id}}[1],
           description: descriptions[:{{command.id}}]
        ) {|ctx| {{command.id}}_command(ctx)}
      )
    else
      add_event_handler(
        CommandHandler.new(
          {% if command == "stop" %}
          ["stop", "leave"],
          {% elsif command == "toggle_karma" %}
          ["togglekarma", "toggle_karma"],
          {% elsif command == "toggle_debug" %}
          ["toggledebug", "toggle_debug"],
          {% elsif command == "motd" %}
          ["rules", "motd"],
          {% elsif command == "upvote" %}
          "1", "+",
          {% elsif command == "downvote" %}
          "1", "-",
          {% elsif command == "blacklist" %}
          ["blacklist", "ban"],
          {% else %}
          "{{command.id}}",
          {% end %}
           register: config.enable_{{command.id}}[1],
           description: descriptions[:{{command.id}}]
        ) {|ctx| command_disabled(ctx)}
      )
    end

    {% end %}

    # Handle embedded commands (sign, tsign, say) differently
    # These are only here to register the commands with BotFather; the commands cannot be disabled here
    if config.enable_sign[0]
      add_event_handler(CommandHandler.new("/sign", register: config.enable_sign[1], description: descriptions[:sign]) { |ctx| command_disabled(ctx) })
    else
      add_event_handler(CommandHandler.new("/sign", register: config.enable_sign[1], description: descriptions[:sign]) { |ctx| command_disabled(ctx) })
    end

    if config.enable_tripsign[0]
      add_event_handler(CommandHandler.new("/tsign", register: config.enable_tripsign[1], description: descriptions[:tsign]) { |ctx| command_disabled(ctx) })
    else
      add_event_handler(CommandHandler.new("/tsign", register: config.enable_tripsign[1], description: descriptions[:tsign]) { |ctx| command_disabled(ctx) })
    end

    if config.enable_ranksay[0]
      add_event_handler(CommandHandler.new("/ranksay", register: config.enable_ranksay[1], description: descriptions[:ranksay]) { |ctx| command_disabled(ctx) })
    else
      add_event_handler(CommandHandler.new("/ranksay", register: config.enable_ranksay[1], description: descriptions[:ranksay]) { |ctx| command_disabled(ctx) })
    end

    register_commands_with_botfather if @set_commands

    {% for media_type in [
                           "text", "animation", "audio", "document", "video", "video_note", "voice", "photo",
                           "media_group", "poll", "forwarded_message", "sticker", "dice", "dart", "basketball",
                           "soccerball", "slot_machine", "bowling", "venue", "location", "contact",
                         ] %}

    if config.relay_{{media_type.id}}
      add_event_handler(UpdateHandler.new(:{{media_type.id}}) {|update| handle_{{media_type.id}}(update)})
    else
      add_event_handler(UpdateHandler.new(:{{media_type.id}}) {|update| media_disabled(update, "{{media_type.id}}")})
    end

    {% end %}
  end

  # Starts various background tasks and stores them in a hash.
  def register_tasks(spam_interval_seconds : Int32) : Hash
    tasks = {} of Symbol => Tasker::Task
    tasks[:cache] = Tasker.every(@history.lifespan * (1/4)) { @history.expire }
    tasks[:warnings] = Tasker.every(15.minutes) { @database.expire_warnings(warn_expire_hours) }
    if spam = @spam_handler
      tasks[:spam] = Tasker.every(spam_interval_seconds.seconds) { spam.expire }
    end
    tasks
  end

  # User starts the bot and begins receiving messages.
  #
  # If the user is not in the database, this will add the user to it
  #
  # If blacklisted or joined, this will not allow them to rejoin
  #
  # Left users can rejoin the bot with this command
  def start_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end

    if user = database.get_user(info.id)
      if user.blacklisted?
        relay_to_one(nil, user.id, :blacklisted, {"reason" => user.blacklist_reason})
      elsif user.left?
        user.rejoin
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        relay_to_one(message.message_id, user.id, :rejoined)
        Log.info { @replies.substitute_log(:rejoined, {"id" => user.id.to_s, "name" => user.get_formatted_name}) }
      else
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        relay_to_one(message.message_id, user.id, :already_in_chat)
      end
    else
      unless @registration_open
        return relay_to_one(nil, info.id, :registration_closed)
      end

      if database.no_users?
        user = database.add_user(info.id, info.username, info.full_name, database.ranks.keys.max)
      else
        user = database.add_user(info.id, info.username, info.full_name)
      end

      if motd = @database.get_motd
        relay_to_one(nil, user.id, @replies.custom(motd))
      end

      relay_to_one(message.message_id, user.id, :joined)
      Log.info { @replies.substitute_log(:joined, {"id" => user.id.to_s, "name" => user.get_formatted_name}) }
    end
  end

  # Stops the bot for the user.
  #
  # This will set the user status to left, meaning the user will not receive any further messages.
  def stop_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end

    if (user = database.get_user(info.id)) && !user.left?
      user.set_active(info.username, info.full_name)
      user.set_left
      @database.modify_user(user)
      relay_to_one(message.message_id, user.id, :left)
      Log.info { @replies.substitute_log(:left, {"id" => user.id.to_s, "name" => user.get_formatted_name}) }
    end
  end

  # Returns a message containing the user's OID, username, karma, warnings, etc.
  #
  # If this is used with a reply, returns the user info of that message if the invoker is ranked.
  def info_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    if reply = message.reply_message
      unless database.authorized?(user.rank, :ranked_info)
        return relay_to_one(message.message_id, user.id, :fail)
      end
      unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
        return
      end

      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      relay_to_one(message.message_id, user.id, :ranked_info, {
          "oid"            => reply_user.get_obfuscated_id,
          "karma"          => reply_user.get_obfuscated_karma,
          "cooldown_until" => reply_user.remove_cooldown ? nil : @replies.format_time(reply_user.cooldown_until),
        })
    else
      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      relay_to_one(message.message_id, user.id, :user_info, {
        "oid"            => user.get_obfuscated_id,
        "username"       => user.get_formatted_name,
        "rank_val"       => user.rank,
        "rank"           => database.ranks[user.rank]?.try &.name,
        "karma"          => user.karma,
        "warnings"       => user.warnings,
        "warn_expiry"    => @replies.format_time(user.warn_expiry),
        "smiley"         => @replies.format_smiley(user.warnings),
        "cooldown_until" => user.remove_cooldown ? nil : @replies.format_time(user.cooldown_until),
      })
    end
  end

  # Return a message containing the number of users in the bot.
  #
  # If the user is not ranked, or `full_usercount` is false, show the total numbers users.
  # Otherwise, return a message containing the number of joined, left, and blacklisted users.
  def users_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    counts = database.get_user_counts

    if database.authorized?(user.rank, :users) || @full_usercount
      relay_to_one(nil, user.id, :user_count_full, {
        "joined"      => counts[:total] - counts[:left],
        "left"        => counts[:left],
        "blacklisted" => counts[:blacklisted],
        "total"       => counts[:total],
      })
    else
      relay_to_one(nil, user.id, :user_count, {"total" => counts[:total]})
    end
  end

  # Returns a message containing the progam's version.
  def version_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(message.message_id, user.id, @replies.version)
  end

  # Upvotes a message.
  def upvote_command(ctx : CommandHandler::Context) : Nil
    unless (history_with_karma = @history) && history_with_karma.is_a?(HistoryRatingsAndWarnings | HistoryRatings | DatabaseHistory)
      return
    end
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :upvote)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    if (spam = @spam_handler) && spam.spammy_upvote?(user.id, @upvote_limit_interval)
      return relay_to_one(message.message_id, user.id, :upvote_spam)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, :no_reply)
    end
    unless reply_user = database.get_user(history_with_karma.get_sender_id(reply.message_id))
      return
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if history_with_karma.get_sender_id(reply.message_id) == user.id
      return relay_to_one(message.message_id, user.id, :upvoted_own_message)
    end
    if !history_with_karma.add_rating(reply.message_id, user.id)
      return relay_to_one(message.message_id, user.id, :already_voted)
    end

    reply_user.increment_karma
    @database.modify_user(reply_user)
    relay_to_one(message.message_id, user.id, :gave_upvote)
    if !reply_user.hide_karma
      relay_to_one(history_with_karma.get_msid(reply.message_id, reply_user.id), reply_user.id, :got_upvote)
    end
  end

  # Downvotes a message.
  def downvote_command(ctx : CommandHandler::Context) : Nil
    unless (history_with_karma = @history) && history_with_karma.is_a?(HistoryRatingsAndWarnings | HistoryRatings | DatabaseHistory)
      return
    end
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :downvote)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    if (spam = @spam_handler) && spam.spammy_downvote?(user.id, @downvote_limit_interval)
      return relay_to_one(message.message_id, user.id, :downvote_spam)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, :no_reply)
    end
    unless reply_user = database.get_user(history_with_karma.get_sender_id(reply.message_id))
      return
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if history_with_karma.get_sender_id(reply.message_id) == user.id
      return relay_to_one(message.message_id, user.id, :downvoted_own_message)
    end
    if !history_with_karma.add_rating(reply.message_id, user.id)
      return relay_to_one(message.message_id, user.id, :already_voted)
    end

    reply_user.decrement_karma
    @database.modify_user(reply_user)
    relay_to_one(message.message_id, user.id, :gave_downvote)
    if !reply_user.hide_karma
      relay_to_one(history_with_karma.get_msid(reply.message_id, reply_user.id), reply_user.id, :got_downvote)
    end
  end

  # Toggle the user's hide_karma attribute.
  def toggle_karma_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    user.toggle_karma
    @database.modify_user(user)

    relay_to_one(nil, user.id, :toggle_karma, {"toggle" => !user.hide_karma})
  end

  # Toggle the user's toggle_debug attribute.
  def toggle_debug_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    user.toggle_debug
    @database.modify_user(user)

    relay_to_one(nil, user.id, :toggle_debug, {"toggle" => user.debug_enabled})
  end

  # Set/modify/view the user's tripcode.
  def tripcode_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if arg = @replies.get_arg(ctx.message.text)
      if !((index = arg.index('#')) && (0 < index < arg.size - 1)) || arg.includes?('\n') || arg.size > 30
        return relay_to_one(message.message_id, user.id, :invalid_tripcode_format)
      end

      user.set_tripcode(arg)
      @database.modify_user(user)

      results = @replies.generate_tripcode(arg)
      relay_to_one(message.message_id, user.id, :tripcode_set, {"name" => results[:name], "tripcode" => results[:tripcode]})
    else
      relay_to_one(message.message_id, user.id, :tripcode_info, {"tripcode" => user.tripcode})
    end
  end

  ##################
  # ADMIN COMMANDS #
  ##################

  def promote_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :promote)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    unless (args = @replies.get_args(message.text, count: 2)) && (args.size == 2)
      return relay_to_one(message.message_id, user.id, :missing_args)
    end
    unless tuple = database.ranks.find {|k, v| v.name.downcase == args[1].downcase || k == args[1].to_i? }
      return relay_to_one(message.message_id, user.id, :no_rank_found, {
        "ranks" => database.ranks.compact_map {|k, v| v.name if k < user.rank}
      })
    end
    unless promoted_user = database.get_user_by_arg(args[0])
      return relay_to_one(message.message_id, user.id, :no_user_found)
    end
    if tuple[0] <= promoted_user.rank || tuple[0] >= user.rank || tuple[0] == -10 || promoted_user.left?
      return relay_to_one(message.message_id, user.id, :fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    promoted_user.set_rank(tuple[0])
    @database.modify_user(promoted_user)

    unless tuple[0] < 0
      relay_to_one(nil, promoted_user.id, :promoted, {"rank" => tuple[1].name})
    end

    Log.info { @replies.substitute_log(:promoted, {
      "id"      => promoted_user.id.to_s,
      "name"    => promoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    }) }
    relay_to_one(message.message_id, user.id, :success)
  end

  # Returns a ranked user to the user rank
  def demote_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :demote)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    unless (args = @replies.get_args(message.text, count: 2)) && (args.size == 2)
      return relay_to_one(message.message_id, user.id, :missing_args)
    end
    unless tuple = database.ranks.find {|k, v| v.name.downcase == args[1].downcase || k == args[1].to_i? }
      return relay_to_one(message.message_id, user.id, :no_rank_found, {
        "ranks" => database.ranks.compact_map {|k, v| v.name if k < user.rank}
      })
    end
    unless demoted_user = database.get_user_by_arg(args[0])
      return relay_to_one(message.message_id, user.id, :no_user_found)
    end
    if tuple[0] >= demoted_user.rank || tuple[0] >= user.rank || tuple[0] == -10 || demoted_user.left?
      return relay_to_one(message.message_id, user.id, :fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    demoted_user.set_rank(tuple[0])
    @database.modify_user(demoted_user)

    Log.info { @replies.substitute_log(:demoted, {
      "id"      => demoted_user.id.to_s,
      "name"    => demoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    }) }
    relay_to_one(message.message_id, user.id, :success)
  end

  # Warns a message without deleting it. Gives the user who sent the message a warning and a cooldown.
  def warn_command(ctx : CommandHandler::Context) : Nil
    unless (history_with_warnings = @history) && history_with_warnings.is_a?(HistoryRatingsAndWarnings | HistoryWarnings | DatabaseHistory)
      return
    end
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :warn)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, :no_reply)
    end
    unless reply_user = database.get_user(history_with_warnings.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, :not_in_cache)
    end
    unless history_with_warnings.get_warning(reply.message_id) == false
      return relay_to_one(message.message_id, user.id, :already_warned)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    reason = @replies.get_arg(ctx.message.text)

    duration = @replies.format_timespan(reply_user.cooldown_and_warn(
      cooldown_time_begin, cooldown_time_linear_m, cooldown_time_linear_b, warn_expire_hours, karma_warn_penalty
    ))
    history_with_warnings.add_warning(reply.message_id)
    @database.modify_user(reply_user)

    cached_msid = history_with_warnings.get_origin_msid(reply.message_id)

    relay_to_one(cached_msid, reply_user.id, :cooldown_given, {"reason" => reason, "duration" => duration})

    Log.info { @replies.substitute_log(:warned, {
      "id"       => user.id.to_s,
      "name"     => user.get_formatted_name,
      "oid"      => reply_user.get_obfuscated_id,
      "duration" => duration,
      "reason"   => reason,
    }) }
    relay_to_one(message.message_id, user.id, :success)
  end

  # Delete a message from a user, give a warning and a cooldown.
  def delete_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :delete)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, :no_reply)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, :not_in_cache)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    reason = @replies.get_arg(message.text)
    cached_msid = delete_messages(reply.message_id, reply_user.id, reply_user.debug_enabled)

    duration = @replies.format_timespan(reply_user.cooldown_and_warn(
      cooldown_time_begin, cooldown_time_linear_m, cooldown_time_linear_b, warn_expire_hours, karma_warn_penalty
    ))
    @database.modify_user(reply_user)

    relay_to_one(cached_msid, reply_user.id, :message_deleted, {"reason" => reason, "duration" => duration})
    Log.info { @replies.substitute_log(:message_deleted, {
      "id"       => user.id.to_s,
      "name"     => user.get_formatted_name,
      "msid"     => cached_msid.to_s,
      "oid"      => reply_user.get_obfuscated_id,
      "duration" => duration,
      "reason"   => reason,
    }) }
    relay_to_one(message.message_id, user.id, :success)
  end

  # Removes a cooldown and warning from a user if the user is in cooldown.
  def uncooldown_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :uncooldown)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    unless arg = @replies.get_arg(message.text)
      return relay_to_one(message.message_id, user.id, :missing_args)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if arg.size < 5
      unless uncooldown_user = database.get_user_by_oid(arg)
        return relay_to_one(message.message_id, user.id, :no_user_oid_found)
      end
    else
      unless uncooldown_user = database.get_user_by_name(arg)
        return relay_to_one(message.message_id, user.id, :no_user_found)
      end
    end

    if !(cooldown_until = uncooldown_user.cooldown_until)
      return relay_to_one(message.message_id, user.id, :not_in_cooldown)
    end

    uncooldown_user.remove_cooldown(true)
    uncooldown_user.remove_warning(1, warn_expire_hours)
    @database.modify_user(uncooldown_user)

    Log.info { @replies.substitute_log(:removed_cooldown, {
      "id"             => user.id.to_s,
      "name"           => user.get_formatted_name,
      "oid"            => uncooldown_user.get_obfuscated_id,
      "cooldown_until" => cooldown_until,
    }) }
    relay_to_one(message.message_id, user.id, :success)
  end

  # Remove a message from a user without giving a warning or cooldown.
  def remove_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :remove)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, :no_reply)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, :not_in_cache)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    cached_msid = delete_messages(reply.message_id, reply_user.id, reply_user.debug_enabled)

    relay_to_one(cached_msid, reply_user.id, :message_removed, {"reason" => @replies.get_arg(message.text)})
    Log.info { @replies.substitute_log(:message_removed, {
      "id"     => user.id.to_s,
      "name"   => user.get_formatted_name,
      "msid"   => cached_msid.to_s,
      "oid"    => reply_user.get_obfuscated_id,
      "reason" => @replies.get_arg(message.text),
    }) }
    relay_to_one(message.message_id, user.id, :success)
  end

  # Delete all messages from recently blacklisted users.
  def purge_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :purge)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if banned_users = @database.get_blacklisted_users
      delete_msids = 0

      banned_users.each do |banned_user|
        @history.get_msids_from_user(banned_user.id).each do |msid|
          delete_messages(msid, banned_user.id, banned_user.debug_enabled)
          delete_msids += 1
        end
      end

      relay_to_one(message.message_id, user.id, :purge_complete, {"msgs_deleted" => delete_msids})
    end
  end

  # Blacklists a user from the chat, deletes the reply, and removes all the user's incoming and outgoing messages from the queue.
  def blacklist_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless database.authorized?(user.rank, :blacklist)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, :no_reply)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, :not_in_cache)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if reply_user.rank < user.rank
      reason = @replies.get_arg(ctx.message.text)
      reply_user.blacklist(reason)
      @database.modify_user(reply_user)

      # Remove queued messages sent by and directed to blacklisted user.
      @queue.reject! do |msg|
        msg.receiver == user.id || msg.sender == user.id
      end
      cached_msid = delete_messages(reply.message_id, reply_user.id, reply_user.debug_enabled)

      relay_to_one(cached_msid, reply_user.id, :blacklisted, {"reason" => reason})
      Log.info { @replies.substitute_log(:blacklisted, {
        "id"      => reply_user.id.to_s,
        "name"    => reply_user.get_formatted_name,
        "invoker" => user.get_formatted_name,
        "reason"  => reason,
      }) }
      relay_to_one(message.message_id, user.id, :success)
    end
  end

  # Replies with the motd/rules associated with this bot.
  # If the host invokes this command, the motd/rules can be set or modified.
  def motd_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    if arg = @replies.get_arg(ctx.message.text)
      unless database.authorized?(user.rank, :motd_set)
        return relay_to_one(message.message_id, user.id, :fail)
      end
      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      @database.set_motd(arg)
      relay_to_one(message.message_id, user.id, :success)
    else
      unless motd = @database.get_motd
        return
      end
      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      relay_to_one(message.message_id, user.id, @replies.custom(motd))
    end
  end

  # Returns a message containing all the commands that a user can use, according to the user's rank.
  def help_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    case user.rank
    when 10
      relay_to_one(message.message_id, user.id, @replies.mod_help)
    when 100
      relay_to_one(message.message_id, user.id, @replies.admin_help)
    when 1000
      relay_to_one(message.message_id, user.id, @replies.host_help)
    end
  end

  # Sends a message to the user if a disabled command is used
  def command_disabled(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(message.message_id, user.id, :command_disabled)
  end

  # Checks if the text contains a special font or starts a sign command.
  #
  # Returns the given text or a formatted text if it is allowed; nil if otherwise or a sign command could not be used.
  def check_text(text : String, user : Database::User, msid : Int64) : String?
    if !@replies.allow_text?(text)
      return relay_to_one(msid, user.id, :rejected_message)
    end

    case
    when !text.starts_with?('/')
      return text
    when text.starts_with?("/s "), text.starts_with?("/sign ")
      return handle_sign(text, user, msid)
    when text.starts_with?("/t "), text.starts_with?("/tsign ")
      return handle_tripcode(text, user, msid)
    when match = /^\/(.*)say/.match(text).try &.[1]
      return handle_ranksay(match, text, user, msid)
    end
  end

  # Given a command text, checks if signs are enabled, user has private forwards,
  # or sign would be spammy, then returns the argument with a username signature
  def handle_sign(text : String, user : Database::User, msid : Int64) : String?
    unless @enable_sign
      return relay_to_one(msid, user.id, :command_disabled)
    end
    unless database.authorized?(user.rank, :sign)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    if (chat = get_chat(user.id)) && chat.has_private_forwards
      return relay_to_one(msid, user.id, :private_sign)
    end
    if (spam = @spam_handler) && spam.spammy_sign?(user.id, @sign_limit_interval)
      return relay_to_one(msid, user.id, :sign_spam)
    end

    if (args = @replies.get_arg(text)) && args.size > 0
      String.build do |str|
        str << args
        str << @replies.format_user_sign(user.id, user.get_formatted_name)
      end
    end
  end

  # Given a command text, checks if tripcodes are enabled, if tripcode would be spammy,
  # or if user does not have a tripcode set, then returns the argument with a tripcode header
  def handle_tripcode(text : String, user : Database::User, msid : Int64) : String?
    unless @enable_tripsign
      return relay_to_one(msid, user.id, :command_disabled)
    end
    unless database.authorized?(user.rank, :tsign)
      return relay_to_one(message.message_id, user.id, :fail)
    end
    if (spam = @spam_handler) && spam.spammy_sign?(user.id, @sign_limit_interval)
      return relay_to_one(msid, user.id, :sign_spam)
    end
    unless tripkey = user.tripcode
      return relay_to_one(msid, user.id, :no_tripcode_set)
    end

    if (args = @replies.get_arg(text)) && args.size > 0
      pair = @replies.generate_tripcode(tripkey)
      String.build do |str|
        str << @replies.format_tripcode_sign(pair[:name], pair[:tripcode]) << ":"
        str << "\n"
        str << args
      end
    end
  end

  # Given a ranked say command, checks if ranked says are enabled and determines the rank
  # (either given or the user's current rank), then returns the argument with a ranked signature
  def handle_ranksay(rank : String, text : String, user : Database::User, msid : Int64) : String?
    unless @enable_ranksay
      return relay_to_one(msid, user.id, :command_disabled)
    end
    unless (parsed_rank = database.ranks.find {|k, v| v.name == rank}.try &.try &.[1].name) || (parsed_rank = database.ranks[user.rank]?.try &.name if rank == "rank")
      return
    end
    unless parsed_rank && database.authorized?(user.rank, :ranksay)
      return relay_to_one(message.message_id, user.id, :fail)
    end

    if (args = @replies.get_arg(text)) && args.size > 0
      Log.info { @replies.substitute_log(:ranked_message, {
        "id"   => user.id.to_s,
        "name" => user.get_formatted_name,
        "rank" => parsed_rank,
        "text" => args,
      }) }
      String.build do |str|
        str << args
        str << @replies.format_user_say(parsed_rank.to_s)
      end
    end
  end

  # Prepares a text message for relaying.
  def handle_text(update : Tourmaline::Update)
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_from || message.forward_from_chat
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    unless (raw_text = message.text) && (text = check_text(@replies.strip_format(raw_text, message.entities), user, message.message_id))
      return
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score_text(text))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text, link_preview: true, reply_to_message: reply) }
    )
  end

  {% for captioned_type in ["animation", "audio", "document", "video", "video_note", "voice", "photo"] %}
  # Prepares a {{captioned_type}} message for relaying.
  def handle_{{captioned_type.id}}(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    {% if captioned_type == "document" %}
        if message.animation
          return
        end
    {% end %}
    if (message.forward_from || message.forward_from_chat)
      return
    end
    if message.media_group_id
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:{{captioned_type}}))
      return relay_to_one(message.message_id, user.id, :spamming)
    end
    {% if captioned_type == "photo" %}
      file_id = (message.photo.last).file_id
    {% else %}
        unless (file_id = message.{{captioned_type.id}}) && (file_id = file_id.file_id)
          return
        end
    {% end %}


    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if raw_caption = message.caption
      caption = check_text(@replies.strip_format(raw_caption, message.entities), user, message.message_id)
      if caption.nil? # Caption contained a special font or used a disabled command
        return
      end
    end


    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      {% if ["animation", "video", "photo"].includes?(captioned_type) %}
        ->(receiver : Int64, reply : Int64 | Nil) { send_{{captioned_type.id}}(
            receiver, 
            file_id, 
            caption: caption, 
            reply_to_message: reply, 
            has_spoiler: message.has_media_spoiler? && @allow_media_spoilers
            ) }
      {% else %}
        ->(receiver : Int64, reply : Int64 | Nil) { send_{{captioned_type.id}}(receiver, file_id, caption: caption, reply_to_message: reply) }
      {% end %}
    )
  end
  {% end %}

  # Prepares an album message for relaying.
  def handle_media_group(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_from || message.forward_from_chat
      return
    end
    unless album = message.media_group_id
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if caption = message.caption
      caption = @replies.replace_links(caption, message.caption_entities)
    end
    if entities = message.caption_entities
      entities = @replies.remove_entities(entities)
    end

    if media = message.photo.last?
      input = InputMediaPhoto.new(media.file_id, caption: caption, caption_entities: entities, has_spoiler: message.has_media_spoiler? && @allow_media_spoilers)
    elsif media = message.video
      input = InputMediaVideo.new(media.file_id, caption: caption, caption_entities: entities, has_spoiler: message.has_media_spoiler? && @allow_media_spoilers)
    elsif media = message.audio
      input = InputMediaAudio.new(media.file_id, caption: caption, caption_entities: entities)
    elsif media = message.document
      input = InputMediaDocument.new(media.file_id, caption: caption, caption_entities: entities)
    else
      return
    end

    if @albums[album]?
      @albums[album].message_ids << message.message_id
      @albums[album].media_ids << input
    else
      media_group = Album.new(message.message_id, input)
      @albums[album] = media_group

      # Wait an arbitrary amount of time for Telegram MediaGroup updates to come in before relaying the album.
      Tasker.at(500.milliseconds.from_now) {
        unless temp_album = @albums.delete(album)
          next
        end
        if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:album))
          next relay_to_one(message.message_id, user.id, :spamming)
        end

        cached_msids = Array(Int64).new

        temp_album.message_ids.each do |msid|
          cached_msids << @history.new_message(info.id, msid)
        end

        relay(
          message.reply_message,
          user,
          cached_msids,
          ->(receiver : Int64, reply : Int64 | Nil) { send_media_group(receiver, temp_album.media_ids, reply_to_message: reply) }
        )
      }
    end
  end

  # Prepares a poll for relaying.
  def handle_poll(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_from || message.forward_from_chat
      return
    end
    unless poll = message.poll
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:poll))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    cached_msid = @history.new_message(user.id, message.message_id)
    poll_msg = send_poll(
      user.id,
      question: poll.question,
      options: poll.options.map(&.text),
      anonymous: true,
      type: poll.type,
      allows_multiple_answers: poll.allows_multiple_answers,
      correct_option_id: poll.correct_option_id,
      reply_to_message: message.message_id
    )
    @history.add_to_cache(cached_msid, poll_msg.message_id, user.id)

    # Prevent user from receiving a second copy of the poll if debug mode is enabled
    if user.debug_enabled
      user.toggle_debug
    end

    relay(
      message.reply_message,
      user,
      cached_msid,
      ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, poll_msg.message_id) }
    )
  end

  # Prepares a forwarded message for relaying.
  def handle_forwarded_message(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.poll
      unless (poll = message.poll) && (poll.anonymous?)
        return relay_to_one(message.message_id, info.id, :deanon_poll)
      end
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:forward))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
    )
  end

  # Prepares a sticker message for relaying.
  def handle_sticker(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_from || message.forward_from_chat
      return
    end
    unless sticker = message.sticker
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:sticker))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      ->(receiver : Int64, reply : Int64 | Nil) { send_sticker(receiver, sticker.file_id, reply_to_message: reply) }
    )
  end

  {% for luck_type in ["dice", "dart", "basketball", "soccerball", "slot_machine", "bowling"] %}
  # Prepares a {{luck_type}} message for relaying.
  def handle_{{luck_type.id}}(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if (message.forward_from || message.forward_from_chat)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:{{luck_type}}))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      ->(receiver : Int64, reply : Int64 | Nil) { send_{{luck_type.id}}(receiver, reply_to_message: reply) }
    )
  end
  {% end %}

  # Prepares a venue message for relaying.
  def handle_venue(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_from || message.forward_from_chat
      return
    end
    unless venue = message.venue
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:venue))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      ->(receiver : Int64, reply : Int64 | Nil) { send_venue(
        receiver,
        venue.location.latitude,
        venue.location.longitude,
        venue.title,
        venue.address,
        venue.foursquare_id,
        venue.foursquare_type,
        venue.google_place_id,
        venue.google_place_type,
        reply_to_message: reply
      ) }
    )
  end

  # Prepares a location message for relaying.
  def handle_location(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_from || message.forward_from_chat
      return
    end
    unless location = message.location
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:location))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      ->(receiver : Int64, reply : Int64 | Nil) { send_location(
        receiver,
        location.latitude,
        location.longitude,
        reply_to_message: reply
      ) }
    )
  end

  # Prepares a contact message for relaying.
  def handle_contact(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_from || message.forward_from_chat
      return
    end
    unless contact = message.contact
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:contact))
      return relay_to_one(message.message_id, user.id, :spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      ->(receiver : Int64, reply : Int64 | Nil) { send_contact(
        receiver,
        contact.phone_number,
        contact.first_name,
        last_name: contact.last_name,
      ) }
    )
  end

  # Sends a message to the user if a disabled media type is sent
  def media_disabled(update : Tourmaline::Update, type : String) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, :not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(message.message_id, user.id, :media_disabled, {"type" => type})
  end

  # Sends a message to the user explaining why they cannot chat at this time
  def deny_user(user : Database::User) : Nil
    if user.blacklisted?
      relay_to_one(nil, user.id, :blacklisted, {"reason" => user.blacklist_reason})
    elsif cooldown_until = user.cooldown_until
      relay_to_one(nil, user.id, :on_cooldown, {"time" => @replies.format_time(cooldown_until)})
    elsif Time.utc - user.joined < @media_limit_period.hours
      relay_to_one(nil, user.id, :media_limit, {"total" => (@media_limit_period.hours - (Time.utc - user.joined)).hours})
    else
      relay_to_one(nil, user.id, :not_in_chat)
    end
  end

  # Deletes the given message for all receivers and removes it from the message history.
  #
  # Returns the sender's (user_id) original message id upon success.
  def delete_messages(msid : Int64, user_id : Int64, debug_enabled : Bool?) : Int64?
    if reply_msids = @history.get_all_msids(msid)
      if !debug_enabled
        reply_msids.delete(user_id)
      end

      reply_msids.each do |receiver_id, receiver_msid|
        delete_message(receiver_id, receiver_msid)
      end

      @history.del_message_group(msid)
    end
  end

  # Caches a message and sends it to the queue for relaying.
  def relay(reply_message : Tourmaline::Message?, user : Database::User, cached_msid : Int64 | Array(Int64), proc : MessageProc) : Nil
    if reply_message
      if (reply_msids = @history.get_all_msids(reply_message.message_id)) && (!reply_msids.empty?)
        @database.get_prioritized_users.each do |receiver_id|
          if (receiver_id != user.id) || user.debug_enabled
            add_to_queue(cached_msid, user.id, receiver_id, reply_msids[receiver_id], proc)
          end
        end
      else # Reply does not exist in cache; remove this message from cache
        relay_to_one(cached_msid.is_a?(Int64) ? cached_msid : cached_msid[0], user.id, :not_in_cache)
        if cached_msid.is_a?(Int64)
          @history.del_message_group(cached_msid)
        else
          cached_msid.each { |msid| @history.del_message_group(msid) }
        end
      end
    else
      @database.get_prioritized_users.each do |receiver_id|
        if (receiver_id != user.id) || user.debug_enabled
          add_to_queue(cached_msid, user.id, receiver_id, nil, proc)
        end
      end
    end
  end

  # Relay a message to a single user. Used for system messages.
  def relay_to_one(reply_message : Int64?, user : Int64, text : String)
    proc = ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text, link_preview: true, reply_to_message: reply) }
    if reply_message
      add_to_queue_priority(user, reply_message, proc)
    else
      add_to_queue_priority(user, nil, proc)
    end
  end

  # :ditto:
  def relay_to_one(reply_message : Int64?, user : Int64, key : Symbol, params : LocaleParameters = {"" => ""}) : Nil
    proc = ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.substitute_reply(key, params), link_preview: true, reply_to_message: reply) }
    if reply_message
      add_to_queue_priority(user, reply_message, proc)
    else
      add_to_queue_priority(user, nil, proc)
    end
  end

  ###################
  # Queue functions #
  ###################

  # Creates a new `QueuedMessage` and pushes it to the back of the queue.
  def add_to_queue(cached_msid : Int64 | Array(Int64), sender_id : Int64 | Nil, receiver_id : Int64, reply_msid : Int64 | Nil, func : MessageProc) : Nil
    @queue.push(QueuedMessage.new(cached_msid, sender_id, receiver_id, reply_msid, func))
  end

  # Creates a new `QueuedMessage` and pushes it to the front of the queue.
  def add_to_queue_priority(receiver_id : Int64, reply_msid : Int64 | Nil, func : MessageProc) : Nil
    @queue.unshift(QueuedMessage.new(nil, nil, receiver_id, reply_msid, func))
  end

  # Receives a `Message` from the `queue`, calls its proc, and adds the returned message id to the History
  #
  # This function should be invoked in a Fiber.
  def send_messages(msg : QueuedMessage) : Nil
    success = msg.function.call(msg.receiver, msg.reply_to)
    if msg.origin_msid != nil
      if !success.is_a?(Array(Tourmaline::Message))
        @history.add_to_cache(msg.origin_msid.as(Int64), success.message_id, msg.receiver)
      else
        sent_msids = success.map(&.message_id)

        sent_msids.zip(msg.origin_msid.as(Array(Int64))) do |msid, origin_msid|
          @history.add_to_cache(origin_msid, msid, msg.receiver)
        end
      end
    end
  rescue Tourmaline::Error::BotBlocked | Tourmaline::Error::UserDeactivated
    force_leave(msg.receiver)
  rescue ex
    Log.error(exception: ex) { "Error occured when relaying message." }
  end

  # Set blocked user to left in the database and delete all incoming messages from the queue.
  def force_leave(user_id : Int64) : Nil
    if user = database.get_user(user_id)
      user.set_left
      @database.modify_user(user)
      Log.info { @replies.substitute_log(:force_leave, {"id" => user_id.to_s}) }
    end
    queue.reject! do |msg|
      msg.receiver == user_id
    end
  end
end
