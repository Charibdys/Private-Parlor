class PrivateParlor < Tourmaline::Client
  property database : Database
  property config : Hash(Symbol, String)
  property history : History
  property queue : Channel(QueuedMessage)
  getter tasks : Hash(Symbol, Tasker::Task)

  struct QueuedMessage
    getter hashcode : UInt64
    getter receiver : Int64
    getter function : Proc(Int64, Tourmaline::Message)
    
    # Creates an instance of `QueuedMessage` with a `hashcode` for caching and a `receiver` for the `function` proc.
    def initialize(hash : UInt64, receiver_id : Int64, func : Proc)
      @hashcode = hash
      @receiver = receiver_id
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
  # :     a `YAML::ANY` from parsing the `config.yaml` file
  #
  # `connection`
  #:      the DB::Databse object obtained from the database path in the `config.yaml` file
  def initialize(bot_token, config, connection)
    super(bot_token: bot_token)
    @config = config
    @database = Database.new(connection)
    @history = History.new(config[:lifetime].to_i8)
    @queue = Channel(QueuedMessage).new
    @tasks = register_tasks()
  end

  def register_tasks() : Hash
    tasks = {} of Symbol => Tasker::Task
    # Handle cache expiration
    tasks.merge!({:cache => Tasker.every(((1/4) * @history.lifespan).hours) {@history.expire}})
  end

  # Update user's record in database.
  def update_user(info, user : Database::User)
    user.username = info.username
    user.realname = info.full_name
    user.set_active
    database.modify_user(user) 
  end

  # Start bot and begin receiving messages.
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
      result = database.get_user(info.id)
      if result # User exists in DB; run checks
        if result.blacklisted?
          send_message(info.id, "You're blacklisted and cannot rejoin.")
        elsif result.left?
          result.rejoin
          update_user(info, result)
          send_message(info.id, "You rejoined the chat!")
        else # user is already in the chat
          update_user(info, result)
          send_message(info.id, "You're already in the chat.")
        end
      else # User does not exist; add to DB
        database.add_user(info.id, info.username, info.full_name)
        send_message(info.id, "Welcome to the chat!")
      end
    end
  end

  # Stops the bot for the user.
  #
  # This will set the user status to left, meaning the user will not receive any further messages.
  @[Command(["stop", "leave"])]
  def stop_command(ctx)
    if info = ctx.message.from.not_nil!
      result = database.get_user(info.id)
      if result
        result.set_left
        send_message(info.id, "You left the chat!")
        database.modify_user(result) 
      end
    end
  end

  # Checks if the message is a command and ensure that the user is in the chat.
  @[On(:message)]
  def check(update)
    if (message = update.message) && (info = message.from.not_nil!)
      if user = database.get_user(info.id)
        if message.text.not_nil!.[0] != '/'
          if user.left == nil
            # FIXME: If a user sends too many messages at once, this will lock the database
            # when the message is being relayed
            update_user(info, user)
            hash = @history.new_message(info.id, message.message_id)
            relay(message, info, hash)
          else
            send_message(user.id, "You're not in this chat!")
          end
        end
      end
    end
  end

  # Takes a message and returns a CoreMethod proc according to its content type.
  #
  # If a reply_msid is given, the proc will contain it.
  def type_to_proc(message, reply) : Proc(Int64, Tourmaline::Message) | Nil
    case message
    when .text
      proc = ->(receiver : Int64){send_message(receiver, message.text, reply_to_message: reply)}
    else # Message did not match any type; return nil and cease relaying for this message
      proc = nil
    end
  end

  # Relay message to every joined user except for the sender.
  def relay(message, info, hash)
    database.get_ids do |result|
      result.each do
        id = result.read(Int64)
        if id != info.id 
          if receiver = database.get_user(id)
            if receiver.left == nil
              reply_msid = nil
              if reply = message.reply_message
                reply_msid = @history.get_msid(reply.message_id, receiver.id)
              end
              
              if proc = type_to_proc(message, reply_msid)
                add_to_queue(hash, receiver.id, proc)
              end
            end
          end
        end
      end
    end
  end

  # Queue functions

  # Creates a new `Message` and sends it to the `queue` channel to be sent later.
  def add_to_queue(hashcode : UInt64, receiver_id : Int64, func : Proc)
    @queue.send(QueuedMessage.new(hashcode, receiver_id, func))
  end

  # Receives a `Message` from the `queue` channel, calls its proc, and adds the 
  # returned message id to the History
  #
  # This function should be invoked in a Fiber
  #
  # TODO: Check if receiver has blocked the bot.
  def send_messages
    msg = @queue.receive
    success = msg.function.call(msg.receiver)
    @history.add_to_cache(msg.hashcode, success.message_id, msg.receiver)
  end

end