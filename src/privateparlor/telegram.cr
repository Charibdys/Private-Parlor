require "./queue/*"
require "./history/*"
require "./locale/*"
require "./rank/*"
require "./config/*"

alias MessageProc = Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message))

class PrivateParlor < Tourmaline::Client
  getter database : Database
  getter history : History | DatabaseHistory
  getter access : AuthorizedRanks
  getter queue : MessageQueue
  getter locale : Locale

  getter tasks : Array(Tasker::Task) = [] of Tasker::Task
  getter albums : Hash(String, Album) = {} of String => Album
  getter spam_handler : SpamScoreHandler | Nil

  getter cooldown_time_begin : Array(Int32)
  getter cooldown_time_linear_m : Int32
  getter cooldown_time_linear_b : Int32
  getter warn_expire_hours : Int32
  getter karma_warn_penalty : Int32

  property log_channel : String
  getter allow_media_spoilers : Bool?
  getter regular_forwards : Bool?
  getter inactivity_limit : Int32
  getter media_limit_period : Int32
  getter registration_open : Bool?
  getter pseudonymous : Bool?
  getter enable_sign : Bool?
  getter enable_tripsign : Bool?
  getter enable_karma_sign : Bool?
  getter enable_ranksay : Bool?
  getter sign_limit_interval : Int32
  getter upvote_limit_interval : Int32
  getter downvote_limit_interval : Int32
  getter smileys : Array(String)
  getter blacklist_contact : String?
  getter tripcode_salt : String
  getter linked_network : Hash(String, String)
  getter entity_types : Array(String)
  getter default_rank : Int32
  getter karma_levels : Hash(Int32, String)
  getter r9k_text : Bool?
  getter r9k_media : Bool?
  getter valid_codepoints : Array(Range(Int32, Int32))

  # Creates a new instance of `PrivateParlor`.
  #
  # ## Arguments:
  #
  # `config`
  # :     a `Config` from parsing the `config.yaml` file
  def initialize(config : Config)
    super(bot_token: config.token, set_commands: true)
    Client.default_parse_mode = (Tourmaline::ParseMode::HTML)

    # Init warn/karma variables
    @cooldown_time_begin = config.cooldown_time_begin
    @cooldown_time_linear_m = config.cooldown_time_linear_m
    @cooldown_time_linear_b = config.cooldown_time_linear_b
    @warn_expire_hours = config.warn_expire_hours
    @karma_warn_penalty = config.karma_warn_penalty

    @log_channel = config.log_channel
    @allow_media_spoilers = config.allow_media_spoilers
    @regular_forwards = config.regular_forwards
    @inactivity_limit = config.inactivity_limit
    @media_limit_period = config.media_limit_period
    @registration_open = config.registration_open
    @pseudonymous = config.pseudonymous
    @enable_sign = config.enable_sign[0]
    @enable_tripsign = config.enable_tripsign[0]
    @enable_karma_sign = config.enable_karma_sign[0]
    @enable_ranksay = config.enable_ranksay[0]
    @sign_limit_interval = config.sign_limit_interval
    @upvote_limit_interval = config.upvote_limit_interval
    @downvote_limit_interval = config.downvote_limit_interval
    @smileys = config.smileys
    @blacklist_contact = config.blacklist_contact
    @tripcode_salt = config.salt
    @linked_network = config.linked_network
    @entity_types = config.entities
    @default_rank = config.default_rank
    @karma_levels = config.karma_levels
    @r9k_text = config.toggle_r9k_text
    @r9k_media = config.toggle_r9k_media
    @valid_codepoints = config.valid_codepoints

    @database = Database.new(DB.open("sqlite3://#{Path.new(config.database)}")) # TODO: We'll want check if this works on Windows later
    @access = AuthorizedRanks.new(config.ranks)
    @history = get_history_type(@database.db, config)
    @queue = MessageQueue.new
    @locale = Localization.parse_locale(config.locale)
    @spam_handler = config.spam_score_handler if config.spam_interval_seconds > 0
    @tasks = register_tasks(config.spam_interval_seconds)

    revert_ranked_users()
    if @r9k_text || @r9k_media
      Robot9000.ensure_r9k_schema(@database.db, config.toggle_r9k_text, config.toggle_r9k_media)
    end
    initialize_handlers(@locale.command_descriptions, config)
  end

  # Determine appropriate `History` type based on given config variables
  def get_history_type(db : DB::Database, config : Config) : History | DatabaseHistory
    if config.database_history
      DatabaseHistory.new(db, config.lifetime.hours)
    elsif (config.enable_downvote || config.enable_upvote) && config.enable_warn
      HistoryFull.new(config.lifetime.hours)
    elsif config.enable_downvote || config.enable_upvote
      HistoryRatings.new(config.lifetime.hours)
    elsif config.enable_warn
      HistoryWarnings.new(config.lifetime.hours)
    else
      HistoryBase.new(config.lifetime.hours)
    end
  end

  # Checks the database for any users that have ranks not found in the `AuthorizedRanks` hash.
  #
  # If the rank is not valid, the user is reverted to the default user rank.
  def revert_ranked_users : Nil
    @database.get_invalid_rank_users(@access.ranks.keys).each do |user|
      invalid_rank = user.rank
      user.set_rank(@default_rank)
      @database.modify_user(user)
      log_output("User #{user.id}, aka #{user.get_formatted_name}, had an invalid rank (was #{invalid_rank}) and was reverted to default rank (#{@default_rank})")
    end
  end

  # Initializes CommandHandlers and UpdateHandlers
  # Also checks whether or not a command or media type is enabled via the config, and registers commands with BotFather
  def initialize_handlers(descriptions : CommandDescriptions, config : Config) : Nil
    {% for command in [
                        "start", "stop", "info", "users", "version", "toggle_karma", "toggle_debug", "reveal", "tripcode", "motd",
                        "help", "upvote", "downvote", "promote", "demote", "warn", "delete", "uncooldown", "remove", "purge",
                        "spoiler", "karma_info", "pin", "unpin", "blacklist", "whitelist",
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
          {% elsif command == "karma_info" %}
          ["karmainfo", "karma_info"],
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
           description: descriptions.{{command.id}}
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
           description: descriptions.{{command.id}}
        ) {|ctx| command_disabled(ctx)}
      )
    end

    {% end %}

    # Handle embedded commands (sign, tsign, say) differently
    # These are only here to register the commands with BotFather; the commands cannot be disabled here
    if config.enable_sign[0]
      add_event_handler(CommandHandler.new("/sign", register: config.enable_sign[1], description: descriptions.sign) { |ctx| command_disabled(ctx) })
    else
      add_event_handler(CommandHandler.new("/sign", register: config.enable_sign[1], description: descriptions.sign) { |ctx| command_disabled(ctx) })
    end

    if config.enable_tripsign[0]
      add_event_handler(CommandHandler.new("/tsign", register: config.enable_tripsign[1], description: descriptions.tsign) { |ctx| command_disabled(ctx) })
    else
      add_event_handler(CommandHandler.new("/tsign", register: config.enable_tripsign[1], description: descriptions.tsign) { |ctx| command_disabled(ctx) })
    end

    if config.enable_karma_sign[0]
      add_event_handler(CommandHandler.new("/ksign", register: config.enable_karma_sign[1], description: descriptions.ksign) { |ctx| command_disabled(ctx) })
    else
      add_event_handler(CommandHandler.new("/ksign", register: config.enable_karma_sign[1], description: descriptions.ksign) { |ctx| command_disabled(ctx) })
    end

    if config.enable_ranksay[0]
      add_event_handler(CommandHandler.new("/ranksay", register: config.enable_ranksay[1], description: descriptions.ranksay) { |ctx| command_disabled(ctx) })
    else
      add_event_handler(CommandHandler.new("/ranksay", register: config.enable_ranksay[1], description: descriptions.ranksay) { |ctx| command_disabled(ctx) })
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
      add_event_handler(UpdateHandler.new(:{{media_type.id}}) {|update| media_disabled(update, {{media_type}})})
    end

    {% end %}
  end

  # Starts various background tasks and stores them in a hash.
  def register_tasks(spam_interval_seconds : Int32) : Array(Tasker::Task)
    tasks = [] of Tasker::Task
    tasks << Tasker.every(15.minutes) { @database.expire_warnings(warn_expire_hours) }
    if @history.lifespan != 0.hours
      tasks << Tasker.every(@history.lifespan * (1/4)) { @history.expire }
    end
    if spam = @spam_handler
      tasks << Tasker.every(spam_interval_seconds.seconds) { spam.expire }
    end
    if @inactivity_limit > 0
      tasks << Tasker.every(6.hours) { kick_inactive_users }
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
        relay_to_one(nil, user.id, @locale.replies.blacklisted, {
          "contact" => Format.format_contact_reply(@blacklist_contact, @locale),
          "reason"  => Format.format_reason_reply(user.blacklist_reason, @locale),
        })
      elsif user.left?
        user.rejoin
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        relay_to_one(message.message_id, user.id, @locale.replies.rejoined)
        log_output(@locale.logs.rejoined, {"id" => user.id.to_s, "name" => user.get_formatted_name})
      else
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        relay_to_one(message.message_id, user.id, @locale.replies.already_in_chat)
      end
    else
      unless @registration_open
        return relay_to_one(nil, info.id, @locale.replies.registration_closed)
      end

      if database.no_users?
        user = database.add_user(info.id, info.username, info.full_name, @access.max_rank)
      else
        user = database.add_user(info.id, info.username, info.full_name, @default_rank)
      end

      if motd = @database.get_motd
        relay_to_one(nil, info.id, motd)
      end

      if @pseudonymous
        relay_to_one(message.message_id, info.id, @locale.replies.joined_pseudonym)
      else
        relay_to_one(message.message_id, info.id, @locale.replies.joined)
      end
      log_output(@locale.logs.joined, {"id" => info.id.to_s, "name" => info.username || info.full_name})
    end
  end

  # Stops the bot for the user.
  #
  # This will set the user status to left, meaning the user will not receive any further messages.
  def stop_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end

    if (user = database.get_user(info.id)) && !user.left?
      user.set_active(info.username, info.full_name)
      user.set_left
      @database.modify_user(user)
      relay_to_one(message.message_id, user.id, @locale.replies.left)
      log_output(@locale.logs.left, {"id" => user.id.to_s, "name" => user.get_formatted_name})
    end
  end

  # Returns a message containing the user's OID, username, karma, warnings, etc.
  #
  # Checks for the following permissions: `ranked_info` (for replies only)
  #
  # If this is used with a reply, returns the user info of that message if the invoker is ranked.
  def info_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    if reply = message.reply_message
      ranked_info(user, info, message.message_id, reply.message_id)
    else
      user_info(user, info, message.message_id)
    end
  end

  def ranked_info(user : Database::User, info : Tourmaline::User, msid : Int64, reply : Int64) : Nil
    unless @access.authorized?(user.rank, :ranked_info)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply))
      return relay_to_one(msid, user.id, @locale.replies.not_in_cache)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    reply_user.remove_cooldown
    cooldown_until = Format.format_cooldown_until(reply_user.cooldown_until, @locale)

    relay_to_one(msid, user.id, @locale.replies.ranked_info, {
      "oid"            => reply_user.get_obfuscated_id.to_s,
      "karma"          => reply_user.get_obfuscated_karma.to_s,
      "cooldown_until" => cooldown_until,
    })
  end

  def user_info(user : Database::User, info : Tourmaline::User, msid : Int64) : Nil
    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if !@karma_levels.empty?
      current_level = ""

      @karma_levels.each_cons_pair do |lower, higher|
        if lower[0] <= user.karma && user.karma < higher[0]
          current_level = lower[1]
          break
        end
      end

      if current_level == "" && user.karma >= @karma_levels.last_key
        current_level = @karma_levels[@karma_levels.last_key]
      elsif user.karma < @karma_levels.first_key
        current_level = "???"
      end
    else
      current_level = ""
    end

    user.remove_cooldown
    cooldown_until = Format.format_cooldown_until(user.cooldown_until, @locale)

    relay_to_one(msid, user.id, @locale.replies.user_info, {
      "oid"            => user.get_obfuscated_id.to_s,
      "username"       => user.get_formatted_name,
      "rank_val"       => user.rank.to_s,
      "rank"           => @access.rank_name(user.rank),
      "karma"          => user.karma.to_s,
      "karma_level"    => current_level.empty? ? nil : "(#{current_level})",
      "warnings"       => user.warnings.to_s,
      "warn_expiry"    => Format.format_warn_expiry(user.warn_expiry, @locale),
      "smiley"         => Format.format_smiley(user.warnings, @smileys),
      "cooldown_until" => cooldown_until,
    })
  end

  # Return a message containing the number of users in the bot.
  #
  # Checks for the following permissions: `users`
  #
  # If the user does not have the "users" permission, show the total numbers of users.
  # Otherwise, return a message containing the number of joined, left, and blacklisted users.
  def users_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    counts = database.get_user_counts

    if @access.authorized?(user.rank, :users)
      relay_to_one(nil, user.id, @locale.replies.user_count_full, {
        "joined"      => (counts[:total] - counts[:left]).to_s,
        "left"        => counts[:left].to_s,
        "blacklisted" => counts[:blacklisted].to_s,
        "total"       => counts[:total].to_s,
      })
    else
      relay_to_one(nil, user.id, @locale.replies.user_count, {"total" => counts[:total].to_s})
    end
  end

  # Returns a message containing the progam's version.
  def version_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(message.message_id, user.id, Format.format_version)
  end

  # Upvotes a message.
  #
  # Checks for the following permissions: `upvote`
  #
  # If `upvote`, allows the user to upvote a message
  def upvote_command(ctx : CommandHandler::Context) : Nil
    unless (history_with_karma = @history) && history_with_karma.is_a?(HistoryFull | HistoryRatings | DatabaseHistory)
      return
    end
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :upvote)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(history_with_karma.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end
    if (spam = @spam_handler) && spam.spammy_upvote?(user.id, @upvote_limit_interval)
      return relay_to_one(message.message_id, user.id, @locale.replies.upvote_spam)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if history_with_karma.get_sender_id(reply.message_id) == user.id
      return relay_to_one(message.message_id, user.id, @locale.replies.upvoted_own_message)
    end
    if !history_with_karma.add_rating(reply.message_id, user.id)
      return relay_to_one(message.message_id, user.id, @locale.replies.already_voted)
    end

    reply_user.increment_karma
    @database.modify_user(reply_user)
    relay_to_one(message.message_id, user.id, @locale.replies.gave_upvote)
    if !reply_user.hide_karma
      relay_to_one(history_with_karma.get_msid(reply.message_id, reply_user.id), reply_user.id, @locale.replies.got_upvote)
    end
  end

  # Downvotes a message.
  #
  # Checks for the following permissions: `downvote`
  #
  # If `downvote`, allows the user to downvote a message
  def downvote_command(ctx : CommandHandler::Context) : Nil
    unless (history_with_karma = @history) && history_with_karma.is_a?(HistoryFull | HistoryRatings | DatabaseHistory)
      return
    end
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :downvote)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(history_with_karma.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end
    if (spam = @spam_handler) && spam.spammy_downvote?(user.id, @downvote_limit_interval)
      return relay_to_one(message.message_id, user.id, @locale.replies.downvote_spam)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if history_with_karma.get_sender_id(reply.message_id) == user.id
      return relay_to_one(message.message_id, user.id, @locale.replies.downvoted_own_message)
    end
    if !history_with_karma.add_rating(reply.message_id, user.id)
      return relay_to_one(message.message_id, user.id, @locale.replies.already_voted)
    end

    reply_user.decrement_karma
    @database.modify_user(reply_user)
    relay_to_one(message.message_id, user.id, @locale.replies.gave_downvote)
    if !reply_user.hide_karma
      relay_to_one(history_with_karma.get_msid(reply.message_id, reply_user.id), reply_user.id, @locale.replies.got_downvote)
    end
  end

  # Toggle the user's hide_karma attribute.
  def toggle_karma_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    user.toggle_karma
    @database.modify_user(user)

    relay_to_one(nil, user.id, @locale.replies.toggle_karma, {
      "toggle" => !user.hide_karma ? locale.toggle[1] : locale.toggle[0],
    })
  end

  # Toggle the user's toggle_debug attribute.
  def toggle_debug_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    user.toggle_debug
    @database.modify_user(user)

    relay_to_one(nil, user.id, @locale.replies.toggle_debug, {
      "toggle" => user.debug_enabled ? locale.toggle[1] : locale.toggle[0],
    })
  end

  # Privately reveal username to another user
  def reveal_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :reveal)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    if (chat = get_chat(user.id)) && chat.has_private_forwards
      return relay_to_one(message.message_id, user.id, @locale.replies.private_sign)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end
    if reply_user.id == user.id
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    if (spam = @spam_handler) && spam.spammy_sign?(user.id, @sign_limit_interval)
      return relay_to_one(message.message_id, user.id, @locale.replies.sign_spam)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(@history.get_msid(reply.message_id, reply_user.id), reply_user.id, Format.format_user_reveal(user.id, user.get_formatted_name, @locale))

    log_output(@locale.logs.revealed, {
      "sender_id"   => user.id.to_s,
      "sender"      => user.get_formatted_name,
      "receiver_id" => reply_user.id.to_s,
      "receiver"    => reply_user.get_formatted_name,
      "msid"        => reply.message_id.to_s,
    })

    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Set/modify/view the user's tripcode.
  def tripcode_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if arg = Format.get_arg(ctx.message.text)
      if !((index = arg.index('#')) && (0 < index < arg.size - 1)) || arg.includes?('\n') || arg.size > 30
        return relay_to_one(message.message_id, user.id, @locale.replies.invalid_tripcode_format)
      end

      user.set_tripcode(arg)
      @database.modify_user(user)

      name, tripcode = Format.generate_tripcode(arg, @tripcode_salt)
      relay_to_one(message.message_id, user.id, @locale.replies.tripcode_set, {"name" => name, "tripcode" => tripcode})
    else
      tripcode = Format.format_tripcode_reply(user.tripcode, @locale)
      relay_to_one(message.message_id, user.id, @locale.replies.tripcode_info, {"tripcode" => tripcode})
    end
  end

  ##################
  # ADMIN COMMANDS #
  ##################

  # Promotes a user to a given rank.
  #
  # Checks for the following permissions: `promote`, `promote_lower`, `promote_same`
  #
  # If `promote`, the reply user can be promoted to a rank lower or equal to the invoker's rank.
  #
  # If `promote_lower`, the reply user can be promoted to a rank lower than the invoker's rank.
  #
  # If `promote_same`, the reply user can only be promoted to the invoker's rank.
  #
  # If used with a reply, the reply user is promoted to the invoker's rank or the given rank.
  def promote_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless authority = @access.authorized?(user.rank, :promote, :promote_lower, :promote_same)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    if reply = message.reply_message
      promote_from_reply(user, info, authority, Format.get_arg(ctx.message.text), message.message_id, reply.message_id)
    else
      promote_from_args(user, info, authority, Format.get_args(message.text, count: 2), message.message_id)
    end
  end

  def promote_from_reply(user : Database::User, info : Tourmaline::User, authority : CommandPermissions, arg : String?, msid : Int64, reply : Int64) : Nil
    if arg.nil? && authority.in?(CommandPermissions::Promote, CommandPermissions::PromoteSame)
      tuple = {user.rank, @access.ranks[user.rank]}
    elsif arg
      tuple = @access.find_rank(arg.downcase, arg.to_i?)
    else
      return relay_to_one(msid, user.id, @locale.replies.missing_args)
    end

    unless tuple
      return relay_to_one(msid, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank).to_s})
    end
    unless promoted_user = database.get_user(@history.get_sender_id(reply))
      return relay_to_one(msid, user.id, @locale.replies.not_in_cache)
    end
    unless @access.can_promote?(tuple[0], user.rank, promoted_user.rank, authority)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    promoted_user.set_rank(tuple[0])
    @database.modify_user(promoted_user)

    relay_to_one(nil, promoted_user.id, @locale.replies.promoted, {"rank" => tuple[1].name})

    log_output(@locale.logs.promoted, {
      "id"      => promoted_user.id.to_s,
      "name"    => promoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    })
    relay_to_one(msid, user.id, @locale.replies.success)
  end

  def promote_from_args(user : Database::User, info : Tourmaline::User, authority : CommandPermissions, args : Array(String) | Nil, msid : Int64) : Nil
    unless args
      return relay_to_one(msid, user.id, @locale.replies.missing_args)
    end

    if args.size == 1 && authority.in?(CommandPermissions::Promote, CommandPermissions::PromoteSame)
      tuple = {user.rank, @access.ranks[user.rank]}
    elsif args.size == 2
      tuple = @access.find_rank(args[1].downcase, args[1].to_i?)
    else
      return relay_to_one(msid, user.id, @locale.replies.missing_args)
    end

    unless tuple
      return relay_to_one(msid, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank).to_s})
    end
    unless promoted_user = database.get_user_by_arg(args[0])
      return relay_to_one(msid, user.id, @locale.replies.no_user_found)
    end
    unless @access.can_promote?(tuple[0], user.rank, promoted_user.rank, authority)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    promoted_user.set_rank(tuple[0])
    @database.modify_user(promoted_user)

    relay_to_one(nil, promoted_user.id, @locale.replies.promoted, {"rank" => tuple[1].name})

    log_output(@locale.logs.promoted, {
      "id"      => promoted_user.id.to_s,
      "name"    => promoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    })
    relay_to_one(msid, user.id, @locale.replies.success)
  end

  # Demotes a user to a given rank.
  #
  # Checks for the following permissions: `demote`
  #
  # If used with a reply, the reply user is demoted to either the user rank or a given rank.
  def demote_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :demote)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    if reply = message.reply_message
      demote_from_reply(user, info, Format.get_arg(ctx.message.text), message.message_id, reply.message_id)
    else
      demote_from_args(user, info, Format.get_args(message.text, count: 2), message.message_id)
    end
  end

  def demote_from_reply(user : Database::User, info : Tourmaline::User, arg : String?, msid : Int64, reply : Int64) : Nil
    if arg.nil?
      tuple = {@default_rank, @access.ranks[@default_rank]}
    elsif arg
      tuple = @access.find_rank(arg.downcase, arg.to_i?)
    else
      return relay_to_one(msid, user.id, @locale.replies.missing_args)
    end

    unless tuple
      return relay_to_one(msid, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank).to_s})
    end
    unless demoted_user = database.get_user(@history.get_sender_id(reply))
      return relay_to_one(msid, user.id, @locale.replies.not_in_cache)
    end
    unless @access.can_demote?(tuple[0], user.rank, demoted_user.rank)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    demoted_user.set_rank(tuple[0])
    @database.modify_user(demoted_user)

    log_output(@locale.logs.demoted, {
      "id"      => demoted_user.id.to_s,
      "name"    => demoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    })
    relay_to_one(msid, user.id, @locale.replies.success)
  end

  def demote_from_args(user : Database::User, info : Tourmaline::User, args : Array(String) | Nil, msid : Int64) : Nil
    unless args && args.size == 2
      return relay_to_one(msid, user.id, @locale.replies.missing_args)
    end

    unless tuple = @access.find_rank(args[1].downcase, args[1].to_i?)
      return relay_to_one(msid, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank).to_s})
    end
    unless demoted_user = database.get_user_by_arg(args[0])
      return relay_to_one(msid, user.id, @locale.replies.no_user_found)
    end
    unless @access.can_demote?(tuple[0], user.rank, demoted_user.rank)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    demoted_user.set_rank(tuple[0])
    @database.modify_user(demoted_user)

    log_output(@locale.logs.demoted, {
      "id"      => demoted_user.id.to_s,
      "name"    => demoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    })
    relay_to_one(msid, user.id, @locale.replies.success)
  end

  # Warns a message without deleting it. Gives the user who sent the message a warning and a cooldown.
  #
  # Checks for the following permissions: `warn`
  #
  # If `warn`, allows the user to warn a message
  def warn_command(ctx : CommandHandler::Context) : Nil
    unless (history_with_warnings = @history) && history_with_warnings.is_a?(HistoryFull | HistoryWarnings | DatabaseHistory)
      return
    end
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :warn)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(history_with_warnings.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end
    unless history_with_warnings.get_warning(reply.message_id) == false
      return relay_to_one(message.message_id, user.id, @locale.replies.already_warned)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    reason = Format.get_arg(message.text)

    duration = Format.format_timespan(
      reply_user.cooldown_and_warn(
        cooldown_time_begin,
        cooldown_time_linear_m,
        cooldown_time_linear_b,
        warn_expire_hours,
        karma_warn_penalty,
      ),
      @locale.time_units
    )
    history_with_warnings.add_warning(reply.message_id)
    @database.modify_user(reply_user)

    cached_msid = history_with_warnings.get_origin_msid(reply.message_id)

    relay_to_one(cached_msid, reply_user.id, @locale.replies.cooldown_given, {"reason" => Format.format_reason_reply(reason, @locale), "duration" => duration})

    log_output(@locale.logs.warned, {
      "id"       => user.id.to_s,
      "name"     => user.get_formatted_name,
      "oid"      => reply_user.get_obfuscated_id,
      "duration" => duration,
      "reason"   => Format.format_reason_log(reason, @locale),
    })
    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Delete a message from a user, give a warning and a cooldown.
  #
  # Checks for the following permissions: `delete`
  #
  # If `delete`, allows the user to delete a message
  def delete_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :delete)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    reason = Format.get_arg(message.text)
    cached_msid = delete_messages(reply.message_id, reply_user.id, reply_user.debug_enabled)

    duration = Format.format_timespan(
      reply_user.cooldown_and_warn(
        cooldown_time_begin,
        cooldown_time_linear_m,
        cooldown_time_linear_b,
        warn_expire_hours,
        karma_warn_penalty
      ),
      @locale.time_units
    )
    @database.modify_user(reply_user)

    relay_to_one(cached_msid, reply_user.id, @locale.replies.message_deleted, {"reason" => Format.format_reason_reply(reason, @locale), "duration" => duration})
    log_output(@locale.logs.message_deleted, {
      "id"       => user.id.to_s,
      "name"     => user.get_formatted_name,
      "msid"     => cached_msid.to_s,
      "oid"      => reply_user.get_obfuscated_id,
      "duration" => duration,
      "reason"   => Format.format_reason_log(reason, @locale),
    })
    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Removes a cooldown and warning from a user if the user is in cooldown.
  #
  # Checks for the following permissions: `uncooldown`
  #
  # If `uncooldown`, allows the user to uncooldown another user
  def uncooldown_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :uncooldown)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless arg = Format.get_arg(message.text)
      return relay_to_one(message.message_id, user.id, @locale.replies.missing_args)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if arg.size < 5
      unless uncooldown_user = database.get_user_by_oid(arg)
        return relay_to_one(message.message_id, user.id, @locale.replies.no_user_oid_found)
      end
    else
      unless uncooldown_user = database.get_user_by_name(arg)
        return relay_to_one(message.message_id, user.id, @locale.replies.no_user_found)
      end
    end

    if !(cooldown_until = uncooldown_user.cooldown_until)
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cooldown)
    end

    uncooldown_user.remove_cooldown(true)
    uncooldown_user.remove_warning(1, warn_expire_hours)
    @database.modify_user(uncooldown_user)

    log_output(@locale.logs.removed_cooldown, {
      "id"             => user.id.to_s,
      "name"           => user.get_formatted_name,
      "oid"            => uncooldown_user.get_obfuscated_id,
      "cooldown_until" => cooldown_until.to_s,
    })
    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Remove a message from a user without giving a warning or cooldown.
  #
  # Checks for the following permissions: `remove`
  #
  # If `remove`, allows the user to remove a message
  def remove_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :remove)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    cached_msid = delete_messages(reply.message_id, reply_user.id, reply_user.debug_enabled)

    reason = Format.get_arg(message.text)

    relay_to_one(cached_msid, reply_user.id, @locale.replies.message_removed, {"reason" => Format.format_reason_reply(reason, @locale)})
    log_output(@locale.logs.message_removed, {
      "id"     => user.id.to_s,
      "name"   => user.get_formatted_name,
      "msid"   => cached_msid.to_s,
      "oid"    => reply_user.get_obfuscated_id,
      "reason" => Format.format_reason_log(reason, @locale),
    })
    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Delete all messages from recently blacklisted users.
  #
  # Checks for the following permissions: `purge`
  #
  # If `purge`, allows the user to run a purge
  def purge_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :purge)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    delete_msids = 0

    if banned_users = @database.get_blacklisted_users
      banned_users.each do |banned_user|
        @history.get_msids_from_user(banned_user.id).each do |msid|
          delete_messages(msid, banned_user.id, banned_user.debug_enabled)
          delete_msids += 1
        end
      end
    end

    relay_to_one(message.message_id, user.id, @locale.replies.purge_complete, {"msgs_deleted" => delete_msids.to_s})
  end

  # Blacklists a user from the chat, deletes the reply, and removes all the user's incoming and outgoing messages from the queue.
  #
  # Checks for the following permissions: `blacklist`
  #
  # If `blacklist`, allows the user to blacklist another user.
  def blacklist_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :blacklist)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end
    unless reply_user.rank < user.rank
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    reason = Format.get_arg(ctx.message.text)
    reply_user.blacklist(reason)
    @database.modify_user(reply_user)

    @queue.reject_messsages do |msg|
      msg.receiver == reply_user.id || msg.sender == reply_user.id
    end

    cached_msid = delete_messages(reply.message_id, reply_user.id, reply_user.debug_enabled)

    relay_to_one(cached_msid, reply_user.id, @locale.replies.blacklisted, {
      "contact" => Format.format_contact_reply(@blacklist_contact, @locale),
      "reason"  => Format.format_reason_reply(reason, @locale),
    })
    log_output(@locale.logs.blacklisted, {
      "id"      => reply_user.id.to_s,
      "name"    => reply_user.get_formatted_name,
      "invoker" => user.get_formatted_name,
      "reason"  => Format.format_reason_log(reason, @locale),
    })
    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Whitelists a user, allowing the user to join the chat. Only applicable if registration is closed
  #
  # Checks for the following permissions: `whitelist`
  #
  # If `whitelist`, allows the user to whitelist another user by user ID.
  def whitelist_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :whitelist)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    if @registration_open
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless (arg = Format.get_arg(message.text)) && (arg = arg.to_i64?)
      return relay_to_one(message.message_id, user.id, @locale.replies.missing_args)
    end
    if @database.get_user(arg)
      return relay_to_one(message.message_id, user.id, @locale.replies.already_whitelisted)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    database.add_user(arg, "", "WHITELISTED", @default_rank)

    # Will throw if user has not started a chat with the bot, or throw and
    # force leave user if bot is blocked, but user is still whitelisted
    begin
      relay_to_one(nil, arg, @locale.replies.added_to_chat)
    end

    log_output(@locale.logs.whitelisted, {
      "id"      => arg.to_s,
      "invoker" => user.get_formatted_name,
    })

    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Adds a spoiler overlay to a media message when replied to.
  #
  # Checks for the following permissions: `spoiler`
  #
  # If `spoiler`, allows the user to add a spoiler to a relayed media message.
  def spoiler_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :spoiler)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    if reply.forward_date
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end
    if (reply_info = reply.from) && user.id == reply_info.id
      # Prevent spoiling messages that were not sent by the bot
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if media = reply.photo.last?
      input = InputMediaPhoto.new(media.file_id, caption: reply.caption, caption_entities: reply.caption_entities)
    elsif media = reply.video
      input = InputMediaVideo.new(media.file_id, caption: reply.caption, caption_entities: reply.caption_entities)
    elsif media = reply.animation
      input = InputMediaAnimation.new(media.file_id, caption: reply.caption, caption_entities: reply.caption_entities)
    else
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    if reply.has_media_spoiler?
      unless spoil_messages(reply.message_id, reply_user.id, reply_user.debug_enabled, input)
        return relay_to_one(message.message_id, user.id, @locale.replies.fail)
      end

      log_output(@locale.logs.unspoiled, {
        "id"   => user.id.to_s,
        "name" => user.get_formatted_name,
        "msid" => reply.message_id.to_s,
      })
    else
      input.has_spoiler = true

      unless spoil_messages(reply.message_id, reply_user.id, reply_user.debug_enabled, input)
        return relay_to_one(message.message_id, user.id, @locale.replies.fail)
      end

      log_output(@locale.logs.spoiled, {
        "id"   => user.id.to_s,
        "name" => user.get_formatted_name,
        "msid" => reply.message_id.to_s,
      })
    end

    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  def karma_info_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    if @karma_levels.empty?
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    current_level = next_level = {0, ""}
    percentage = 0.0_f32

    @karma_levels.each_cons_pair do |lower, higher|
      if lower[0] <= user.karma && user.karma < higher[0]
        current_level = lower
        next_level = higher

        percentage = ((user.karma - lower[0]) * 100) / (higher[0] - lower[0]).to_f32
        break
      end
    end

    # Karma lies outside of bounds
    if current_level == next_level
      if (lowest = @karma_levels.first?) && user.karma < lowest[0]
        current_level = {user.karma, "???"}
        next_level = lowest
      elsif (highest = {@karma_levels.last_key, @karma_levels.last_value}) && user.karma >= highest[0]
        current_level = {user.karma, highest[1]}
        next_level = {highest[0], "???"}
        percentage = 100.0_f32
      end
    end

    relay_to_one(message.message_id, user.id, @locale.replies.karma_info, {
      "current_level" => current_level[1],
      "next_level"    => next_level[1],
      "karma"         => user.karma.to_s,
      "limit"         => next_level[0].to_s,
      "loading_bar"   => Format.format_karma_loading_bar(percentage, @locale),
      "percentage"    => "#{percentage.format(decimal_places: 1, only_significant: true)}",
    })
  end

  def pin_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :pin)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless @history.get_sender_id(reply.message_id)
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    @history.get_all_msids(reply.message_id).each do |receiver_id, receiver_msid|
      active_users = @database.get_prioritized_users
      if receiver_id.in?(active_users)
        pin_chat_message(receiver_id, receiver_msid)
      end
    end

    log_output(@locale.logs.pinned, {
      "id"   => user.id.to_s,
      "name" => user.get_formatted_name,
      "msid" => reply.message_id.to_s,
    })

    # On success, a Telegram system message
    # will be displayed saying that the bot has pinned the message
  end

  def unpin_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :unpin)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    @database.get_prioritized_users.each do |user_id|
      unpin_chat_message(user_id)
    end

    log_output(@locale.logs.unpinned, {
      "id"   => user.id.to_s,
      "name" => user.get_formatted_name,
    })

    relay_to_one(message.message_id, user.id, @locale.replies.success)
  end

  # Replies with the motd/rules associated with this bot.
  #
  # Checks for the following permissions: `motd_set` (only when an argument is given)
  #
  # If the host invokes this command, the motd/rules can be set or modified.
  def motd_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end
    unless text = message.text
      return
    end

    if text.split(2)[1]?
      unless @access.authorized?(user.rank, :motd_set)
        return relay_to_one(message.message_id, user.id, @locale.replies.fail)
      end

      arg = Format.format_motd(text, message.entities, @linked_network)

      if arg.empty?
        return relay_to_one(message.message_id, user.id, @locale.replies.fail)
      end

      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      @database.set_motd(arg)

      log_output(@locale.logs.motd_set, {
        "id"   => user.id.to_s,
        "name" => user.get_formatted_name,
        "text" => arg,
      })

      relay_to_one(message.message_id, user.id, @locale.replies.success)
    else
      unless motd = @database.get_motd
        return
      end
      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      relay_to_one(message.message_id, user.id, motd)
    end
  end

  # Returns a message containing all the commands that a user can use, according to the user's rank.
  def help_command(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(message.message_id, user.id, Format.format_help(user, @access.ranks, @locale))
  end

  # Sends a message to the user if a disabled command is used
  def command_disabled(ctx : CommandHandler::Context) : Nil
    unless (message = ctx.message) && (info = message.from)
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_use_command?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(message.message_id, user.id, @locale.replies.command_disabled)
  end

  # Checks if the text contains a special font or starts a sign command.
  #
  # Returns the given text or a formatted text if it is allowed; nil if otherwise or a sign command could not be used.
  def check_text(text : String, user : Database::User, msid : Int64) : String?
    if @r9k_text
      permit_text = Robot9000.allow_text?(text, @valid_codepoints)
    else
      permit_text = Format.allow_text?(text)
    end
    unless permit_text
      return relay_to_one(msid, user.id, @locale.replies.rejected_message)
    end
    
    case
    when !text.starts_with?('/')
      text
    when text.starts_with?("/s "), text.starts_with?("/sign ")
      handle_sign(text, user, msid)
    when text.starts_with?("/t "), text.starts_with?("/tsign ")
      handle_tripcode(text, user, msid)
    when text.starts_with?("/ks "), text.starts_with?("/ksign ")
      handle_karma_sign(text, user, msid)
    when match = /^\/(\w*)say\s/.match(text).try &.[1]
      handle_ranksay(match, text, user, msid)
    end
  end

  # Given a command text, checks if signs are enabled, user has private forwards,
  # or sign would be spammy, then returns the argument with a username signature
  #
  # Checks for the following permissions: `sign`
  #
  # If `sign`, allows the user to sign a message
  def handle_sign(text : String, user : Database::User, msid : Int64) : String?
    unless @enable_sign
      return relay_to_one(msid, user.id, @locale.replies.command_disabled)
    end
    unless @access.authorized?(user.rank, :sign)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end
    if (chat = get_chat(user.id)) && chat.has_private_forwards
      return relay_to_one(msid, user.id, @locale.replies.private_sign)
    end
    if (spam = @spam_handler) && spam.spammy_sign?(user.id, @sign_limit_interval)
      return relay_to_one(msid, user.id, @locale.replies.sign_spam)
    end

    if (args = Format.get_arg(text)) && args.size > 0
      String.build do |str|
        str << args
        str << Format.format_user_sign(user.id, user.get_formatted_name)
      end
    end
  end

  # Given a command text, checks if tripcodes are enabled, if tripcode would be spammy,
  # or if user does not have a tripcode set, then returns the argument with a tripcode header
  #
  # Checks for the following permissions: `tsign`
  #
  # If `tsign`, allows the user to sign a message with a tripcode.
  def handle_tripcode(text : String, user : Database::User, msid : Int64) : String?
    if @pseudonymous || !@enable_tripsign
      return relay_to_one(msid, user.id, @locale.replies.command_disabled)
    end
    unless @access.authorized?(user.rank, :TSign)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end
    unless tripkey = user.tripcode
      return relay_to_one(msid, user.id, @locale.replies.no_tripcode_set)
    end
    if (spam = @spam_handler) && spam.spammy_sign?(user.id, @sign_limit_interval)
      return relay_to_one(msid, user.id, @locale.replies.sign_spam)
    end

    if (args = Format.get_arg(text)) && args.size > 0
      name, tripcode = Format.generate_tripcode(tripkey, @tripcode_salt)
      String.build do |str|
        str << Format.format_tripcode_sign(name, tripcode) << ":"
        str << "\n"
        str << args
      end
    end
  end

  # Given a command text, checks if karma signs are enabled and if the karma sign
  # would be spammy, then returns the argument with a karma level signature
  def handle_karma_sign(text : String, user : Database::User, msid : Int64) : String?
    unless @enable_karma_sign
      return relay_to_one(msid, user.id, @locale.replies.command_disabled)
    end
    unless (args = Format.get_arg(text)) && args.size > 0
      return relay_to_one(msid, user.id, @locale.replies.missing_args)
    end
    if @karma_levels.empty?
      return
    end
    if user.karma < @karma_levels.first_key
      # Can't sign if one doesn't have a karma rank
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end
    if (spam = @spam_handler) && spam.spammy_sign?(user.id, @sign_limit_interval)
      return relay_to_one(msid, user.id, @locale.replies.sign_spam)
    end

    current_level = ""

    @karma_levels.each_cons_pair do |lower, higher|
      if lower[0] <= user.karma && user.karma < higher[0]
        current_level = lower[1]
        break
      end
    end

    if current_level == "" && user.karma >= @karma_levels.last_key
      current_level = @karma_levels[@karma_levels.last_key]
    end

    String.build do |str|
      str << args
      str << Format.format_karma_say(current_level)
    end
  end

  # Given a ranked say command, checks if ranked says are enabled and determines the rank
  # (either given or the user's current rank), then returns the argument with a ranked signature
  #
  # Checks for the following permissions: `ranksay`, `ranksay_lower`
  #
  # If `ranksay`, allows the user to sign a message with the user's rank name.
  #
  # If `ranksay_lower`, allows the user to sign a message with the user's rank name and any subordinate rank.
  def handle_ranksay(rank : String, text : String, user : Database::User, msid : Int64) : String?
    unless @enable_ranksay
      return relay_to_one(msid, user.id, @locale.replies.command_disabled)
    end
    unless authority = @access.authorized?(user.rank, :ranksay, :ranksay_lower)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end
    unless (args = Format.get_arg(text)) && args.size > 0
      return relay_to_one(msid, user.id, @locale.replies.missing_args)
    end

    if rank == "rank"
      parsed_rank = @access.find_rank(rank, user.rank)
    else
      parsed_rank = @access.find_rank(rank)
    end

    unless parsed_rank
      return relay_to_one(msid, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank).to_s})
    end

    parsed_rank_authority = @access.authorized?(parsed_rank[0], :ranksay, :ranksay_lower)

    unless @access.can_ranksay?(parsed_rank[0], user.rank, authority, parsed_rank_authority)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end

    log_output(@locale.logs.ranked_message, {
      "id"   => user.id.to_s,
      "name" => user.get_formatted_name,
      "rank" => parsed_rank[1].name,
      "text" => args,
    })

    String.build do |str|
      str << args
      str << Format.format_user_say(parsed_rank[1].name)
    end
  end

  # Prepares a text message for relaying.
  def handle_text(update : Tourmaline::Update)
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_date
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :text)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "text"})
    end
    unless (raw_text = message.text) && (text = check_text(Format.strip_format(raw_text, message.entities, @entity_types, @linked_network), user, message.message_id))
      return
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score_text(text))
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
    end
    if @pseudonymous
      unless tripkey = user.tripcode
        return relay_to_one(message.message_id, user.id, @locale.replies.no_tripcode_set)
      end

      text = Format.format_pseudonymous_message(text, tripkey, @tripcode_salt)
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
    if message.forward_date
      return
    end
    if message.media_group_id
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :{{captioned_type}})
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => {{captioned_type}}})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_{{captioned_type.id}})
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
      caption = check_text(Format.strip_format(raw_caption, message.caption_entities, @entity_types, @linked_network), user, message.message_id)
      if caption.nil? # Caption contained a special font or used a disabled command
        return
      end
    end

    if @pseudonymous
      unless tripkey = user.tripcode
        return relay_to_one(message.message_id, user.id, @locale.replies.no_tripcode_set)
      end

      caption = Format.format_pseudonymous_message(caption, tripkey, @tripcode_salt)
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
    if message.forward_date
      return
    end
    unless album = message.media_group_id
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :media_group)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "media_group"})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_media_group)
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if raw_caption = message.caption
      caption = check_text(Format.strip_format(raw_caption, message.caption_entities, @entity_types, @linked_network), user, message.message_id)
      if caption.nil? # Caption contained a special font or used a disabled command
        return
      end
    end

    # If using pseudononymous mode, then only apply tripcode to the the first input file
    if @pseudonymous && @albums[album]? == nil
      unless tripkey = user.tripcode
        return relay_to_one(message.message_id, user.id, @locale.replies.no_tripcode_set)
      end

      caption = Format.format_pseudonymous_message(caption, tripkey, @tripcode_salt)
    end

    relay_album(message, album, user, caption)
  end

  def relay_album(message : Tourmaline::Message, album : String, user : Database::User, caption : String?, entities : Array(MessageEntity) = [] of MessageEntity) : Nil
    if media = message.photo.last?
      input = InputMediaPhoto.new(media.file_id, caption: caption, caption_entities: entities, parse_mode: :HTML, has_spoiler: message.has_media_spoiler? && @allow_media_spoilers)
    elsif media = message.video
      input = InputMediaVideo.new(media.file_id, caption: caption, caption_entities: entities, parse_mode: :HTML, has_spoiler: message.has_media_spoiler? && @allow_media_spoilers)
    elsif media = message.audio
      input = InputMediaAudio.new(media.file_id, caption: caption, caption_entities: entities, parse_mode: :HTML)
    elsif media = message.document
      input = InputMediaDocument.new(media.file_id, caption: caption, caption_entities: entities, parse_mode: :HTML)
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

        cached_msids = Array(Int64).new

        temp_album.message_ids.each do |msid|
          cached_msids << @history.new_message(user.id, msid)
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
    if message.forward_date
      return
    end
    unless poll = message.poll
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :poll)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "poll"})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_poll)
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
        return relay_to_one(message.message_id, info.id, @locale.replies.deanon_poll)
      end
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :forward)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "forwarded_message"})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_forwarded_message)
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if @regular_forwards
      handle_regular_forward(user, message)
    else
      relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
      )
    end
  end

  def handle_regular_forward(user : Database::User, message : Tourmaline::Message) : Nil
    if Format.regular_forward?(message.text || message.caption, message.text_entities.keys)
      return relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
      )
    end

    unless header = Format.get_forward_header(message)
      return relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
      )
    end

    if text = message.text
      text = Format.unparse_text(text, message.entities, Client.default_parse_mode, escape: true)
    elsif text = message.caption
      text = Format.unparse_text(text, message.caption_entities, Client.default_parse_mode, escape: true)
    end

    text = String.build do |str|
      str << header
      str << "\n\n"
      str << text
    end

    relay_regular_forward(user, message, text)
  end

  def relay_regular_forward(user : Database::User, message : Tourmaline::Message, text : String) : Nil
    if message.text
      relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text) }
      )
    elsif album = message.media_group_id
      if @albums[album]?
        relay_album(message, album, user, message.caption, message.caption_entities)
      else
        relay_album(message, album, user, text)
      end
    elsif file = message.animation
      return unless file_id = file.file_id
      relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) {
          send_animation(receiver, file_id, caption: text, has_spoiler: message.has_media_spoiler?)
        }
      )
    elsif file = message.document
      return unless file_id = file.file_id
      relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) {
          send_document(receiver, file_id, caption: text)
        }
      )
    elsif file = message.video
      return unless file_id = file.file_id
      relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) {
          send_video(receiver, file_id, caption: text, has_spoiler: message.has_media_spoiler?)
        }
      )
    elsif file = message.photo
      return unless file_id = file.last.file_id
      relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) {
          send_photo(receiver, file_id, caption: text, has_spoiler: message.has_media_spoiler?)
        }
      )
    else
      relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
      )
    end
  end

  # Prepares a sticker message for relaying.
  def handle_sticker(update : Tourmaline::Update) : Nil
    unless (message = update.message) && (info = message.from)
      return
    end
    if message.forward_date
      return
    end
    unless sticker = message.sticker
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?(@media_limit_period.hours)
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :sticker)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "sticker"})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_sticker)
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
    if message.forward_date
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :{{luck_type}})
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => {{luck_type}}})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_{{luck_type.id}})
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
    if message.forward_date
      return
    end
    unless venue = message.venue
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :venue)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "venue"})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_venue)
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
    if message.forward_date
      return
    end
    unless location = message.location
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :location)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "location"})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_location)
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
    if message.forward_date
      return
    end
    unless contact = message.contact
      return
    end
    unless user = database.get_user(info.id)
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end
    unless @access.authorized?(user.rank, :contact)
      return relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => "contact"})
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.score_contact)
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
      return relay_to_one(nil, info.id, @locale.replies.not_in_chat)
    end
    unless user.can_chat?
      return deny_user(user)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    relay_to_one(message.message_id, user.id, @locale.replies.media_disabled, {"type" => type})
  end

  # Sends a message to the user explaining why they cannot chat at this time
  def deny_user(user : Database::User) : Nil
    if user.blacklisted?
      relay_to_one(nil, user.id, @locale.replies.blacklisted, {
        "contact" => Format.format_contact_reply(@blacklist_contact, @locale),
        "reason"  => Format.format_reason_reply(user.blacklist_reason, @locale),
      })
    elsif cooldown_until = user.cooldown_until
      relay_to_one(nil, user.id, @locale.replies.on_cooldown, {"time" => Format.format_time(cooldown_until, @locale.time_format)})
    elsif Time.utc - user.joined < @media_limit_period.hours
      relay_to_one(nil, user.id, @locale.replies.media_limit, {"total" => (@media_limit_period.hours - (Time.utc - user.joined)).hours.to_s})
    else
      relay_to_one(nil, user.id, @locale.replies.not_in_chat)
    end
  end

  # Kicks any users that have been inactive for a duration of time.
  def kick_inactive_users : Nil
    @database.get_inactive_users(@inactivity_limit).each do |user|
      user.set_left
      @database.modify_user(user)
      @queue.reject_messsages do |msg|
        msg.receiver == user.id
      end
      log_output(@locale.logs.left, {"id" => user.id.to_s, "name" => user.get_formatted_name})
      relay_to_one(nil, user.id, @locale.replies.inactive, {"time" => @inactivity_limit.to_s})
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

  # Spoils the given media message for all receivers by editing the media with the given input.
  #
  # Returns true on success, false or nil otherwise.
  def spoil_messages(msid : Int64, user_id : Int64, debug_enabled : Bool?, input : InputMedia) : Bool?
    if reply_msids = @history.get_all_msids(msid)
      if !debug_enabled
        reply_msids.delete(user_id)
      end

      reply_msids.each do |receiver_id, receiver_msid|
        begin
          edit_message_media(receiver_id, input, receiver_msid)
        rescue Tourmaline::Error::MessageCantBeEdited
          # Either message was a forward or
          # User set debug_mode to true before message was spoiled; simply continue on
        rescue Tourmaline::Error::MessageNotModified
          return false
        end
      end
      return true
    end
  end

  # Caches a message and sends it to the queue for relaying.
  def relay(reply_message : Tourmaline::Message?, user : Database::User, cached_msid : Int64, proc : MessageProc) : Nil
    if reply_message
      if (reply_msids = @history.get_all_msids(reply_message.message_id)) && reply_msids.empty?
        relay_to_one(cached_msid, user.id, @locale.replies.not_in_cache)
        @history.del_message_group(cached_msid)
        return
      end
    end

    @queue.add_to_queue(
      cached_msid,
      user.id,
      @database.get_prioritized_users(user),
      reply_msids,
      proc
    )
  end

  # Caches an album message and sends it to the queue for relaying.
  def relay(reply_message : Tourmaline::Message?, user : Database::User, cached_msid : Array(Int64), proc : MessageProc) : Nil
    if reply_message
      if (reply_msids = @history.get_all_msids(reply_message.message_id)) && reply_msids.empty?
        relay_to_one(cached_msid[0], user.id, @locale.replies.not_in_cache)
        cached_msid.each { |msid| @history.del_message_group(msid) }
        return
      end
    end

    @queue.add_to_queue(
      cached_msid,
      user.id,
      @database.get_prioritized_users(user),
      reply_msids,
      proc
    )
  end

  # Relay a message to a single user. Used for system messages.
  def relay_to_one(reply_message : Int64?, user : Int64, text : String)
    @queue.add_to_queue_priority(
      user,
      reply_message,
      ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text, link_preview: true, reply_to_message: reply) }
    )
  end

  # :ditto:
  def relay_to_one(reply_message : Int64?, user : Int64, reply : String, params : Hash(String, String?)) : Nil
    @queue.add_to_queue_priority(
      user,
      reply_message,
      ->(receiver : Int64, reply_msid : Int64 | Nil) { send_message(receiver, Format.substitute_message(reply, @locale, params), link_preview: true, reply_to_message: reply_msid) }
    )
  end

  # Formats and outputs given log message to the log (either STDOUT or a file, defined in config) with INFO severity.
  #
  # Also outputs message to a given log channel, if available
  def log_output(log : String, params : Hash(String, String?) = {"" => ""}) : Nil
    text = Format.substitute_message(log, @locale, params)

    Log.info { text }
    unless @log_channel.empty?
      send_message(@log_channel, text)
    end
  end

  # Receives a `Message` from the `queue`, calls its proc, and adds the returned message id to the History
  #
  # This function should be invoked in a Fiber.
  def send_messages : Bool?
    msg = @queue.get_message

    if msg.nil?
      return true
    end

    begin
      success = msg.function.call(msg.receiver, msg.reply_to)
    rescue Tourmaline::Error::BotBlocked | Tourmaline::Error::UserDeactivated
      return force_leave(msg.receiver)
    rescue ex
      return Log.error(exception: ex) { "Error occured when relaying message." }
    end

    unless msg.origin_msid
      return
    end

    case success
    when Tourmaline::Message
      @history.add_to_cache(msg.origin_msid.as(Int64), success.message_id, msg.receiver)
    when Array(Tourmaline::Message)
      sent_msids = success.map(&.message_id)

      sent_msids.zip(msg.origin_msid.as(Array(Int64))) do |msid, origin_msid|
        @history.add_to_cache(origin_msid, msid, msg.receiver)
      end
    end
  end

  # Set blocked user to left in the database and delete all incoming messages from the queue.
  #
  # Should only be invoked in `send_messages`, as this does not check the `queue_mutex`
  def force_leave(user_id : Int64) : Nil
    if user = database.get_user(user_id)
      user.set_left
      @database.modify_user(user)
      log_output(@locale.logs.force_leave, {"id" => user_id.to_s})
    end
    @queue.reject_messsages do |msg|
      msg.receiver == user_id
    end
  end
end
