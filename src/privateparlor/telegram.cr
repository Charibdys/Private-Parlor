class PrivateParlor < Tourmaline::Client
  getter database : Database
  getter history : History
  getter queue : Deque(QueuedMessage)
  getter replies : Replies
  getter tasks : Hash(Symbol, Tasker::Task)
  getter config : Configuration::Config
  getter albums : Hash(String, Album)

  # Creates a new instance of PrivateParlor.
  #
  # ## Arguments:
  #
  # `bot_token`
  # :     the bot token given by `@BotFather`
  #
  # `config`
  # :     a `Configuration::Config` from parsing the `config.yaml` file
  #
  # `connection`
  # :     the `DB::Databse` object obtained from the database path in the `config.yaml` file
  def initialize(@config : Configuration::Config, parse_mode)
    super(bot_token: config.token, default_parse_mode: parse_mode)
    @database = Database.new(DB.open("sqlite3://#{Path.new(config.database)}")) # TODO: We'll want check if this works on Windows later
    @history = History.new(config.lifetime.hours)
    @queue = Deque(QueuedMessage).new
    @replies = Replies.new(config.entities)
    @tasks = register_tasks()
    @albums = {} of String => Album
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

    def initialize(msid : Int64, media : InputMediaPhoto | InputMediaVideo | InputMediaAudio | InputMediaDocument)
      @message_ids = [msid]
      @media_ids = [media]
    end
  end

  # Starts various background tasks and stores them in a hash.
  def register_tasks : Hash
    tasks = {} of Symbol => Tasker::Task
    # Handle cache expiration
    tasks.merge!({:cache => Tasker.every(@history.lifespan * (1/4)) { @history.expire }})
  end

  # Updates user's record in the database with new, up-to-date information.
  def update_user(info, user : Database::User)
    user.username = info.username
    user.realname = info.full_name
    user.set_active
    database.modify_user(user)
  end

  # Update user's record in database with current values.
  def update_user(user : Database::User)
    database.modify_user(user)
  end

  # User starts the bot and begins receiving messages.
  #
  # If the user is not in the database, this will add the user to it
  #
  # If blacklisted or joined, this will not allow them to rejoin
  #
  # Left users can rejoin the bot with this command
  #
  # TODO: Define the replies somwehere else and format them
  @[Command("start")]
  def start_command(ctx)
    if (message = ctx.message) && (info = message.from)
      user = database.get_user(info.id)
      unless user.nil? # User exists in DB; run checks
        if user.blacklisted?
          relay_to_one(nil, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.blacklisted(user.blacklistReason)) })
        elsif user.left?
          user.rejoin
          update_user(info, user)
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.rejoined, reply_to_message: reply) })
          Log.info { "User #{user.id}, aka #{user.get_formatted_name}, rejoined the chat." }
        else # user is already in the chat
          update_user(info, user)
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.already_in_chat, reply_to_message: reply) })
        end
      else # User does not exist; add to DB
        if (database.no_users?)
          user = database.add_user(info.id, info.username, info.full_name, rank: 1000)
        else
          user = database.add_user(info.id, info.username, info.full_name)
        end

        if motd = @database.get_motd
          relay_to_one(nil, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.custom(motd)) })
        end
        relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.joined, reply_to_message: reply) })
        Log.info { "User #{user.id}, aka #{user.get_formatted_name}, joined the chat." }
      end
    end
  end

  # Stops the bot for the user.
  #
  # This will set the user status to left, meaning the user will not receive any further messages.
  @[Command(["stop", "leave"])]
  def stop_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if (user = database.get_user(info.id)) && !user.left?
        user.set_left
        update_user(user)
        relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.left, reply_to_message: reply) })
        Log.info { "User #{user.id}, aka #{user.get_formatted_name}, left the chat." }
      end
    end
  end

  # Returns a message containing the user's OID, username, karma, warnings, etc.
  #
  # If this is used with a reply, returns the user info of that message if the invoker is ranked.
  @[Command(["info"])]
  def info_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if reply = message.reply_message
          if user.authorized?(Ranks::Moderator)
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              return relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver,
                @replies.user_info_mod(
                  oid: reply_user.get_obfuscated_id,
                  karma: reply_user.get_obfuscated_karma,
                  cooldown_until: reply_user.cooldownUntil
                ), reply_to_message: reply) })
            end
          end
        end

        return relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver,
          @replies.user_info(
            oid: user.get_obfuscated_id,
            username: user.get_formatted_name,
            rank: Ranks.new(user.rank),
            karma: user.karma,
            warnings: user.warnings,
            warn_expiry: user.warnExpiry,
            cooldown_until: user.cooldownUntil
          ), reply_to_message: reply) })
      end
    end
  end

  # Return a message containing the number of users in the bot.
  #
  # If the user is not ranked, or `full_usercount` is false, show the total numbers users.
  # Otherwise, return a message containing the number of joined, left, and blacklisted users.
  @[Command(["users"])]
  def users_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = check_user(info)
        counts = database.get_user_counts

        if user.authorized?(Ranks::Moderator) || config.full_usercount
          text = @replies.user_count((counts[:total] - counts[:left]), counts[:left], counts[:blacklisted], counts[:total], true)
        else
          text = @replies.user_count(counts[:total] - counts[:left], counts[:left], counts[:blacklisted], counts[:total], false)
        end

        relay_to_one(nil, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text) })
      end
    end
  end

  # Returns a message containing the progam's version.
  @[Command(["version"])]
  def version_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = check_user(info)
        relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.version, link_preview: true, reply_to_message: reply) })
      end
    end
  end

  # Upvotes a message.
  @[Command(["1"], prefix: ["+"])]
  def karma_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if reply = message.reply_message
          if (@history.get_sender_id(reply.message_id) == user.id)
            return relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.upvoted_own_message, reply_to_message: reply) })
          end
          if (!@history.add_rating(reply.message_id, user.id))
            return relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.already_upvoted, reply_to_message: reply) })
          end

          if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
            reply_user.increment_karma
            update_user(reply_user)
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.gave_upvote, reply_to_message: reply) })
            if (!reply_user.hideKarma)
              relay_to_one(@history.get_msid(reply.message_id, reply_user.id), reply_user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.got_upvote, reply_to_message: reply) })
            end
          end
        else
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_reply, reply_to_message: reply) })
        end
      end
    end
  end

  # Toggle the user's hide_karma attribute.
  @[Command(["toggle_karma", "togglekarma"])]
  def toggle_karma_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        user.toggle_karma
        update_user(user)
        relay_to_one(nil, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.toggle_karma(user.hideKarma)) })
      end
    end
  end

  # Toggle the user's toggle_debug attribute.
  @[Command(["toggle_debug", "toggledebug"])]
  def toggle_debug_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        user.toggle_debug
        update_user(user)
        relay_to_one(nil, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.toggle_debug(user.debugEnabled)) })
      end
    end
  end

  # Set/modify/view the user's tripcode.
  @[Command(["tripcode"])]
  def tripcode_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if arg = get_args(ctx.message.text)
          if !((index = arg.index('#')) && (0 < index < arg.size - 1)) || arg.includes?('\n') || arg.size > 30
            return relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.invalid_tripcode_format, reply_to_message: reply) })
          end

          user.tripcode = arg
          update_user(user)

          results = generate_tripcode(arg, @config.salt)
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.tripcode_set(results[:name], results[:tripcode]), reply_to_message: reply) })
        else
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.tripcode_info(user.tripcode), reply_to_message: reply) })
        end
      end
    end
  end

  ##################
  # ADMIN COMMANDS #
  ##################

  # Promote a user to the moderator rank.
  @[Command(["mod"])]
  def mod_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if user.authorized?(Ranks::Host)
          if arg = get_args(message.text)
            if promoted_user = database.get_user_by_name(arg)
              if promoted_user.left? || promoted_user.rank >= Ranks::Moderator.value
                return
              else
                promoted_user.set_rank(Ranks::Moderator)
                update_user(promoted_user)
                relay_to_one(nil, promoted_user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.promoted(Ranks::Moderator)) })

                Log.info { "User #{promoted_user.id}, aka #{promoted_user.get_formatted_name}, has been promoted to #{Ranks::Moderator}." }
                relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.success, reply_to_message: reply) })
              end
            else
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_user_found, reply_to_message: reply) })
            end
          else
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.missing_args, reply_to_message: reply) })
          end
        end
      end
    end
  end

  # Promote a user to the administrator rank.
  @[Command(["admin"])]
  def admin_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if user.authorized?(Ranks::Host)
          if arg = get_args(message.text)
            if promoted_user = database.get_user_by_name(arg)
              if promoted_user.left? || promoted_user.rank >= Ranks::Admin.value
                return
              else
                promoted_user.set_rank(Ranks::Admin)
                update_user(promoted_user)
                relay_to_one(nil, promoted_user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.promoted(Ranks::Admin)) })

                Log.info { "User #{promoted_user.id}, aka #{promoted_user.get_formatted_name}, has been promoted to #{Ranks::Admin}." }
                relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.success, reply_to_message: reply) })
              end
            else
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_user_found, reply_to_message: reply) })
            end
          else
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.missing_args, reply_to_message: reply) })
          end
        end
      end
    end
  end

  # Returns a ranked user to the user rank
  @[Command(["demote"])]
  def demote_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if user.authorized?(Ranks::Host)
          if arg = get_args(message.text)
            if demoted_user = database.get_user_by_name(arg)
              demoted_user.set_rank(Ranks::User)
              update_user(demoted_user)
              Log.info { "User #{demoted_user.id}, aka #{demoted_user.get_formatted_name}, has been demoted." }
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.success, reply_to_message: reply) })
            else
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_user_found, reply_to_message: reply) })
            end
          else
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.missing_args, reply_to_message: reply) })
          end
        end
      end
    end
  end

  # Delete a message from a user, give a warning and a cooldown.
  # TODO: Implement warning/cooldown system
  @[Command(["delete"])]
  def delete_message(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if user.authorized?(Ranks::Moderator)
          if reply = message.reply_message
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              cached_msid = delete_messages(reply.message_id, reply_user.id)

              relay_to_one(cached_msid, reply_user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.message_deleted(true, get_args(message.text)), reply_to_message: reply) })

              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.success, reply_to_message: reply) })
            else
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.not_in_cache, reply_to_message: reply) })
            end
          else
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_reply, reply_to_message: reply) })
          end
        end
      end
    end
  end

  # Remove a message from a user without giving a warning or cooldown.
  @[Command(["remove"])]
  def remove_message(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if user.authorized?(Ranks::Moderator)
          if reply = message.reply_message
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              cached_msid = delete_messages(reply.message_id, reply_user.id)

              relay_to_one(cached_msid, reply_user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.message_deleted(false, get_args(message.text)), reply_to_message: reply) })

              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.success, reply_to_message: reply) })
            else
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.not_in_cache, reply_to_message: reply) })
            end
          else
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_reply, reply_to_message: reply) })
          end
        end
      end
    end
  end

  # Delete all messages from recently blacklisted users.
  @[Command(["purge"])]
  def delete_all_messages(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if user.authorized?(Ranks::Admin)
          if banned_users = @database.get_blacklisted_users
            delete_msids = 0
            banned_users.each do |banned_user|
              @history.get_msids_from_user(banned_user.id).each do |msid|
                delete_messages(msid, banned_user.id)
                delete_msids += 1
              end

              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.purge_complete(delete_msids), reply_to_message: reply) })
            end
          end
        end
      end
    end
  end

  # Blacklists a user from the chat, deletes the reply, and removes all the user's incoming and outgoing messages from the queue.
  @[Command(["blacklist", "ban"])]
  def blacklist(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if user.authorized?(Ranks::Admin)
          if reply = ctx.message.reply_message
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              reason = get_args(ctx.message.text)
              reply_user.blacklist(reason)
              update_user(reply_user)

              # Remove queued messages sent by and directed to blacklisted user.
              @queue.reject! do |msg|
                msg.receiver == user.id || msg.sender == user.id
              end
              cached_msid = delete_messages(reply.message_id, reply_user.id)

              relay_to_one(cached_msid, reply_user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.blacklisted(reason), reply_to_message: reply) })
              Log.info { "User #{reply_user.id}, aka #{reply_user.get_formatted_name}, has been blacklisted by #{user.get_formatted_name}#{reason ? " for: #{reason}" : "."}" }
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.success, reply_to_message: reply) })
            else
              relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.not_in_cache, reply_to_message: reply) })
            end
          else
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_reply, reply_to_message: reply) })
          end
        end
      end
    end
  end

  # Deletes the given message for all receivers and removes it from the message history.
  #
  # Returns the sender's (user_id) original message id upon success.
  def delete_messages(msid : Int64, user_id : Int64) : Int64?
    if reply_msids = @history.get_all_msids(msid)
      reply_msids.each do |receiver_id, cached_msid|
        delete_message(receiver_id, reply_msids[receiver_id])
      end
      return @history.del_message_group(msid)
    end
  end

  # Replies with the motd/rules associated with this bot.
  # If the host invokes this command, the motd/rules can be set or modified.
  @[Command(["motd", "rules"])]
  def motd(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        if arg = get_args(ctx.message.text)
          if user.authorized?(Ranks::Host)
            @database.set_motd(arg)
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.success, reply_to_message: reply) })
          end
        else
          if motd = @database.get_motd
            relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.custom(motd), reply_to_message: reply) })
          end
        end
      end
    end
  end

  # Returns a message containing all the commands that a user can use, according to the user's rank.
  @[Command(["help"])]
  def help_command(ctx)
    if (message = ctx.message) && (info = message.from)
      if user = check_user(info)
        case user.rank
        when Ranks::Moderator.value
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.mod_help, reply_to_message: reply) })
        when Ranks::Admin.value
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.admin_help, reply_to_message: reply) })
        when Ranks::Host.value
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.host_help, reply_to_message: reply) })
        end
      end
    end
  end

  # Checks if the user can send a message.
  #
  # Returns the user if the user can send a message; nil otherwise.
  def check_user(info : Tourmaline::User) : Database::User | Nil
    user = database.get_user(info.id)
    if (user && !user.left?)
      update_user(info, user)
      # TODO: Add spam and warning checks
      return user
    elsif user && user.blacklisted?
      relay_to_one(nil, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.blacklisted(user.blacklistReason)) })
      return
    else
      relay_to_one(nil, info.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.not_in_chat) })
      return
    end
  end

  # Checks if the text contains a special font or starts a sign command.
  #
  # Returns the given text or a formatted text if it is allowed; nil if otherwise or a sign command could not be used.
  def check_text(text : String, user : Database::User, msid : Int64) : String?
    if !@replies.allow_text?(text)
      relay_to_one(msid, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.rejected_message, reply_to_message: reply) })
      return
    end

    case
    when !text.starts_with?('/')
      return text
    when text.starts_with?("/s"), text.starts_with?("/sign")
      if config.allow_signing # NOTE: Since we cannot check if user has private forwards enabled, signing will not work as intendend
        if (args = get_args(text)) && args.size > 0
          return String.build do |str|
            str << args
            str << @replies.format_user_sign(user.id, user.get_formatted_name)
          end
        end
      else
        relay_to_one(msid, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.command_disabled, reply_to_message: reply) })
      end
    when text.starts_with?("/t"), text.starts_with?("/tsign")
      if config.allow_tripcodes
        if tripkey = user.tripcode
          if (args = get_args(text)) && args.size > 0
            pair = generate_tripcode(tripkey, config.salt)
            return String.build do |str|
              str << @replies.format_tripcode_sign(pair[:name], pair[:tripcode]) << ":"
              str << "\n"
              str << args
            end
          end
        else
          relay_to_one(msid, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.no_tripcode_set, reply_to_message: reply) })
        end
      else
        relay_to_one(msid, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.command_disabled, reply_to_message: reply) })
      end
    when text.starts_with?("/modsay")
      if user.authorized?(Ranks::Moderator)
        if (args = get_args(text)) && args.size > 0
          Log.info { "User #{user.id}, aka #{user.get_formatted_name} sent mod message: #{args}" }
          return String.build do |str|
            str << args
            str << @replies.format_user_say("mod")
          end
        end
      end
    when text.starts_with?("/adminsay")
      if user.authorized?(Ranks::Admin)
        if (args = get_args(text)) && args.size > 0
          Log.info { "User #{user.id}, aka #{user.get_formatted_name} sent admin message: #{args}" }
          return String.build do |str|
            str << args
            str << @replies.format_user_say("admin")
          end
        end
      end
    when text.starts_with?("/hostsay")
      if user.authorized?(Ranks::Host)
        if (args = get_args(text)) && args.size > 0
          Log.info { "User #{user.id}, aka #{user.get_formatted_name} sent host message: #{args}" }
          return String.build do |str|
            str << args
            str << @replies.format_user_say("host")
          end
        end
      end
    else
      return
    end

    return
  end

  # Prepares a text message for relaying.
  @[On(:text)]
  def handle_text(update)
    if (message = update.message) && (info = message.from)
      if message.forward_from || message.forward_from_chat
        return
      end

      if user = check_user(info)
        if raw_text = message.text
          if text = check_text(@replies.strip_format(raw_text, message.entities), user, message.message_id)
            relay(
              message.reply_message,
              user,
              @history.new_message(user.id, message.message_id),
              ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text, reply_to_message: reply) }
            )
          end
        end
      end
    end
  end

  {% for captioned_type in ["animation", "audio", "document", "video", "video_note", "voice", "photo"] %}
  # Prepares a {{captioned_type}} message for relaying.
  @[On(:{{captioned_type.id}})]
  def handle_{{captioned_type.id}}(update)
    if (message = update.message) && (info = message.from)
      if message.media_group_id || (message.forward_from || message.forward_from_chat)
        return
      end
      {% if captioned_type == "document" %}
        if message.animation
          return
        end
      {% end %}

      if user = check_user(info)
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
          {% if captioned_type == "photo" %}
            ->(receiver : Int64, reply : Int64 | Nil) { send_photo(receiver, (message.photo.last).file_id, caption, reply_to_message: reply) }
          {% else %}
            ->(receiver : Int64, reply : Int64 | Nil) { send_{{captioned_type.id}}(receiver, message.{{captioned_type.id}}.not_nil!.file_id, caption: caption, reply_to_message: reply) }
          {% end %}
        )
      end
    end
  end
  {% end %}

  # Prepares a album message for relaying.
  @[On(:media_group)]
  def handle_albums(update)
    if (message = update.message) && (info = message.from)
      if message.forward_from || message.forward_from_chat
        return
      end
      if user = check_user(info)
        album = message.media_group_id.not_nil!
        if caption = message.caption
          caption = @replies.replace_links(caption, message.caption_entities)
        end
        if entities = message.caption_entities
          entities = @replies.remove_entities(entities)
        end
        if (media = message.photo.last?)
          input = InputMediaPhoto.new(media.file_id, caption: caption, caption_entities: entities)
        elsif (media = message.video)
          input = InputMediaVideo.new(media.file_id, caption: caption, caption_entities: entities)
        elsif (media = message.audio)
          input = InputMediaAudio.new(media.file_id, caption: caption, caption_entities: entities)
        elsif (media = message.document)
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
          Tasker.at(2.seconds.from_now) {
            cached_msids = Array(Int64).new
            temp_album = @albums.delete(album)
            temp_album.not_nil!.message_ids.each do |msid|
              cached_msids << @history.new_message(info.id, msid)
            end

            relay(
              message.reply_message,
              user,
              cached_msids,
              ->(receiver : Int64, reply : Int64 | Nil) { send_media_group(receiver, temp_album.not_nil!.media_ids, reply_to_message: reply) }
            )
          }
        end
      end
    end
  end

  # Prepares a poll for relaying.
  @[On(:poll)]
  def handle_poll(update)
    if (message = update.message) && (info = message.from)
      if message.forward_from || message.forward_from_chat
        return
      end
      if user = check_user(info)
        if message.poll.not_nil!.is_anonymous == false
          relay_to_one(message.message_id, user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.deanon_poll, reply_to_message: reply) })
        else
          relay(
            message.reply_message,
            user,
            @history.new_message(user.id, message.message_id),
            ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
          )
        end
      end
    end
  end

  # Prepares a poll message for relaying.
  @[On(:forwarded_message)]
  def handle_forward(update)
    if (message = update.message) && (info = message.from)
      if user = check_user(info)
        relay(
          message.reply_message,
          user,
          @history.new_message(user.id, message.message_id),
          ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
        )
      end
    end
  end

  # Prepares a sticker message for relaying.
  @[On(:sticker)]
  def handle_sticker(update)
    if (message = update.message) && (info = message.from)
      if message.forward_from || message.forward_from_chat
        return
      end

      if user = check_user(info)
        relay(
          message.reply_message,
          user,
          @history.new_message(user.id, message.message_id),
          ->(receiver : Int64, reply : Int64 | Nil) { send_sticker(receiver, message.sticker.not_nil!.file_id, reply_to_message: reply) }
        )
      end
    end
  end

  {% for luck_type in ["dice", "dart", "basketball", "soccerball", "slot_machine", "bowling"] %}
  # Prepares a {{luck_type}} message for relaying.
  @[On(:{{luck_type.id}})]
  def handle_{{luck_type.id}}(update)
    if config.relay_luck
      if (message = update.message) && (info = message.from)
        if (message.forward_from || message.forward_from_chat)
          return
        end
        if user = check_user(info)
          relay(
            message.reply_message, 
            user, 
            @history.new_message(user.id, message.message_id),
            ->(receiver : Int64, reply : Int64 | Nil) { send_{{luck_type.id}}(receiver, reply_to_message: reply) }
          )
        end
      end
    end
  end
  {% end %}

  def relay(reply_message : Tourmaline::Message?, user : Database::User, cached_msid : Int64 | Array(Int64), proc : MessageProc)
    if reply_message
      if (reply_msids = @history.get_all_msids(reply_message.message_id)) && (!reply_msids.empty?)
        @database.get_prioritized_users.each do |receiver_id|
          if receiver_id != user.id || user.debugEnabled
            add_to_queue(cached_msid, user.id, receiver_id, reply_msids[receiver_id], proc)
          end
        end
      else # Reply does not exist in cache; remove this message from cache
        relay_to_one(cached_msid.is_a?(Int64) ? cached_msid : cached_msid[0], user.id, ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.not_in_cache, reply_to_message: reply) })
        if cached_msid.is_a?(Int64)
          @history.del_message_group(cached_msid)
        else
          cached_msid.each { |msid| @history.del_message_group(msid) }
        end
      end
    else
      @database.get_prioritized_users.each do |receiver_id|
        if (receiver_id != user.id) || user.debugEnabled
          add_to_queue(cached_msid, user.id, receiver_id, nil, proc)
        end
      end
    end
  end

  # Relay a message to a single user. Used for system messages.
  def relay_to_one(reply_message : Int64?, user : Int64, proc : MessageProc)
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
  def add_to_queue(cached_msid : Int64 | Array(Int64), sender_id : Int64 | Nil, receiver_id : Int64, reply_msid : Int64 | Nil, func : MessageProc)
    @queue.push(QueuedMessage.new(cached_msid, sender_id, receiver_id, reply_msid, func))
  end

  # Creates a new `QueuedMessage` and pushes it to the front of the queue.
  def add_to_queue_priority(receiver_id : Int64, reply_msid : Int64 | Nil, func : MessageProc)
    @queue.unshift(QueuedMessage.new(nil, nil, receiver_id, reply_msid, func))
  end

  # Receives a `Message` from the `queue`, calls its proc, and adds the returned message id to the History
  #
  # This function should be invoked in a Fiber.
  def send_messages(msg : QueuedMessage)
    begin
      success = msg.function.call(msg.receiver, msg.reply_to)
      if msg.origin_msid != nil
        if !success.is_a?(Array(Tourmaline::Message))
          @history.add_to_cache(msg.origin_msid.as(Int64), success.message_id, msg.receiver)
        else
          sent_msids = success.map { |msg| msg.message_id }

          sent_msids.zip(msg.origin_msid.as(Array(Int64))) do |msid, origin_msid|
            @history.add_to_cache(origin_msid, msid, msg.receiver)
          end
        end
      end
    rescue Tourmaline::Error::BotBlocked | Tourmaline::Error::UserDeactivated
      force_leave(msg.receiver)
    end
  end

  # Set blocked user to left in the database and delete all incoming messages from the queue.
  def force_leave(user_id : Int64) : Nil
    if user = database.get_user(user_id)
      user.set_left
      update_user(user)
      Log.info { "Force leaving user #{user_id} because bot is blocked." }
    end
    queue.reject! do |msg|
      msg.receiver == user_id
    end
  end
end
