class PrivateParlor < Tourmaline::Client
  getter database : Database
  getter history : History
  getter queue : Deque(QueuedMessage)
  getter replies : Replies
  getter tasks : Hash(Symbol, Tasker::Task)
  getter config : Configuration::Config
  getter albums : Hash(String, Album)
  getter spam : SpamScoreHandler

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
    super(bot_token: config.token)
    Client.default_parse_mode=(parse_mode)
    default_parse_mode = (parse_mode)

    @database = Database.new(DB.open("sqlite3://#{Path.new(config.database)}")) # TODO: We'll want check if this works on Windows later
    @history = HistoryFull.new(config.lifetime.hours)
    @queue = Deque(QueuedMessage).new
    @replies = Replies.new(config.entities, config.locale)
    @spam = SpamScoreHandler.new
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

  class SpamScoreHandler
    getter scores : Hash(Int64, Float32)
    getter sign_last_used : Hash(Int64, Time)

    def initialize
      @scores = {} of Int64 => Float32
      @sign_last_used = {} of Int64 => Time
    end

    # Check if user's spam score triggers the spam filter
    #
    # Returns true if score is greater than spam limit, false otherwise.
    def spammy?(user : Int64, increment : Float32) : Bool
      score = 0 unless score = @scores[user]?

      if score > SPAM_LIMIT
        return true
      elsif score + increment > SPAM_LIMIT
        @scores[user] = SPAM_LIMIT_HIT
        return score + increment >= SPAM_LIMIT_HIT
      end

      @scores[user] = score + increment

      return false
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

      return false
    end

    def calculate_spam_score(type : Symbol) : Float32
      case type
      when :forward
        SCORE_BASE_FORWARD
      when :sticker
        SCORE_STICKER
      when :album
        SCORE_ALBUM
      else
        SCORE_BASE_MESSAGE
      end
    end

    def calculate_spam_score_text(text : String) : Float32
      SCORE_BASE_MESSAGE + (text.size * SCORE_TEXT_CHARACTER) + (text.count('\n') * SCORE_TEXT_LINEBREAK)
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

  # Starts various background tasks and stores them in a hash.
  def register_tasks : Hash
    tasks = {
      :cache    => Tasker.every(@history.lifespan * (1/4)) { @history.expire },
      :spam     => Tasker.every(SPAM_INTERVAL_SECONDS.seconds) { @spam.expire },
      :warnings => Tasker.every(15.minutes) { @database.expire_warnings },
    } of Symbol => Tasker::Task
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
  def start_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      user = database.get_user(info.id)
      unless user.nil?
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
        if (database.no_users?)
          user = database.add_user(info.id, info.username, info.full_name, rank: 1000)
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
  end

  # Stops the bot for the user.
  #
  # This will set the user status to left, meaning the user will not receive any further messages.
  @[Command(["stop", "leave"])]
  def stop_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if (user = database.get_user(info.id)) && !user.left?
        user.set_active(info.username, info.full_name)
        user.set_left
        @database.modify_user(user)
        relay_to_one(message.message_id, user.id, :left)
        Log.info { @replies.substitute_log(:left, {"id" => user.id.to_s, "name" => user.get_formatted_name}) }
      end
    end
  end

  # Returns a message containing the user's OID, username, karma, warnings, etc.
  #
  # If this is used with a reply, returns the user info of that message if the invoker is ranked.
  @[Command(["info"])]
  def info_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if reply = message.reply_message
          if user.authorized?(Ranks::Moderator)
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              return relay_to_one(message.message_id, user.id, :ranked_info, {
                "oid"            => reply_user.get_obfuscated_id,
                "karma"          => reply_user.get_obfuscated_karma,
                "cooldown_until" => reply_user.remove_cooldown ? nil : reply_user.cooldown_until,
              })
            end
          end
        end

        return relay_to_one(message.message_id, user.id, :user_info, {
          "oid"            => user.get_obfuscated_id,
          "username"       => user.get_formatted_name,
          "rank"           => Ranks.new(user.rank),
          "karma"          => user.karma,
          "warnings"       => user.warnings,
          "warn_expiry"    => user.warn_expiry,
          "cooldown_until" => user.remove_cooldown ? nil : user.cooldown_until,
        })
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Return a message containing the number of users in the bot.
  #
  # If the user is not ranked, or `full_usercount` is false, show the total numbers users.
  # Otherwise, return a message containing the number of joined, left, and blacklisted users.
  @[Command(["users"])]
  def users_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        counts = database.get_user_counts

        if user.authorized?(Ranks::Moderator) || config.full_usercount
          relay_to_one(nil, user.id, :user_count_full, {
            "joined"      => counts[:total] - counts[:left],
            "left"        => counts[:left],
            "blacklisted" => counts[:blacklisted],
            "total"       => counts[:total],
          })
        else
          relay_to_one(nil, user.id, :user_count, {"total" => counts[:total]})
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Returns a message containing the progam's version.
  @[Command(["version"])]
  def version_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        relay_to_one(message.message_id, user.id, @replies.version)
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Upvotes a message.
  @[Command(["1"], prefix: ["+"])]
  def karma_command(ctx) : Nil
    if history_with_karma = @history.as?(HistoryFull)
      if (message = ctx.message) && (info = message.from)
        if user = database.get_user(info.id)
          unless user.can_use_command?
            return deny_user(user)
          end
          user.set_active(info.username, info.full_name)
          @database.modify_user(user)

          if reply = message.reply_message
            if (history_with_karma.get_sender_id(reply.message_id) == user.id)
              return relay_to_one(message.message_id, user.id, :upvoted_own_message)
            end
            if (!history_with_karma.add_rating(reply.message_id, user.id))
              return relay_to_one(message.message_id, user.id, :already_upvoted)
            end

            if reply_user = database.get_user(history_with_karma.get_sender_id(reply.message_id))
              reply_user.increment_karma
              @database.modify_user(reply_user)
              relay_to_one(message.message_id, user.id, :gave_upvote)
              if (!reply_user.hide_karma)
                relay_to_one(history_with_karma.get_msid(reply.message_id, reply_user.id), reply_user.id, :got_upvote)
              end
            end
          else
            relay_to_one(message.message_id, user.id, :no_reply)
          end
        else
          relay_to_one(nil, info.id, :not_in_chat)
        end
      end
    end
  end

  # Toggle the user's hide_karma attribute.
  @[Command(["toggle_karma", "togglekarma"])]
  def toggle_karma_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        user.toggle_karma
        @database.modify_user(user)
        relay_to_one(nil, user.id, :toggle_karma, {"toggle" => user.hide_karma})
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Toggle the user's toggle_debug attribute.
  @[Command(["toggle_debug", "toggledebug"])]
  def toggle_debug_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        user.toggle_debug
        @database.modify_user(user)
        relay_to_one(nil, user.id, :toggle_debug, {"toggle" => user.debug_enabled})
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Set/modify/view the user's tripcode.
  @[Command(["tripcode"])]
  def tripcode_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        if arg = @replies.get_args(ctx.message.text)
          if !((index = arg.index('#')) && (0 < index < arg.size - 1)) || arg.includes?('\n') || arg.size > 30
            return relay_to_one(message.message_id, user.id, :invalid_tripcode_format)
          end
          user.set_active(info.username, info.full_name)
          user.set_tripcode(arg)
          @database.modify_user(user)

          results = @replies.generate_tripcode(arg, @config.salt)
          relay_to_one(message.message_id, user.id, :tripcode_set, {"name" => results[:name], "tripcode" => results[:tripcode]})
        else
          relay_to_one(message.message_id, user.id, :tripcode_sinfo, {"tripcode" => user.tripcode})
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  ##################
  # ADMIN COMMANDS #
  ##################

  # Promote a user to the moderator rank.
  @[Command(["mod"])]
  def mod_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Host)
          if arg = @replies.get_args(message.text)
            if promoted_user = database.get_user_by_name(arg)
              if promoted_user.left? || promoted_user.rank >= Ranks::Moderator.value
                return
              else
                promoted_user.set_rank(Ranks::Moderator)
                @database.modify_user(promoted_user)
                relay_to_one(nil, promoted_user.id, :promoted, {"rank" => Ranks::Moderator})

                Log.info { @replies.substitute_log(:promoted, {
                  "id"      => promoted_user.id.to_s,
                  "name"    => promoted_user.get_formatted_name,
                  "rank"    => Ranks::Moderator,
                  "invoker" => user.get_formatted_name,
                }) }
                relay_to_one(message.message_id, user.id, :success)
              end
            else
              relay_to_one(message.message_id, user.id, :no_user_found)
            end
          else
            relay_to_one(message.message_id, user.id, :missing_args)
          end
        end
      end
    end
  end

  # Promote a user to the administrator rank.
  @[Command(["admin"])]
  def admin_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Host)
          if arg = @replies.get_args(message.text)
            if promoted_user = database.get_user_by_name(arg)
              if promoted_user.left? || promoted_user.rank >= Ranks::Admin.value
                return
              else
                promoted_user.set_rank(Ranks::Admin)
                @database.modify_user(promoted_user)
                relay_to_one(nil, promoted_user.id, :promoted, {"rank" => Ranks::Admin})

                Log.info { @replies.substitute_log(:promoted, {
                  "id"      => promoted_user.id.to_s,
                  "name"    => promoted_user.get_formatted_name,
                  "rank"    => Ranks::Admin,
                  "invoker" => user.get_formatted_name,
                }) }
                relay_to_one(message.message_id, user.id, :success)
              end
            else
              relay_to_one(message.message_id, user.id, :no_user_found)
            end
          else
            relay_to_one(message.message_id, user.id, :missing_args)
          end
        end
      end
    end
  end

  # Returns a ranked user to the user rank
  @[Command(["demote"])]
  def demote_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Host)
          if arg = @replies.get_args(message.text)
            if demoted_user = database.get_user_by_name(arg)
              demoted_user.set_rank(Ranks::User)
              @database.modify_user(demoted_user)
              Log.info { @replies.substitute_log(:demoted, {
                "id"      => demoted_user.id.to_s,
                "name"    => demoted_user.get_formatted_name,
                "invoker" => user.get_formatted_name,
              }) }
              relay_to_one(message.message_id, user.id, :success)
            else
              relay_to_one(message.message_id, user.id, :no_user_found)
            end
          else
            relay_to_one(message.message_id, user.id, :missing_args)
          end
        end
      end
    end
  end

  # Warns a message without deleting it. Gives the user who sent the message a warning and a cooldown.
  @[Command(["warn"])]
  def warn_message(ctx) : Nil
    if history_with_warnings = @history.as?(HistoryFull)
      if (message = ctx.message) && (info = message.from)
        if user = database.get_user(info.id)
          unless user.can_use_command?
            return deny_user(user)
          end
          user.set_active(info.username, info.full_name)
          @database.modify_user(user)
          if user.authorized?(Ranks::Moderator)
            if reply = message.reply_message
              if reply_user = database.get_user(history_with_warnings.get_sender_id(reply.message_id))
                unless history_with_warnings.get_warning(reply.message_id) == true
                  reason = @replies.get_args(ctx.message.text)

                  duration = @replies.format_timespan(reply_user.cooldown_and_warn)
                  history_with_warnings.add_warning(reply.message_id)
                  @database.modify_user(reply_user)

                  relay_to_one(history_with_warnings.get_origin_msid(reply.message_id), reply_user.id, :cooldown_given, {"reason" => reason, "duration" => duration})
                  Log.info { @replies.substitute_log(:warned, {
                    "id"       => user.id.to_s,
                    "name"     => user.get_formatted_name,
                    "oid"      => reply_user.get_obfuscated_id,
                    "duration" => duration,
                    "reason"   => reason,
                  }) }
                  relay_to_one(message.message_id, user.id, :success)
                else
                  relay_to_one(message.message_id, user.id, :already_warned)
                end
              else
                relay_to_one(message.message_id, user.id, :not_in_cache)
              end
            else
              relay_to_one(message.message_id, user.id, :no_reply)
            end
          end
        end
      end
    end
  end

  # Delete a message from a user, give a warning and a cooldown.
  @[Command(["delete"])]
  def delete_message(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Moderator)
          if reply = message.reply_message
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              reason = @replies.get_args(message.text)
              cached_msid = delete_messages(reply.message_id, reply_user.id)

              duration = @replies.format_timespan(reply_user.cooldown_and_warn)
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
            else
              relay_to_one(message.message_id, user.id, :not_in_cache)
            end
          else
            relay_to_one(message.message_id, user.id, :no_reply)
          end
        end
      end
    end
  end

  # Removes a cooldown and warning from a user if the user is in cooldown.
  @[Command(["uncooldown"])]
  def uncooldown_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Admin)
          if arg = @replies.get_args(message.text)
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
            uncooldown_user.remove_warning
            @database.modify_user(uncooldown_user)

            Log.info { @replies.substitute_log(:removed_cooldown, {
              "id"             => user.id.to_s,
              "name"           => user.get_formatted_name,
              "oid"            => uncooldown_user.get_obfuscated_id,
              "cooldown_until" => cooldown_until,
            }) }
            relay_to_one(message.message_id, user.id, :success)
          else
            relay_to_one(message.message_id, user.id, :missing_args)
          end
        end
      end
    end
  end

  # Remove a message from a user without giving a warning or cooldown.
  @[Command(["remove"])]
  def remove_message(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Moderator)
          if reply = message.reply_message
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              cached_msid = delete_messages(reply.message_id, reply_user.id)

              relay_to_one(cached_msid, reply_user.id, :message_removed, {"reason" => @replies.get_args(message.text)})
              Log.info { @replies.substitute_log(:message_removed, {
                "id"     => user.id.to_s,
                "name"   => user.get_formatted_name,
                "msid"   => cached_msid.to_s,
                "oid"    => reply_user.get_obfuscated_id,
                "reason" => @replies.get_args(message.text),
              }) }
              relay_to_one(message.message_id, user.id, :success)
            else
              relay_to_one(message.message_id, user.id, :not_in_cache)
            end
          else
            relay_to_one(message.message_id, user.id, :no_reply)
          end
        end
      end
    end
  end

  # Delete all messages from recently blacklisted users.
  @[Command(["purge"])]
  def delete_all_messages(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Admin)
          if banned_users = @database.get_blacklisted_users
            delete_msids = 0
            banned_users.each do |banned_user|
              @history.get_msids_from_user(banned_user.id).each do |msid|
                delete_messages(msid, banned_user.id)
                delete_msids += 1
              end

              relay_to_one(message.message_id, user.id, :purge_complete, {"msgs_deleted" => delete_msids})
            end
          end
        end
      end
    end
  end

  # Blacklists a user from the chat, deletes the reply, and removes all the user's incoming and outgoing messages from the queue.
  @[Command(["blacklist", "ban"])]
  def blacklist(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if user.authorized?(Ranks::Admin)
          if reply = ctx.message.reply_message
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              if reply_user.rank < user.rank
                reason = @replies.get_args(ctx.message.text)
                reply_user.blacklist(reason)
                @database.modify_user(reply_user)

                # Remove queued messages sent by and directed to blacklisted user.
                @queue.reject! do |msg|
                  msg.receiver == user.id || msg.sender == user.id
                end
                cached_msid = delete_messages(reply.message_id, reply_user.id)

                relay_to_one(cached_msid, reply_user.id, :blacklisted, {"reason" => reason})
                Log.info { @replies.substitute_log(:blacklisted, {
                  "id"      => reply_user.id.to_s,
                  "name"    => reply_user.get_formatted_name,
                  "invoker" => user.get_formatted_name,
                  "reason"  => reason,
                }) }
                relay_to_one(message.message_id, user.id, :success)
              end
            else
              relay_to_one(message.message_id, user.id, :not_in_cache)
            end
          else
            relay_to_one(message.message_id, user.id, :no_reply)
          end
        end
      end
    end
  end

  # Replies with the motd/rules associated with this bot.
  # If the host invokes this command, the motd/rules can be set or modified.
  @[Command(["motd", "rules"])]
  def motd(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)
        if arg = @replies.get_args(ctx.message.text)
          if user.authorized?(Ranks::Host)
            @database.set_motd(arg)
            relay_to_one(message.message_id, user.id, :success)
          end
        else
          if motd = @database.get_motd
            relay_to_one(message.message_id, user.id, @replies.custom(motd))
          end
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Returns a message containing all the commands that a user can use, according to the user's rank.
  @[Command(["help"])]
  def help_command(ctx) : Nil
    if (message = ctx.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_use_command?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        case user.rank
        when Ranks::Moderator.value
          relay_to_one(message.message_id, user.id, @replies.mod_help)
        when Ranks::Admin.value
          relay_to_one(message.message_id, user.id, @replies.admin_help)
        when Ranks::Host.value
          relay_to_one(message.message_id, user.id, @replies.host_help)
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Checks if the text contains a special font or starts a sign command.
  #
  # Returns the given text or a formatted text if it is allowed; nil if otherwise or a sign command could not be used.
  def check_text(text : String, user : Database::User, msid : Int64) : String?
    if !@replies.allow_text?(text)
      relay_to_one(msid, user.id, :rejected_message)
      return
    end

    case
    when !text.starts_with?('/')
      return text
    when text.starts_with?("/s"), text.starts_with?("/sign")
      if config.allow_signing
        unless (chat = get_chat(user.id)) && chat.has_private_forwards
          unless @spam.spammy_sign?(user.id, @config.sign_limit_interval)
            if (args = @replies.get_args(text)) && args.size > 0
              return String.build do |str|
                str << args
                str << @replies.format_user_sign(user.id, user.get_formatted_name)
              end
            end
          else
            relay_to_one(msid, user.id, :sign_spam)
          end
        else
          relay_to_one(msid, user.id, :private_sign)
        end
      else
        relay_to_one(msid, user.id, :command_disabled)
      end
    when text.starts_with?("/t"), text.starts_with?("/tsign")
      if config.allow_tripcodes
        unless @spam.spammy_sign?(user.id, @config.sign_limit_interval)
          if tripkey = user.tripcode
            if (args = @replies.get_args(text)) && args.size > 0
              pair = @replies.generate_tripcode(tripkey, config.salt)
              return String.build do |str|
                str << @replies.format_tripcode_sign(pair[:name], pair[:tripcode]) << ":"
                str << "\n"
                str << args
              end
            end
          else
            relay_to_one(msid, user.id, :no_tripcode_set)
          end
        else
          relay_to_one(msid, user.id, :sign_spam)
        end
      else
        relay_to_one(msid, user.id, :command_disabled)
      end
    when text.starts_with?("/modsay")
      if user.authorized?(Ranks::Moderator)
        if (args = @replies.get_args(text)) && args.size > 0
          Log.info { @replies.substitute_log(:ranked_message, {
            "id"   => user.id.to_s,
            "name" => user.get_formatted_name,
            "rank" => Ranks::Moderator,
            "text" => args,
          }) }
          return String.build do |str|
            str << args
            str << @replies.format_user_say("mod")
          end
        end
      end
    when text.starts_with?("/adminsay")
      if user.authorized?(Ranks::Admin)
        if (args = @replies.get_args(text)) && args.size > 0
          Log.info { @replies.substitute_log(:ranked_message, {
            "id"   => user.id.to_s,
            "name" => user.get_formatted_name,
            "rank" => Ranks::Admin,
            "text" => args,
          }) }
          return String.build do |str|
            str << args
            str << @replies.format_user_say("admin")
          end
        end
      end
    when text.starts_with?("/hostsay")
      if user.authorized?(Ranks::Host)
        if (args = @replies.get_args(text)) && args.size > 0
          Log.info { @replies.substitute_log(:ranked_message, {
            "id"   => user.id.to_s,
            "name" => user.get_formatted_name,
            "rank" => Ranks::Host,
            "text" => args,
          }) }
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

      if user = database.get_user(info.id)
        unless user.can_chat?
          return deny_user(user)
        end
        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        if raw_text = message.text
          if text = check_text(@replies.strip_format(raw_text, message.entities), user, message.message_id)
            unless @spam.spammy?(info.id, @spam.calculate_spam_score_text(text))
              relay(
                message.reply_message,
                user,
                @history.new_message(user.id, message.message_id),
                ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, text, reply_to_message: reply) }
              )
            else
              return relay_to_one(message.message_id, user.id, :spamming)
            end
          end
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  {% for captioned_type in ["animation", "audio", "document", "video", "video_note", "voice", "photo"] %}
  # Prepares a {{captioned_type}} message for relaying.
  @[On(:{{captioned_type.id}})]
  def handle_{{captioned_type.id}}(update) : Nil
    if (message = update.message) && (info = message.from)
      if message.media_group_id || (message.forward_from || message.forward_from_chat)
        return
      end
      {% if captioned_type == "document" %}
        if message.animation
          return
        end
      {% end %}

      if user = database.get_user(info.id)
        unless user.can_chat?
          return deny_user(user)
        end

        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        if raw_caption = message.caption
          caption = check_text(@replies.strip_format(raw_caption, message.entities), user, message.message_id)
          if caption.nil? # Caption contained a special font or used a disabled command
            return 
          end
        end

        unless @spam.spammy?(info.id, @spam.calculate_spam_score(:{{captioned_type}}))
          relay(
            message.reply_message, 
            user, 
            @history.new_message(user.id, message.message_id),
            {% if captioned_type == "photo" %}
              ->(receiver : Int64, reply : Int64 | Nil) { send_photo(receiver, (message.photo.last).file_id, caption: caption, reply_to_message: reply) }
            {% else %}
              ->(receiver : Int64, reply : Int64 | Nil) { send_{{captioned_type.id}}(receiver, message.{{captioned_type.id}}.not_nil!.file_id, caption: caption, reply_to_message: reply) }
            {% end %}
          )
        else
          return relay_to_one(message.message_id, user.id, :spamming)
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end
  {% end %}

  # Prepares a album message for relaying.
  @[On(:media_group)]
  def handle_albums(update) : Nil
    if (message = update.message) && (info = message.from)
      if message.forward_from || message.forward_from_chat
        return
      end
      if user = database.get_user(info.id)
        unless user.can_chat?
          return deny_user(user)
        end

        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

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
            unless @spam.spammy?(info.id, @spam.calculate_spam_score(:album))
              temp_album.not_nil!.message_ids.each do |msid|
                cached_msids << @history.new_message(info.id, msid)
              end

              relay(
                message.reply_message,
                user,
                cached_msids,
                ->(receiver : Int64, reply : Int64 | Nil) { send_media_group(receiver, temp_album.not_nil!.media_ids, reply_to_message: reply) }
              )
            else
              relay_to_one(message.message_id, user.id, :spamming)
            end
          }
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Prepares a poll for relaying.
  @[On(:poll)]
  def handle_poll(update) : Nil
    if (message = update.message) && (info = message.from)
      if message.forward_from || message.forward_from_chat
        return
      end
      if user = database.get_user(info.id)
        unless user.can_chat?
          return deny_user(user)
        end

        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        if message.poll.not_nil!.anonymous? == false
          relay_to_one(message.message_id, user.id, :deanon_poll)
        else
          unless @spam.spammy?(info.id, @spam.calculate_spam_score(:poll))
            relay(
              message.reply_message,
              user,
              @history.new_message(user.id, message.message_id),
              ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
            )
          else
            return relay_to_one(message.message_id, user.id, :spamming)
          end
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Prepares a poll message for relaying.
  @[On(:forwarded_message)]
  def handle_forward(update) : Nil
    if (message = update.message) && (info = message.from)
      if user = database.get_user(info.id)
        unless user.can_chat?
          return deny_user(user)
        end

        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        unless @spam.spammy?(info.id, @spam.calculate_spam_score(:forward))
          relay(
            message.reply_message,
            user,
            @history.new_message(user.id, message.message_id),
            ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
          )
        else
          return relay_to_one(message.message_id, user.id, :spamming)
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  # Prepares a sticker message for relaying.
  @[On(:sticker)]
  def handle_sticker(update) : Nil
    if (message = update.message) && (info = message.from)
      if message.forward_from || message.forward_from_chat
        return
      end

      if user = database.get_user(info.id)
        unless user.can_chat?
          return deny_user(user)
        end

        user.set_active(info.username, info.full_name)
        @database.modify_user(user)

        unless @spam.spammy?(info.id, @spam.calculate_spam_score(:sticker))
          relay(
            message.reply_message,
            user,
            @history.new_message(user.id, message.message_id),
            ->(receiver : Int64, reply : Int64 | Nil) { send_sticker(receiver, message.sticker.not_nil!.file_id, reply_to_message: reply) }
          )
        else
          return relay_to_one(message.message_id, user.id, :spamming)
        end
      else
        relay_to_one(nil, info.id, :not_in_chat)
      end
    end
  end

  {% for luck_type in ["dice", "dart", "basketball", "soccerball", "slot_machine", "bowling"] %}
  # Prepares a {{luck_type}} message for relaying.
  @[On(:{{luck_type.id}})]
  def handle_{{luck_type.id}}(update) : Nil
    if config.relay_luck
      if (message = update.message) && (info = message.from)
        if (message.forward_from || message.forward_from_chat)
          return
        end
        if user = database.get_user(info.id)
          unless user.can_chat?
            return deny_user(user)
          end

          user.set_active(info.username, info.full_name)
          @database.modify_user(user)

          unless @spam.spammy?(info.id, @spam.calculate_spam_score(:{{luck_type}}))
            relay(
              message.reply_message,
              user,
              @history.new_message(user.id, message.message_id),
              ->(receiver : Int64, reply : Int64 | Nil) { send_{{luck_type.id}}(receiver, reply_to_message: reply) }
            )
          else
            return relay_to_one(message.message_id, user.id, :spamming)
          end
        else
          relay_to_one(nil, info.id, :not_in_chat)
        end
      end
    end
  end
  {% end %}

  # Prepares a venue message for relaying.
  @[On(:venue)]
  def handle_venue(update) : Nil
    if config.relay_venue
      if (message = update.message) && (info = message.from)
        if (message.forward_from || message.forward_from_chat)
          return
        end
        if user = database.get_user(info.id)
          unless user.can_chat?
            return deny_user(user)
          end

          user.set_active(info.username, info.full_name)
          @database.modify_user(user)

          unless @spam.spammy?(info.id, @spam.calculate_spam_score(:venue))
            venue = message.venue.not_nil!
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
          else
            return relay_to_one(message.message_id, user.id, :spamming)
          end
        else
          relay_to_one(nil, info.id, :not_in_chat)
        end
      end
    end
  end

  # Prepares a location message for relaying.
  @[On(:location)]
  def handle_location(update) : Nil
    if config.relay_location
      if (message = update.message) && (info = message.from)
        if (message.forward_from || message.forward_from_chat) || message.venue
          return
        end
        if user = database.get_user(info.id)
          unless user.can_chat?
            return deny_user(user)
          end

          user.set_active(info.username, info.full_name)
          @database.modify_user(user)

          unless @spam.spammy?(info.id, @spam.calculate_spam_score(:location))
            location = message.location.not_nil!
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
          else
            return relay_to_one(message.message_id, user.id, :spamming)
          end
        else
          relay_to_one(nil, info.id, :not_in_chat)
        end
      end
    end
  end

  # Prepares a contact message for relaying.
  @[On(:contact)]
  def handle_contact(update) : Nil
    if config.relay_contact
      if (message = update.message) && (info = message.from)
        if (message.forward_from || message.forward_from_chat)
          return
        end
        if user = database.get_user(info.id)
          unless user.can_chat?
            return deny_user(user)
          end

          user.set_active(info.username, info.full_name)
          @database.modify_user(user)

          unless @spam.spammy?(info.id, @spam.calculate_spam_score(:contact))
            contact = message.contact.not_nil!
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
          else
            return relay_to_one(message.message_id, user.id, :spamming)
          end
        else
          relay_to_one(nil, info.id, :not_in_chat)
        end
      end
    end
  end

  # Sends a message to the user explaining why they cannot chat at this time
  def deny_user(user : Database::User) : Nil
    if user.blacklisted?
      relay_to_one(nil, user.id, :blacklisted, {"reason" => user.blacklist_reason})
    elsif user.cooldown_until
      relay_to_one(nil, user.id, :on_cooldown, {"cooldown_until" => user.cooldown_until.not_nil!})
    else
      relay_to_one(nil, user.id, :not_in_chat)
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

  # Caches a message and sends it to the queue for relaying.
  def relay(reply_message : Tourmaline::Message?, user : Database::User, cached_msid : Int64 | Array(Int64), proc : MessageProc) : Nil
    if reply_message
      if (reply_msids = @history.get_all_msids(reply_message.message_id)) && (!reply_msids.empty?)
        @database.get_prioritized_users.each do |receiver_id|
          if receiver_id != user.id || user.debug_enabled
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
    rescue ex
      Log.error(exception: ex) { "Error occured when relaying message." }
    end
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
