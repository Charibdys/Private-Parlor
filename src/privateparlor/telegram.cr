require "digest"

# Bind to libcrypt
@[Link("crypt")]
lib LibCrypt
  fun crypt(password : UInt8*, salt : UInt8*) : UInt8*
end

class PrivateParlor < Tourmaline::Client
  property database : Database
  property history : History
  property queue : Channel(QueuedMessage)
  property replies : Replies
  property albums : Hash(String, Album)
  getter tasks : Hash(Symbol, Tasker::Task)
  getter config : Configuration::Config

  struct QueuedMessage
    getter hashcode : UInt64 | Array(UInt64)
    getter receiver : Int64
    getter reply_to : Int64 | Nil
    getter function : Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message))

    # Creates an instance of `QueuedMessage`.
    #
    # ## Arguments:
    #
    # `hash`
    # :     a hashcode that refers to the associated `MessageGroup` stored in the message history
    #
    # `receiver_id`
    # :     the ID of the user who will receive this message
    #
    # `reply_msid`
    # :     the MSID of a message to reply to. May be `nil` if this message isn't a reply.
    #
    # `function`
    # :     a proc that points to a Tourmaline CoreMethod send function and takes a user ID and MSID as its arguments
    def initialize(hash : UInt64 | Array(UInt64), receiver_id : Int64, reply_msid : Int64 | Nil, func : Proc)
      @hashcode = hash
      @receiver = receiver_id
      @reply_to = reply_msid
      @function = func
    end
  end

  struct Album
    property message_ids : Array(Int64)
    property media_ids : Array(InputMediaPhoto | InputMediaVideo | InputMediaAudio | InputMediaDocument)

    def initialize(msid : Int64, media : InputMediaPhoto | InputMediaVideo | InputMediaAudio | InputMediaDocument)
      @message_ids = [msid]
      @media_ids = [media]
    end
  end

  # Creates a new instance of PrivateParlor.
  #
  # ## Arguments:
  #
  # `bot_token`
  # :     the bot token given by `@BotFather`
  #
  # `config`
  # :     a `Hash(Symbol, String)` from parsing the `config.yaml` file
  #
  # `connection`
  # :     the `DB::Databse` object obtained from the database path in the `config.yaml` file
  def initialize(@config : Configuration::Config, parse_mode)
    super(bot_token: config.token, default_parse_mode: parse_mode)
    @database = Database.new(DB.open("sqlite3://#{Path.new(config.database)}")) # TODO: We'll want check if this works on Windows later
    @history = History.new(config.lifetime.hours)
    @queue = Channel(QueuedMessage).new
    @replies = Replies.new(config.entities)
    @tasks = register_tasks()
    @albums = {} of String => Album
  end

  # Starts various background tasks and stores them in a hash.
  def register_tasks : Hash
    tasks = {} of Symbol => Tasker::Task
    # Handle cache expiration
    tasks.merge!({:cache => Tasker.every(((1/4) * @history.lifespan.to_i).hours) { @history.expire }})
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
    if info = ctx.message.from.not_nil!
      user = database.get_user(info.id)
      if user # User exists in DB; run checks
        if user.blacklisted?
          send_message(user.id, @replies.blacklisted(user.blacklistReason))
        elsif user.left?
          user.rejoin
          update_user(info, user)
          send_message(user.id, @replies.rejoined)
          Log.info { "User #{user.id}, aka #{user.get_formatted_name}, rejoined the chat." }
        else # user is already in the chat
          update_user(info, user)
          send_message(user.id, @replies.already_in_chat)
        end
      else # User does not exist; add to DB
        if (database.no_users?)
          user = database.add_user(info.id, info.username, info.full_name, rank: 1000)
        else
          user = database.add_user(info.id, info.username, info.full_name)
        end

        send_message(user.id, @replies.joined)
        if motd = @database.get_motd
          send_message(user.id, @replies.custom(motd))
        end
        Log.info { "User #{user.id}, aka #{user.get_formatted_name}, joined the chat." }
      end
    end
  end

  # Stops the bot for the user.
  #
  # This will set the user status to left, meaning the user will not receive any further messages.
  @[Command(["stop", "leave"])]
  def stop_command(ctx)
    if info = ctx.message.from.not_nil!
      if (user = database.get_user(info.id)) && !user.left?
        user.set_left
        send_message(info.id, @replies.left)
        update_user(user)
        Log.info { "User #{user.id}, aka #{user.get_formatted_name}, left the chat." }
      end
    end
  end

  # Returns a message containing the user's OID, username, karma, warnings, etc.
  #
  # If this is used with a reply, returns the user info of that message if the invoker is ranked.
  @[Command(["info"])]
  def info_command(ctx)
    if info = ctx.message.from.not_nil!
      if user = database.get_user(info.id)
        if reply = ctx.message.reply_message
          if authorized?(user.id, Ranks::MOD)
            if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
              return send_message(user.id, @replies.user_info_mod(
                oid: reply_user.get_obfuscated_id,
                karma: reply_user.get_obfuscated_karma,
                cooldown_until: reply_user.cooldownUntil
              ))
            end
          end
        end

        return send_message(user.id, @replies.user_info(
          oid: user.get_obfuscated_id,
          username: user.get_formatted_name,
          rank: Ranks.new(user.rank),
          karma: user.karma,
          warnings: user.warnings,
          warn_expiry: user.warnExpiry,
          cooldown_until: user.cooldownUntil
        ))
      end
    end
  end

  # Upvotes a message.
  @[Command(["1"], prefix: ["+"])]
  def karma_command(ctx)
    if info = ctx.message.from.not_nil!
      if user = database.get_user(info.id)
        if reply = ctx.message.reply_message
          if (@history.get_sender_id(reply.message_id) == user.id)
            return send_message(user.id, @replies.upvoted_own_message)
          end
          if (!@history.add_rating(reply.message_id, user.id))
            return send_message(user.id, @replies.already_upvoted)
          end

          if reply_user = database.get_user(@history.get_sender_id(reply.message_id))
            reply_user.increment_karma
            update_user(reply_user)
            send_message(user.id, @replies.gave_upvote)
            if (!reply_user.hideKarma)
              send_message(reply_user.id, @replies.got_upvote)
            end
          end
        else
          return send_message(user.id, @replies.no_reply)
        end
      end
    end
  end

  # Toggle the user's hide_karma attribute.
  @[Command(["toggle_karma", "togglekarma"])]
  def toggle_karma_command(ctx)
    if info = ctx.message.from.not_nil!
      if user = database.get_user(info.id)
        user.toggle_karma
        send_message(info.id, @replies.toggle_karma(user.hideKarma))
        update_user(user)
      end
    end
  end

  # Set/modify/view the user's tripcode.
  @[Command(["tripcode"])]
  def tripcode_command(ctx)
    if info = ctx.message.from.not_nil!
      if user = database.get_user(info.id)
        if arg = get_args(ctx.message)
          if !((index = arg.index('#')) && (0 < index < arg.size - 1)) || arg.includes?('\n') || arg.size > 30
            return send_message(info.id, @replies.invalid_tripcode_format)
          end

          user.tripcode = arg
          update_user(user)

          results = generate_tripcode(arg)
          return send_message(info.id, @replies.tripcode_set(results[:name], results[:tripcode]))
        else
          return send_message(info.id, @replies.tripcode_info(user.tripcode))
        end
      end
    end
  end

  # Generate a 8chan or Secretlounge-ng style tripcode from a given string in the format `name#pass`.
  #
  # Returns a named tuple containing the tripname and tripcode.
  def generate_tripcode(tripkey : String) : NamedTuple
    split = tripkey.split('#', 2)
    name = split[0]
    pass = split[1]

    if !@config.salt.empty?
      # Based on 8chan's secure tripcodes
      salt = @config.salt
      pass = String.new(pass.encode("Shift_JIS"), "Shift_JIS")
      tripcode = "!#{Digest::SHA1.base64digest(pass + salt)[0...10]}"
    else
      salt = (pass[...8] + "H.")[1...3]
      salt = String.build do |s|
        salt.each_char do |c|
          if ':' <= c <= '@'
            s << c + 7
          elsif '[' <= c <= '`'
            s << c + 6
          elsif '.' <= c <= 'Z'
            s << c
          else
            s << '.'
          end
        end
      end

      tripcode = "!#{String.new(LibCrypt.crypt(pass[...8], salt))[-10...]}"
    end

    return {name: name, tripcode: tripcode}
  end

  ##################
  # ADMIN COMMANDS #
  ##################

  # Checks if the user is authorized to use a particular command.
  #
  # Returns true if authorized, false otherwise.
  def authorized?(user_id, rank : Ranks)
    if user = database.get_user(user_id)
      if user.rank >= rank.value
        return true
      else
        return false
      end
    end
  end

  # Promote a user to the moderator rank.
  @[Command(["mod"])]
  def mod_command(ctx)
    if info = ctx.message.from.not_nil!
      if authorized?(info.id, Ranks::HOST)
        arg = ctx.message.text.not_nil!
        if arg = arg.split[1]?
          if user = database.get_user_by_name(arg)
            if user.left?
              return
            elsif user.rank >= Ranks::MOD.value
              return
            else
              user.set_rank(Ranks::MOD)
              update_user(user)

              send_message(user.id, @replies.promoted(Ranks::MOD))
              Log.info { "User #{user.id}, aka #{user.get_formatted_name}, has been promoted to #{user.rank.to_s.downcase}." }
              return send_message(info.id, @replies.success)
            end
          end
        else
          return send_message(info.id, @replies.missing_args)
        end
      end
    end
  end

  # Promote a user to the administrator rank.
  @[Command(["admin"])]
  def admin_command(ctx)
    if info = ctx.message.from.not_nil!
      if authorized?(info.id, Ranks::HOST)
        arg = ctx.message.text.not_nil!
        if arg = arg.split[1]?
          if user = database.get_user_by_name(arg)
            if user.left?
              return
            elsif user.rank >= Ranks::ADMIN.value
              return
            else
              user.set_rank(Ranks::ADMIN)
              update_user(user)

              send_message(user.id, @replies.promoted(Ranks::ADMIN))
              return send_message(info.id, @replies.success)
            end
          end
        else
          return send_message(info.id, @replies.missing_args)
        end
      end
    end
  end

  # Returns a ranked user to the user rank
  @[Command(["demote"])]
  def demote_command(ctx)
    if info = ctx.message.from.not_nil!
      if authorized?(info.id, Ranks::HOST)
        if arg = get_args(ctx.message)
          if user = database.get_user_by_name(arg)
            user.set_rank(Ranks::USER)
            update_user(user)
            Log.info { "User #{user.id}, aka #{user.get_formatted_name}, has been demoted." }
            return send_message(info.id, @replies.success)
          end
        else
          return send_message(info.id, @replies.missing_args)
        end
      end
    end
  end

  # Delete a message from a user, give a warning and a cooldown.
  # TODO: Implement warning/cooldown system
  @[Command(["delete"])]
  def delete_message(ctx)
    if info = ctx.message.from.not_nil!
      if authorized?(info.id, Ranks::MOD)
        if reply = ctx.message.reply_message
          reply_msids = @history.get_all_msids(reply.message_id)
          reply_msids.each_key do |receiver_id|
            if receiver_id != @history.get_sender_id(reply.message_id)
              delete_message(receiver_id, reply_msids[receiver_id])
            end
          end

          send_message(@history.get_sender_id(reply.message_id), @replies.message_deleted(true, get_args(ctx.message)), reply_to_message: reply_msids[@history.get_sender_id(reply.message_id)])
          @history.del_message_group(reply.message_id)

          return send_message(info.id, @replies.success)
        else
          return send_message(info.id, @replies.no_reply)
        end
      end
    end
  end

  # Remove a message from a user without giving a warning or cooldown.
  @[Command(["remove"])]
  def remove_message(ctx)
    if info = ctx.message.from.not_nil!
      if authorized?(info.id, Ranks::MOD)
        if reply = ctx.message.reply_message
          reply_msids = @history.get_all_msids(reply.message_id)
          reply_msids.each_key do |receiver_id|
            if receiver_id != @history.get_sender_id(reply.message_id)
              delete_message(receiver_id, reply_msids[receiver_id])
            end
          end

          send_message(@history.get_sender_id(reply.message_id), @replies.message_deleted(false, get_args(ctx.message)), reply_to_message: reply_msids[@history.get_sender_id(reply.message_id)])
          @history.del_message_group(reply.message_id)

          return send_message(info.id, @replies.success)
        else
          return send_message(info.id, @replies.no_reply)
        end
      end
    end
  end

  # Delete all messages from recently blacklisted users.
  @[Command(["purge"])]
  def delete_all_messages(ctx)
    if info = ctx.message.from.not_nil!
      if authorized?(info.id, Ranks::ADMIN)
        if user = @database.get_blacklisted_users
          delete_msids = [] of Int64
          user.each do |user|
            @history.get_msids_from_user(user.id).each do |msid|
              reply_msids = @history.get_all_msids(msid)
              reply_msids.each_key do |receiver_id|
                if receiver_id != user.id
                  delete_message(receiver_id, reply_msids[receiver_id])
                end
              end
              delete_msids << msid
            end

            delete_msids.each do |msid|
              @history.del_message_group(msid)
            end

            return send_message(info.id, @replies.purge_complete(delete_msids.size))
          end
        end
      end
    end
  end

  @[Command(["blacklist", "ban"])]
  def blacklist(ctx)
    if info = ctx.message.from.not_nil!
      if authorized?(info.id, Ranks::ADMIN)
        if reply = ctx.message.reply_message
          if user = database.get_user(@history.get_sender_id(reply.message_id))
            reason = get_args(ctx.message)
            user.blacklist(reason)
            update_user(user)

            send_message(user.id, @replies.blacklisted(get_args(ctx.message)), reply_to_message: @history.get_msid(reply.message_id, user.id))
            Log.info { "User #{user.id}, aka #{user.get_formatted_name}, has been blacklisted#{reason ? " for: #{reason}" : "."}" }

            return send_message(info.id, @replies.success)
          end
        else
          return send_message(info.id, @replies.no_reply)
        end
      end
    end
  end

  # Replies with the motd/rules associated with this bot.
  # If the host invokes this command, the motd/rules can be set or modified.
  @[Command(["motd", "rules"])]
  def motd(ctx)
    if info = ctx.message.from.not_nil!
      if arg = get_args(ctx.message)
        if authorized?(info.id, Ranks::HOST)
          @database.set_motd(arg)
          return send_message(info.id, @replies.success)
        end
      else
        if motd = @database.get_motd
          return send_message(info.id, @replies.custom(motd), reply_to_message: ctx.message.message_id)
        end
      end
    end
  end

  # Checks if the message is a command and ensure that the user is in the chat.
  @[On(:message)]
  def check(update)
    if (message = update.message) && (info = message.from.not_nil!)
      if (text = message.text) || (text = message.caption)
        if !@replies.allow_text?(text)
          return send_message(info.id, @replies.rejected_message)
        end
      end
      if (user = database.get_user(info.id)) && !user.left?
        if !((text = message.text) && text.starts_with?('/')) # Don't relay commands
          # NOTE: If a user sends too many messages at once, this may lock the database when relaying messages
          update_user(info, user)
          if (check_message_type(message, info))
            hash = @history.new_message(info.id, message.message_id)
            relay(message, info, hash)
          end
        end
      else # Either user has left or is not in the database
        send_message(info.id, @replies.not_in_chat)
      end
    end
  end

  # Check whether or not the type of message should be relayed
  # Prevents non-anonymous polls and handles Album relaying
  #
  # Returns true if the message type is allowed, false otherwise
  def check_message_type(message, info) : Bool
    if poll = message.poll
      if poll.is_anonymous == false
        send_message(info.id, @replies.deanon_poll)
        return false
      end
    end

    if album = message.media_group_id
      # Can't use @replies.strip_format() as that will send the caption with formatting syntax escaped
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
        return false
      end

      if @albums[album]?
        @albums[album].message_ids << message.message_id
        @albums[album].media_ids << input
      else
        media_group = Album.new(message.message_id, input)
        @albums[album] = media_group

        # Wait an arbitrary amount of time for Telegram MediaGroup updates to come in before relaying the album.
        Tasker.at(2.seconds.from_now) {
          hash = Array(UInt64).new
          @albums[album].message_ids.each do |msid|
            hash << @history.new_message(info.id, msid)
          end

          relay(message, info, hash)
        }
      end
      return false
    end
    return true
  end

  # Takes a message and returns a CoreMethod proc according to its content type.
  def type_to_proc(message) : Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message)) | Nil
    if (forward = message.forward_from) || (forward = message.forward_from_chat)
      return proc = ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }
    end

    if album = message.media_group_id
      if temp_album = @albums.delete(album)
        return proc = ->(receiver : Int64, reply : Int64 | Nil) { send_media_group(receiver, temp_album.media_ids, reply_to_message: reply) }
      else
        return nil
      end
    end

    if caption = message.caption
      caption = @replies.strip_format(caption, message.caption_entities)
    end

    # Standard text message
    if text = message.text
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_message(receiver, @replies.strip_format(text, message.entities), reply_to_message: reply) }

      # Captioned types
    elsif animation = message.animation
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_animation(receiver, animation.file_id, caption: caption, reply_to_message: reply) }
    elsif audio = message.audio
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_audio(receiver, audio.file_id, caption, reply_to_message: reply) }
    elsif document = message.document
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_document(receiver, document.file_id, caption, reply_to_message: reply) }
    elsif video = message.video
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_video(receiver, video.file_id, caption: caption, reply_to_message: reply) }
    elsif video_note = message.video_note
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_video_note(receiver, video_note.file_id, caption: caption, reply_to_message: reply) }
    elsif voice = message.voice
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_voice(receiver, voice.file_id, caption, reply_to_message: reply) }
    elsif photo = message.photo.last? # The last photo in the array will have the highest resolution
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_photo(receiver, photo.file_id, caption, reply_to_message: reply) }

      # Forward polls
    elsif poll = message.poll
      proc = ->(receiver : Int64, reply : Int64 | Nil) { forward_message(receiver, message.chat.id, message.message_id) }

      # Stickers
    elsif sticker = message.sticker
      proc = ->(receiver : Int64, reply : Int64 | Nil) { send_sticker(receiver, sticker.file_id, reply_to_message: reply) }

      # Dice and other luck types
    elsif dice = message.dice
      if config.relay_luck
        case dice.emoji
        when "🎲"
          proc = ->(receiver : Int64, reply : Int64 | Nil) { send_dice(receiver, message.text, reply_to_message: reply) }
        when "🎯"
          proc = ->(receiver : Int64, reply : Int64 | Nil) { send_dart(receiver, message.text, reply_to_message: reply) }
        when "🏀"
          proc = ->(receiver : Int64, reply : Int64 | Nil) { send_basketball(receiver, message.text, reply_to_message: reply) }
        when "⚽"
          proc = ->(receiver : Int64, reply : Int64 | Nil) { send_soccerball(receiver, message.text, reply_to_message: reply) }
        when "🎰"
          proc = ->(receiver : Int64, reply : Int64 | Nil) { send_slot_machine(receiver, message.text, reply_to_message: reply) }
        when "🎳"
          proc = ->(receiver : Int64, reply : Int64 | Nil) { send_bowling(receiver, message.text, reply_to_message: reply) }
        end
      else
        proc = nil
      end
    else # Message did not match any type; return nil and cease relaying for this message
      proc = nil
    end
  end

  # Relay message to every joined user except for the sender.
  def relay(message, info, hash)
    if proc = type_to_proc(message)
      if !(reply = message.reply_message)                     # Message was NOT a reply
        @database.get_prioritized_users.each do |receiver_id| # No need for a left? check here
          if receiver_id != info.id
            add_to_queue(hash, receiver_id, nil, proc)
          end
        end
      else # Message was a reply
        reply_msids = @history.get_all_msids(reply.message_id)
        @database.get_prioritized_users.each do |receiver_id|
          if receiver_id != info.id
            add_to_queue(hash, receiver_id, reply_msids[receiver_id], proc)
          end
        end
      end
    else
      Log.error { "Could not create proc for message type. Message was #{message}" }
    end
  end

  # Returns arguments found after a command from a message text.
  def get_args(msg : Tourmaline::Message, count : Int = 1) : String | Array(String) | Nil
    args = msg.text.not_nil!.split(count + 1)
    case args.size
    when 2
      return args[1]
    when 2..
      return args.shift
    else
      return nil
    end
  end

  ###################
  # Queue functions #
  ###################

  # Creates a new `Message` and sends it to the `queue` channel to be sent later.
  def add_to_queue(hashcode : UInt64 | Array(UInt64), receiver_id : Int64, reply_msid : Int64 | Nil, func : Proc)
    @queue.send(QueuedMessage.new(hashcode, receiver_id, reply_msid, func))
  end

  # Receives a `Message` from the `queue` channel, calls its proc, and adds the
  # returned message id to the History
  #
  # This function should be invoked in a Fiber
  #
  # TODO: Check if receiver has blocked the bot.
  def send_messages
    msg = @queue.receive
    success = msg.function.call(msg.receiver, msg.reply_to)

    if !success.is_a?(Array(Tourmaline::Message))
      @history.add_to_cache(msg.hashcode.as(UInt64), success.message_id, msg.receiver)
    else
      sent_msids = success.map { |msg| msg.message_id }

      sent_msids.zip(msg.hashcode.as(Array(UInt64))) do |msid, hashcode|
        @history.add_to_cache(hashcode, msid, msg.receiver)
      end
    end
  end
end

enum Ranks
  BANNED =  -10
  USER   =    0
  MOD    =   10
  ADMIN  =  100
  HOST   = 1000
end
