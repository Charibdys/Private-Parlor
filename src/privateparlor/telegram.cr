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

  getter tasks : Hash(Symbol, Tasker::Task) = {} of Symbol => Tasker::Task
  getter albums : Hash(String, Album) = {} of String => Album
  getter spam_handler : SpamScoreHandler | Nil

  getter cooldown_time_begin : Array(Int32)
  getter cooldown_time_linear_m : Int32
  getter cooldown_time_linear_b : Int32
  getter warn_expire_hours : Int32
  getter karma_warn_penalty : Int32

  getter log_channel : String?
  getter allow_media_spoilers : Bool?
  getter regular_forwards : Bool?
  getter inactivity_limit : Int32
  getter media_limit_period : Int32
  getter registration_open : Bool?
  getter enable_sign : Bool?
  getter enable_tripsign : Bool?
  getter enable_ranksay : Bool?
  getter sign_limit_interval : Int32
  getter upvote_limit_interval : Int32
  getter downvote_limit_interval : Int32
  getter smileys : Array(String)
  getter blacklist_contact : String?
  getter tripcode_salt : String
  getter linked_network : Hash(String, String)
  getter entity_types : Array(String)

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
    @enable_sign = config.enable_sign[0]
    @enable_tripsign = config.enable_tripsign[0]
    @enable_ranksay = config.enable_ranksay[0]
    @sign_limit_interval = config.sign_limit_interval
    @upvote_limit_interval = config.upvote_limit_interval
    @downvote_limit_interval = config.downvote_limit_interval
    @smileys = config.smileys
    @blacklist_contact = config.blacklist_contact
    @tripcode_salt = config.salt
    @linked_network = config.linked_network
    @entity_types = config.entities

    db = DB.open("sqlite3://#{Path.new(config.database)}") # TODO: We'll want check if this works on Windows later
    @database = Database.new(db)
    @access = AuthorizedRanks.new(config.ranks)
    @history = get_history_type(db, config)
    @queue = MessageQueue.new
    @locale = Localization.parse_locale(config.locale)
    @spam_handler = config.spam_score_handler if config.spam_interval_seconds != 0
    @tasks = register_tasks(config.spam_interval_seconds)

    revert_ranked_users()
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
      user.set_rank(0)
      @database.modify_user(user)
      log_output(@log_channel, "User #{user.id}, aka #{user.get_formatted_name}, had an invalid rank (was #{user.rank}) and was reverted to user rank (0)" )
    end
  end

  # Initializes CommandHandlers and UpdateHandlers
  # Also checks whether or not a command or media type is enabled via the config, and registers commands with BotFather
  def initialize_handlers(descriptions : CommandDescriptions, config : Config) : Nil
    {% for command in [
                        "start", "stop", "info", "users", "version", "toggle_karma", "toggle_debug", "tripcode", "motd", "help",
                        "upvote", "downvote", "promote", "demote", "warn", "delete", "uncooldown", "remove", "purge", "spoiler", "blacklist",
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
      add_event_handler(UpdateHandler.new(:{{media_type.id}}) {|update| media_disabled(update, "{{media_type.id}}")})
    end

    {% end %}
  end

  # Starts various background tasks and stores them in a hash.
  def register_tasks(spam_interval_seconds : Int32) : Hash(Symbol, Tasker::Task)
    tasks = {} of Symbol => Tasker::Task
    tasks[:cache] = Tasker.every(@history.lifespan * (1/4)) { @history.expire }
    tasks[:warnings] = Tasker.every(15.minutes) { @database.expire_warnings(warn_expire_hours) }
    if spam = @spam_handler
      tasks[:spam] = Tasker.every(spam_interval_seconds.seconds) { spam.expire }
    end
    if @inactivity_limit > 0
      tasks[:inactivity] = Tasker.every(6.hours) { kick_inactive_users }
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
        relay_to_one(nil, user.id, @locale.replies.blacklisted, {"reason" => user.blacklist_reason})
      elsif user.left?
        user.rejoin
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        relay_to_one(message.message_id, user.id, @locale.replies.rejoined)
        log_output(@log_channel, Format.substitute_log(@locale.logs.rejoined, @locale, {"id" => user.id.to_s, "name" => user.get_formatted_name}))
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
        user = database.add_user(info.id, info.username, info.full_name)
      end

      if motd = @database.get_motd
        relay_to_one(nil, user.id, motd)
      end

      relay_to_one(message.message_id, user.id, @locale.replies.joined)
      log_output(@log_channel, Format.substitute_log(@locale.logs.joined, @locale, {"id" => user.id.to_s, "name" => user.get_formatted_name}))
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
      relay_to_one(message.message_id, user.id, @locale.replies.left)
      log_output(@log_channel, Format.substitute_log(@locale.logs.left, @locale, {"id" => user.id.to_s, "name" => user.get_formatted_name}))
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
      unless @access.authorized?(user.rank, :ranked_info)
        return relay_to_one(message.message_id, user.id, @locale.replies.fail)
      end
      unless reply_user = database.get_user(@history.get_sender_id(reply.message_id))
        return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
      end

      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      relay_to_one(message.message_id, user.id, @locale.replies.ranked_info, {
        "oid"            => reply_user.get_obfuscated_id,
        "karma"          => reply_user.get_obfuscated_karma,
        "cooldown_until" => reply_user.remove_cooldown ? nil : Format.format_time(reply_user.cooldown_until, @locale.time_format),
      })
    else
      user.set_active(info.username, info.full_name)
      @database.modify_user(user)

      relay_to_one(message.message_id, user.id, @locale.replies.user_info, {
        "oid"            => user.get_obfuscated_id,
        "username"       => user.get_formatted_name,
        "rank_val"       => user.rank,
        "rank"           => @access.rank_name(user.rank),
        "karma"          => user.karma,
        "warnings"       => user.warnings,
        "warn_expiry"    => Format.format_time(user.warn_expiry, @locale.time_format),
        "smiley"         => Format.format_smiley(user.warnings, @smileys),
        "cooldown_until" => user.remove_cooldown ? nil : Format.format_time(user.cooldown_until, @locale.time_format),
      })
    end
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
        "joined"      => counts[:total] - counts[:left],
        "left"        => counts[:left],
        "blacklisted" => counts[:blacklisted],
        "total"       => counts[:total],
      })
    else
      relay_to_one(nil, user.id, @locale.replies.user_count, {"total" => counts[:total]})
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
    if (spam = @spam_handler) && spam.spammy_upvote?(user.id, @upvote_limit_interval)
      return relay_to_one(message.message_id, user.id, @locale.replies.upvote_spam)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(history_with_karma.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
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
    if (spam = @spam_handler) && spam.spammy_downvote?(user.id, @downvote_limit_interval)
      return relay_to_one(message.message_id, user.id, @locale.replies.downvote_spam)
    end
    unless reply = message.reply_message
      return relay_to_one(message.message_id, user.id, @locale.replies.no_reply)
    end
    unless reply_user = database.get_user(history_with_karma.get_sender_id(reply.message_id))
      return relay_to_one(message.message_id, user.id, @locale.replies.not_in_cache)
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

    relay_to_one(nil, user.id, @locale.replies.toggle_karma, {"toggle" => !user.hide_karma})
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

    relay_to_one(nil, user.id, @locale.replies.toggle_debug, {"toggle" => user.debug_enabled})
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

      results = Format.generate_tripcode(arg, @tripcode_salt)
      relay_to_one(message.message_id, user.id, @locale.replies.tripcode_set, {"name" => results[:name], "tripcode" => results[:tripcode]})
    else
      relay_to_one(message.message_id, user.id, @locale.replies.tripcode_info, {"tripcode" => user.tripcode})
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
      arg = Format.get_arg(ctx.message.text)

      if arg.nil? && authority.in?(:promote, :promote_same)
        tuple = {user.rank, @access.ranks[user.rank]}
      elsif arg
        tuple = @access.find_rank(arg.downcase, arg.to_i?)
      else
        return relay_to_one(message.message_id, user.id, @locale.replies.missing_args)
      end

      unless tuple
        return relay_to_one(message.message_id, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank)})
      end

      unless (promoted_user = database.get_user(@history.get_sender_id(reply.message_id))) && !promoted_user.left?
        return relay_to_one(message.message_id, user.id, @locale.replies.no_user_found)
      end
    else
      unless args = Format.get_args(message.text, count: 2)
        return relay_to_one(message.message_id, user.id, @locale.replies.missing_args)
      end

      if args.size == 1 && authority.in?(:promote, :promote_same)
        tuple = {user.rank, @access.ranks[user.rank]}
      elsif args.size == 2
        tuple = @access.find_rank(args[1].downcase, args[1].to_i?)
      else
        return relay_to_one(message.message_id, user.id, @locale.replies.missing_args)
      end

      unless tuple
        return relay_to_one(message.message_id, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank)})
      end

      unless (promoted_user = database.get_user_by_arg(args[0])) && !promoted_user.left?
        return relay_to_one(message.message_id, user.id, @locale.replies.no_user_found)
      end
    end

    unless @access.can_promote?(tuple[0], user.rank, promoted_user.rank, authority)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    promoted_user.set_rank(tuple[0])
    @database.modify_user(promoted_user)

    relay_to_one(nil, promoted_user.id, @locale.replies.promoted, {"rank" => tuple[1].name})

    log_output(@log_channel, Format.substitute_log(@locale.logs.promoted, locale, {
      "id"      => promoted_user.id.to_s,
      "name"    => promoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    }))
    relay_to_one(message.message_id, user.id, @locale.replies.success)
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
      arg = Format.get_arg(ctx.message.text)

      if arg.nil?
        tuple = {0, @access.ranks[0]}
      elsif arg
        tuple = @access.find_rank(arg.downcase, arg.to_i?)
      else
        return relay_to_one(message.message_id, user.id, @locale.replies.missing_args)
      end

      unless tuple
        return relay_to_one(message.message_id, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank)})
      end

      unless (demoted_user = database.get_user(@history.get_sender_id(reply.message_id))) && !demoted_user.left?
        return relay_to_one(message.message_id, user.id, @locale.replies.no_user_found)
      end
    else
      unless (args = Format.get_args(message.text, count: 2)) && (args.size == 2)
        return relay_to_one(message.message_id, user.id, @locale.replies.missing_args)
      end
      unless tuple = @access.find_rank(args[1].downcase, args[1].to_i?)
        return relay_to_one(message.message_id, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank)})
      end
      unless demoted_user = database.get_user_by_arg(args[0])
        return relay_to_one(message.message_id, user.id, @locale.replies.no_user_found)
      end
    end

    unless @access.can_demote?(tuple[0], user.rank, demoted_user.rank)
      return relay_to_one(message.message_id, user.id, @locale.replies.fail)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    demoted_user.set_rank(tuple[0])
    @database.modify_user(demoted_user)

    log_output(@log_channel, Format.substitute_log(@locale.logs.demoted, locale, {
      "id"      => demoted_user.id.to_s,
      "name"    => demoted_user.get_formatted_name,
      "rank"    => tuple[1].name,
      "invoker" => user.get_formatted_name,
    }))
    relay_to_one(message.message_id, user.id, @locale.replies.success)
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

    reason = Format.get_arg(ctx.message.text)

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

    relay_to_one(cached_msid, reply_user.id, @locale.replies.cooldown_given, {"reason" => reason, "duration" => duration})

    log_output(@log_channel, Format.substitute_log(@locale.logs.warned, locale, {
      "id"       => user.id.to_s,
      "name"     => user.get_formatted_name,
      "oid"      => reply_user.get_obfuscated_id,
      "duration" => duration,
      "reason"   => reason,
    }))
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

    relay_to_one(cached_msid, reply_user.id, @locale.replies.message_deleted, {"reason" => reason, "duration" => duration})
    log_output(@log_channel, Format.substitute_log(@locale.logs.message_deleted, @locale, {
      "id"       => user.id.to_s,
      "name"     => user.get_formatted_name,
      "msid"     => cached_msid.to_s,
      "oid"      => reply_user.get_obfuscated_id,
      "duration" => duration,
      "reason"   => reason,
    }))
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

    log_output(@log_channel, Format.substitute_log(@locale.logs.removed_cooldown, @locale, {
      "id"             => user.id.to_s,
      "name"           => user.get_formatted_name,
      "oid"            => uncooldown_user.get_obfuscated_id,
      "cooldown_until" => cooldown_until,
    }))
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

    relay_to_one(cached_msid, reply_user.id, @locale.replies.message_removed, {"reason" => Format.get_arg(message.text)})
    log_output(@log_channel, Format.substitute_log(@locale.logs.message_removed, @locale, {
      "id"     => user.id.to_s,
      "name"   => user.get_formatted_name,
      "msid"   => cached_msid.to_s,
      "oid"    => reply_user.get_obfuscated_id,
      "reason" => Format.get_arg(message.text),
    }))
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

    if banned_users = @database.get_blacklisted_users
      delete_msids = 0

      banned_users.each do |banned_user|
        @history.get_msids_from_user(banned_user.id).each do |msid|
          delete_messages(msid, banned_user.id, banned_user.debug_enabled)
          delete_msids += 1
        end
      end

      relay_to_one(message.message_id, user.id, @locale.replies.purge_complete, {"msgs_deleted" => delete_msids})
    end
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

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if reply_user.rank < user.rank
      reason = Format.get_arg(ctx.message.text)
      reply_user.blacklist(reason)
      @database.modify_user(reply_user)

      @queue.reject_messsages do |msg|
        msg.receiver == reply_user.id || msg.sender == reply_user.id
      end

      cached_msid = delete_messages(reply.message_id, reply_user.id, reply_user.debug_enabled)

      relay_to_one(cached_msid, reply_user.id, @locale.replies.blacklisted, {"contact" => @blacklist_contact, "reason" => reason})
      log_output(@log_channel, Format.substitute_log(@locale.logs.blacklisted, @locale, {
        "id"      => reply_user.id.to_s,
        "name"    => reply_user.get_formatted_name,
        "invoker" => user.get_formatted_name,
        "reason"  => reason,
      }))
      relay_to_one(message.message_id, user.id, @locale.replies.success)
    end
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
      if spoil_messages(reply.message_id, reply_user.id, reply_user.debug_enabled, input)
        log_output(@log_channel, Format.substitute_log(@locale.logs.unspoiled, @locale, {
          "id"   => user.id.to_s,
          "name" => user.get_formatted_name,
          "msid" => reply.message_id.to_s,
        }))
      else
        return relay_to_one(message.message_id, user.id, @locale.replies.fail)
      end
    else
      input.has_spoiler = true

      if spoil_messages(reply.message_id, reply_user.id, reply_user.debug_enabled, input)
        log_output(@log_channel, Format.substitute_log(@locale.logs.spoiled, @locale, {
          "id"   => user.id.to_s,
          "name" => user.get_formatted_name,
          "msid" => reply.message_id.to_s,
        }))
      else
        return relay_to_one(message.message_id, user.id, @locale.replies.fail)
      end
    end

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
    if !Format.allow_text?(text)
      return relay_to_one(msid, user.id, @locale.replies.rejected_message)
    end

    case
    when !text.starts_with?('/')
      return text
    when text.starts_with?("/s "), text.starts_with?("/sign ")
      return handle_sign(text, user, msid)
    when text.starts_with?("/t "), text.starts_with?("/tsign ")
      return handle_tripcode(text, user, msid)
    when match = /^\/(\w*)say\s/.match(text).try &.[1]
      return handle_ranksay(match, text, user, msid)
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
    unless @enable_tripsign
      return relay_to_one(msid, user.id, @locale.replies.command_disabled)
    end
    unless @access.authorized?(user.rank, :tsign)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end
    unless tripkey = user.tripcode
      return relay_to_one(msid, user.id, @locale.replies.no_tripcode_set)
    end
    if (spam = @spam_handler) && spam.spammy_sign?(user.id, @sign_limit_interval)
      return relay_to_one(msid, user.id, @locale.replies.sign_spam)
    end

    if (args = Format.get_arg(text)) && args.size > 0
      pair = Format.generate_tripcode(tripkey, @tripcode_salt)
      String.build do |str|
        str << Format.format_tripcode_sign(pair[:name], pair[:tripcode]) << ":"
        str << "\n"
        str << args
      end
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
      return relay_to_one(msid, user.id, @locale.replies.no_rank_found, {"ranks" => @access.rank_names(limit: user.rank)})
    end

    unless @access.can_ranksay?(parsed_rank[0], user.rank, authority)
      return relay_to_one(msid, user.id, @locale.replies.fail)
    end

    log_output(@log_channel, Format.substitute_log(@locale.logs.ranked_message, @locale, {
      "id"   => user.id.to_s,
      "name" => user.get_formatted_name,
      "rank" => parsed_rank[1].name,
      "text" => args,
    }))

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
    unless (raw_text = message.text) && (text = check_text(Format.strip_format(raw_text, message.entities, @entity_types, @linked_network), user, message.message_id))
      return
    end
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score_text(text))
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:{{captioned_type}}))
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

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    if caption = message.caption
      caption = Format.replace_links(caption, message.caption_entities)
    end
    if entities = message.caption_entities
      entities = Format.remove_entities(entities, @entity_types)
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
          next relay_to_one(message.message_id, user.id, @locale.replies.spamming)
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:poll))
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:forward))
      return relay_to_one(message.message_id, user.id, @locale.replies.spamming)
    end

    user.set_active(info.username, info.full_name)
    @database.modify_user(user)

    unless @regular_forwards
      return relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
      )
    end

    if Format.is_regular_forward?(message.text || message.caption, message.text_entities.keys)
      return relay(
        message.reply_message,
        user,
        @history.new_message(user.id, message.message_id),
        ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
      )
    end

    if from = message.forward_from
      if from.bot?
        header = Format.format_username_forward(from.full_name, from.username, Client.default_parse_mode)
      elsif from.id
        header = Format.format_user_forward(from.full_name, from.id, Client.default_parse_mode)
      end
    elsif (from = message.forward_from_chat) && message.forward_from_message_id
      if from.username
        header = Format.format_username_forward(from.name, from.username, Client.default_parse_mode, message.forward_from_message_id)
      else
        header = Format.format_private_channel_forward(from.name, from.id, message.forward_from_message_id, Client.default_parse_mode)
      end
    elsif from = message.forward_sender_name
      header = Format.format_private_user_forward(from, Client.default_parse_mode)
    end

    unless header
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

    if message.text
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text) }
    elsif album = message.media_group_id
      if media = message.photo.last?
        input = InputMediaPhoto.new(media.file_id, parse_mode: Tourmaline::ParseMode::HTML, has_spoiler: message.has_media_spoiler?)
      elsif media = message.video
        input = InputMediaVideo.new(media.file_id, parse_mode: Tourmaline::ParseMode::HTML, has_spoiler: message.has_media_spoiler?)
      elsif media = message.audio
        input = InputMediaAudio.new(media.file_id, parse_mode: Tourmaline::ParseMode::HTML)
      elsif media = message.document
        input = InputMediaDocument.new(media.file_id, parse_mode: Tourmaline::ParseMode::HTML)
      else
        return
      end

      if @albums[album]?
        input.caption = message.caption
        input.caption_entities = message.caption_entities

        @albums[album].message_ids << message.message_id
        @albums[album].media_ids << input
      else
        input.caption = text
        media_group = Album.new(message.message_id, input)
        @albums[album] = media_group

        # Wait an arbitrary amount of time for Telegram MediaGroup updates to come in before relaying the album.
        Tasker.at(500.milliseconds.from_now) {
          unless temp_album = @albums.delete(album)
            next
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

      return
    elsif file = message.animation
      return unless file && (file_id = file.file_id)
      proc = ->(receiver : Int64, reply : Int64 | Nil) {
        send_animation(receiver, file_id, caption: text, has_spoiler: message.has_media_spoiler?)
      }
    elsif file = message.document
      return unless file && (file_id = file.file_id)
      proc = ->(receiver : Int64, reply : Int64 | Nil) {
        send_document(receiver, file_id, caption: text)
      }
    elsif file = message.video
      return unless file && (file_id = file.file_id)
      proc = ->(receiver : Int64, reply : Int64 | Nil) {
        send_video(receiver, file_id, caption: text, has_spoiler: message.has_media_spoiler?)
      }
    elsif file = message.photo
      return unless file.last? && (file_id = file.last.file_id)
      proc = ->(receiver : Int64, reply : Int64 | Nil) {
        send_photo(receiver, file_id, caption: text, has_spoiler: message.has_media_spoiler?)
      }
    else
      proc = ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
    end

    return relay(
      message.reply_message,
      user,
      @history.new_message(user.id, message.message_id),
      proc
    )
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:sticker))
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:{{luck_type}}))
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:venue))
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:location))
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
    if (spam = @spam_handler) && spam.spammy?(info.id, spam.calculate_spam_score(:contact))
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
      relay_to_one(nil, user.id, @locale.replies.blacklisted, {"reason" => user.blacklist_reason})
    elsif cooldown_until = user.cooldown_until
      relay_to_one(nil, user.id, @locale.replies.on_cooldown, {"time" => Format.format_time(cooldown_until, @locale.time_format)})
    elsif Time.utc - user.joined < @media_limit_period.hours
      relay_to_one(nil, user.id, @locale.replies.media_limit, {"total" => (@media_limit_period.hours - (Time.utc - user.joined)).hours})
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
      log_output(@log_channel, Format.substitute_log(@locale.logs.left, @locale, {"id" => user.id.to_s, "name" => user.get_formatted_name}))
      relay_to_one(nil, user.id, @locale.replies.inactive, {"time" => @inactivity_limit})
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
  def relay(reply_message : Tourmaline::Message?, user : Database::User, cached_msid : Int64 | Array(Int64), proc : MessageProc) : Nil
    if reply_message
      unless (reply_msids = @history.get_all_msids(reply_message.message_id)) && (!reply_msids.empty?)
        relay_to_one(cached_msid.is_a?(Int64) ? cached_msid : cached_msid[0], user.id, @locale.replies.not_in_cache)
        if cached_msid.is_a?(Int64)
          @history.del_message_group(cached_msid)
        else
          cached_msid.each { |msid| @history.del_message_group(msid) }
        end

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
    proc = ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text, link_preview: true, reply_to_message: reply) }
    @queue.add_to_queue_priority(user, reply_message, proc)
  end

  # :ditto:
  def relay_to_one(reply_message : Int64?, user : Int64, reply : String, params : Hash(String, String | Array(String) | Time | Int32 | Bool | Rank | Nil)) : Nil
    proc = ->(receiver : Int64, reply_msid : Int64 | Nil) { send_message(receiver, Format.substitute_reply(reply, @locale, params), link_preview: true, reply_to_message: reply_msid) }
    @queue.add_to_queue_priority(user, reply_message, proc)
  end

  # Outputs given text to the log (either STDOUT or a file, defined in config) with INFO severity.
  #
  # Also outputs text to a given log channel, if available
  def log_output(channel : String?, text : String) : Nil
    Log.info { text }
    if channel
      send_message(channel, text)
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
      log_output(@log_channel, Format.substitute_log(@locale.logs.force_leave, @locale, {"id" => user_id.to_s}))
    end
    @queue.reject_messsages do |msg|
      msg.receiver == user_id
    end
  end
end
