require "digest"

@[Link("crypt")]
lib LibCrypt
  fun crypt(password : UInt8*, salt : UInt8*) : UInt8*
end

class Replies
  include Tourmaline::Format
  include Tourmaline::Helpers

  getter entity_types : Array(String) # TODO: See if this attribute can be removed entirely

  getter replies : Hash(Symbol, String) = {} of Symbol => String
  getter logs : Hash(Symbol, String) = {} of Symbol => String
  getter time_units : Array(String)
  getter time_format : String
  getter toggle : Array(String)

  # Creates an instance of `Replies`.
  #
  # ## Arguments:
  #
  # `entities`
  # :     an array of strings refering to one or more of the possible message entity types
  def initialize(entities : Array(String), locale : String)
    begin
      yaml = File.open("./locales/#{locale}.yaml") do |file|
        YAML.parse(file)
      end
    rescue ex : YAML::ParseException
      Log.error(exception: ex) { "Could not parse the given value at row #{ex.line_number}. This could be because a required value was not set or the wrong type was given." }
      exit
    rescue ex : File::NotFoundError | File::AccessDeniedError
      Log.error(exception: ex) { "Could not open \"./locales/#{locale}.yaml\". Exiting..." }
      exit
    end

    reply_keys = %i(
      joined rejoined left already_in_chat not_in_chat not_in_cooldown rejected_message deanon_poll
      missing_args command_disabled no_reply not_in_cache no_tripcode_set no_user_found no_user_oid_found
      promoted toggle_karma toggle_debug gave_upvote got_upvote upvoted_own_message already_voted
      gave_downvote got_downvote downvoted_own_message already_warned private_sign spamming
      sign_spam invalid_tripcode_format tripcode_set tripcode_info tripcode_unset user_info ranked_info
      cooldown_true cooldown_false user_count user_count_full message_deleted message_removed
      reason_prefix cooldown_given on_cooldown blacklisted purge_complete success
    )

    log_keys = %i(
      start joined rejoined left promoted demoted warned message_deleted message_removed removed_cooldown
      blacklisted reason_prefix ranked_message force_leave
    )

    @entity_types = entities
    @time_units = yaml["time_units"].as_a.map(&.as_s)
    @time_format = yaml["time_format"].as_s
    @toggle = yaml["toggle"].as_a.map(&.as_s)
    @replies = Hash.zip(reply_keys, yaml["replies"].as_a.map(&.as_s))
    @logs = Hash.zip(log_keys, yaml["logs"].as_a.map(&.as_s))
  end

  # Globally substitutes placeholders in reply with the given variables
  def substitute_reply(key : Symbol, variables : LocaleParameters = {"" => ""}) : String
    if @replies[key].nil?
      Log.warn { "There was no reply available with key #{key}" }
      return ""
    end

    if @replies[key].scan(/\#{\w*}/).size != 0
      if variables.size == 1 && variables[""]? == ""
        Log.warn { "\"#{key}\" reply has placeholders, but no parameters were available!" }
      end

      @replies[key].gsub(/\#{\w*}/) do |match|
        placeholder = match.strip("\#{}")
        case placeholder
        when "toggle"
          replace = variables[placeholder] ? @toggle[1] : @toggle[0]
        when "rank"
          replace = variables[placeholder]?.to_s.downcase
        when "cooldown_until"
          if variables[placeholder]
            replace = "#{@replies[:cooldown_true]} #{variables[placeholder]}"
          else
            replace = @replies[:cooldown_false]
          end
        when "reason"
          if variables[placeholder]
            replace = "#{@replies[:reason_prefix]}#{variables[placeholder]}"
          end
        when "tripcode"
          if variables[placeholder]
            replace = variables[placeholder].to_s
          else
            replace = @replies[:tripcode_unset]
          end
        else
          replace = variables[placeholder]?.to_s
        end

        if replace
          replace = replace.to_md
        end
        replace
      end
    else
      @replies[key]
    end
  end

  # Globally substitutes placeholders in log message with the given variables
  def substitute_log(key : Symbol, variables : LocaleParameters = {"" => ""}) : String
    if @logs[key].nil?
      Log.warn { "There was no log message available with key #{key}" }
      return ""
    end

    if @logs[key].scan(/\#{\w*}/).size != 0
      if variables.size == 1 && variables[""]? == ""
        Log.warn { "\"#{key}\" log message has placeholders, but no parameters were available!" }
      end

      @logs[key].gsub(/\#{\w*}/) do |match|
        placeholder = match.strip("\#{}")
        case placeholder
        when "rank"
          variables[placeholder]?.to_s.downcase
        when "reason"
          if variables[placeholder]?
            "#{@logs[:reason_prefix]}#{variables[placeholder]}"
          end
        else
          variables[placeholder]?.to_s
        end
      end
    else
      @logs[key]
    end
  end

  # Takes the URL found in an inline link and appends it to the message text.
  def replace_links(text : String, entities : Array(Tourmaline::MessageEntity)) : String
    entities.each do |entity|
      if entity.type == "text_link" && (url = entity.url)
        if url.starts_with?("tg://")
          next
        end

        if url.includes?("://t.me/") && url.includes?("?start=")
          next
        end

        text += "\n(#{url})"
      end
    end
    text
  end

  # Checks the content of the message text and determines if it should be relayed.
  #
  # Returns false if the text has mathematical alphanumeric symbols, as they contain bold and italic characters.
  def allow_text?(text : String) : Bool
    if text.empty?
      true
    elsif text.codepoints.any? { |codepoint| (0x1D400..0x1D7FF).includes?(codepoint) }
      false
    else
      true
    end
  end

  # Strips message entities if they're found in `entity_types`
  def remove_entities(entities : Array(Tourmaline::MessageEntity)) : Array(Tourmaline::MessageEntity)
    stripped_entities = [] of Tourmaline::MessageEntity

    entities.each do |entity|
      if @entity_types.includes?(entity.type)
        stripped_entities << entity
      end
    end

    entities - stripped_entities
  end

  # Strips MarkdownV2 format from a message and escapes formatting found in `MessageEntities`.
  # If the message has `MessageEntities`, replaces any inline links and removes entities found in `entity_types`.
  def strip_format(text : String, entities : Array(Tourmaline::MessageEntity)) : String
    if !entities.empty?
      text = replace_links(text, entities)
      entities = remove_entities(entities)
    end
    unparse_text(text, entities, Tourmaline::ParseMode::MarkdownV2, escape: true)
  end

  # Generate a 8chan or Secretlounge-ng style tripcode from a given string in the format `name#pass`.
  #
  # Returns a named tuple containing the tripname and tripcode.
  def generate_tripcode(tripkey : String, salt : String) : NamedTuple
    split = tripkey.split('#', 2)
    name = split[0]
    pass = split[1]

    if !salt.empty?
      # Based on 8chan's secure tripcodes
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

    {name: name, tripcode: tripcode}
  end

  # Returns arguments found after a command from a message text.
  def get_args(msg : String?, count : Int = 1) : String | Array(String) | Nil
    if msg
      args = msg.split(count + 1)
      case args.size
      when 2
        return args[1]
      when 2..
        return args.shift
      else
        return nil
      end
    end
  end

  # Returns a link to the given user's account.
  def format_user_sign(id : Int64, name : String) : String
    Link.new("~~#{name}", "tg://user?id=#{id}").to_md
  end

  # Returns a bolded signature showing which type of user sent this message.
  def format_user_say(signature : String) : String
    Bold.new("~~#{signature}").to_md
  end

  # Returns a tripcode (Name!Tripcode) segment.
  def format_tripcode_sign(name : String, tripcode : String) : String
    Group.new(Bold.new(name), Code.new(tripcode)).to_md
  end

  # Formats a timespan, so the duration is marked by its largest unit ("20m", "3h", "5d", etc)
  def format_timespan(cmp : Time::Span) : String
    case
    when cmp >= Time::Span.new(days: 7)
      "#{cmp.total_weeks.floor.to_i}#{@time_units[0]}"
    when cmp >= Time::Span.new(days: 1)
      "#{cmp.total_days.floor.to_i}#{@time_units[1]}"
    when cmp >= Time::Span.new(hours: 1)
      "#{cmp.total_hours.floor.to_i}#{@time_units[2]}"
    when cmp >= Time::Span.new(minutes: 1)
      "#{cmp.total_minutes.floor.to_i}#{@time_units[3]}"
    else
      "#{cmp.to_i}#{@time_units[4]}"
    end
  end

  def format_smiley(warnings : Int32, smileys : Array(String)) : String
    if warnings <= 0
      smileys[0]
    elsif warnings == 1
      smileys[1]
    elsif warnings <= 3
      smileys[2]
    else
      smileys[3]
    end
  end

  def format_time(time : Time?) : String?
    if time
      time.to_s(@time_format)
    end
  end

  # Returns a message containing the program version and a link to its Git repo.
  #
  # Feel free to edit this if you fork the code.
  def version : String
    Group.new("Private Parlor v#{VERSION} ~ ", Link.new("[Source]", "https://github.com/Charibdys/Private-Parlor")).to_md
  end

  # Returns a custom text from a given string.
  def custom(text : String) : String
    Section.new(text).to_md
  end

  # TODO: Move command descriptions to locale
  # Returns a message containing the commands the a moderator can use.
  def mod_help : String
    Section.new(
      Italic.new("The following commands are available to moderators:"),
      "    /help - Show this text",
      "    /modsay [text] - Send an offical moderator message",
      Italic.new("The commands below must be used with a reply:"),
      "    /info - Get the user info from this message",
      "    /delete [reason] - Delete a message and give a cooldown",
      "    /remove [reason] - Delete a message without giving a cooldown",
      indent: 0
    ).to_md
  end

  # TODO: Move command descriptions to locale
  # Returns a message containing the commands the an admin can use.
  def admin_help : String
    Section.new(
      Italic.new("The following commands are available to admins:"),
      "    /help - Show this text",
      "    /purge - Delete all messages from a blacklisted user",
      "    /adminsay [text] - Send an official admin message",
      Italic.new("The commands below must be used with a reply:"),
      "    /info - Get the user info from this message",
      "    /blacklist [reason] - Ban a user from the chat",
      "    /delete [reason] - Delete a message and give a cooldown",
      "    /remove [reason] - Delete a message without giving a cooldown",
      indent: 0
    ).to_md
  end

  # TODO: Move command descriptions to locale
  # Returns a message containing the commands the a host can use.
  def host_help : String
    Section.new(
      Italic.new("The following commands are available to hosts:"),
      "    /help - Show this text",
      "    /purge - Delete all messages from a blacklisted user",
      "    /mod [username] - Promote a user to moderator",
      "    /admin [username] - Promote a user to admin",
      "    /demote [username] - Demote a user",
      "    /motd [text] - Set the motd (users will see this when joining)",
      "    /hostsay [text] - Send an official host message",
      Italic.new("The commands below must be used with a reply:"),
      "    /info - Get the user info from this message",
      "    /blacklist [reason] - Ban a user from the chat",
      "    /delete [reason] - Delete a message and give a cooldown",
      "    /remove [reason] - Delete a message without giving a cooldown",
      indent: 0
    ).to_md
  end
end
