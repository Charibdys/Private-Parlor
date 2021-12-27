class PrivateParlor < Tourmaline::Client
  property database : Database
  property config : YAML::Any
  property history : History
  getter tasks : Hash(Symbol, Tasker::Task)

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
    @history = History.new(24)
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
            @history.new_message(info.id, message.message_id)
            relay(message, info)
          else
            send_message(user.id, "You're not in this chat!")
          end
        end
      end
    end
  end

  # Relay message to every joined user except for the sender.
  #
  # TODO: Check if receiver has blocked the bot.
  def relay(message, info)
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
              success = send_message(receiver.id, message.text, reply_to_message: reply_msid)
              @history.add_to_cache(success.message_id, receiver.id)
            end
          end
        end
      end
    end
  end

end