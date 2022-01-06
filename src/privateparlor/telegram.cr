class PrivateParlor < Tourmaline::Client
  property database : Database
  property history : History
  property queue : Channel(QueuedMessage)
  property replies : Replies
  getter tasks : Hash(Symbol, Tasker::Task)
  getter config : NamedTuple(
    token: String,
    database: String,
    log_level: String,
    log_path: String,
    lifetime: Time::Span,
    relay_luck: Bool,
    entities: Array(String)
    )

  struct QueuedMessage
    getter hashcode : UInt64
    getter receiver : Int64
    getter reply_to : Int64 | Nil
    getter function : Proc(Int64, Int64 | Nil, Tourmaline::Message)
    
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
    def initialize(hash : UInt64, receiver_id : Int64, reply_msid : Int64 | Nil, func : Proc)
      @hashcode = hash
      @receiver = receiver_id
      @reply_to = reply_msid
      @function = func
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
  def initialize(bot_token, config, connection, parse_mode)
    super(bot_token: bot_token, default_parse_mode: parse_mode)
    @config = config
    @database = Database.new(connection)
    @history = History.new(config[:lifetime])
    @queue = Channel(QueuedMessage).new
    @replies = Replies.new(config[:entities])
    @tasks = register_tasks()
  end

  # Starts various background tasks and stores them in a hash.
  def register_tasks() : Hash
    tasks = {} of Symbol => Tasker::Task
    # Handle cache expiration
    tasks.merge!({:cache => Tasker.every(((1/4) * @history.lifespan.to_i).hours) {@history.expire}})
  end

  # Updates user's record in the database.
  def update_user(info, user : Database::User)
    user.username = info.username
    user.realname = info.full_name
    user.set_active
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
          send_message(user.id, @replies.blacklisted(user.blacklist_text))
        elsif user.left?
          user.rejoin
          update_user(info, user)
          send_message(user.id, @replies.rejoined)
        else # user is already in the chat
          update_user(info, user)
          send_message(user.id, @replies.already_in_chat)
        end
      else # User does not exist; add to DB
        user = database.add_user(info.id, info.username, info.full_name)
        send_message(user.id, @replies.joined)
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
        database.modify_user(user) 
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
          hash = @history.new_message(info.id, message.message_id)
          relay(message, info, hash)
        end
      else # Either user has left or is not in the database
        send_message(info.id, @replies.not_in_chat)
      end
    end
  end

  # Takes a message and returns a CoreMethod proc according to its content type.
  def type_to_proc(message) : Proc(Int64, Int64 | Nil, Tourmaline::Message) | Nil
    case message
    when .text
      text = @replies.strip_format(message.text.not_nil!, message.entities)
      proc = ->(receiver : Int64, reply : Int64 | Nil){send_message(receiver, text, entities: message.entities, reply_to_message: reply)}
    when .dice
      if @config[:relay_luck]
        case message.dice.not_nil!.emoji
        when "🎲"
          proc = ->(receiver : Int64, reply : Int64 | Nil){send_dice(receiver, message.text, reply_to_message: reply)}
        when "🎯"
          proc = ->(receiver : Int64, reply : Int64 | Nil){send_dart(receiver, message.text, reply_to_message: reply)}
        when "🏀"
          proc = ->(receiver : Int64, reply : Int64 | Nil){send_basketball(receiver, message.text, reply_to_message: reply)}
        when "⚽"
          proc = ->(receiver : Int64, reply : Int64 | Nil){send_soccerball(receiver, message.text, reply_to_message: reply)}
        when "🎰"
          proc = ->(receiver : Int64, reply : Int64 | Nil){send_slot_machine(receiver, message.text, reply_to_message: reply)}
        when "🎳"
          proc = ->(receiver : Int64, reply : Int64 | Nil){send_bowling(receiver, message.text, reply_to_message: reply)}
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
      if !(reply = message.reply_message) # Message was NOT a reply
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
      Log.error {"Could not create proc for message type. Message was #{message}"}
    end
  end

  ###################
  # Queue functions #
  ###################

  # Creates a new `Message` and sends it to the `queue` channel to be sent later.
  def add_to_queue(hashcode : UInt64, receiver_id : Int64, reply_msid : Int64 | Nil, func : Proc)
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
    @history.add_to_cache(msg.hashcode, success.message_id, msg.receiver)
  end

end