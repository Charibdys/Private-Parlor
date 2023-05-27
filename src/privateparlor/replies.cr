require "digest"

@[Link("crypt")]
lib LibCrypt
  fun crypt(password : UInt8*, salt : UInt8*) : UInt8*
end

alias LocaleParameters = Hash(String, String | Array(String) | Time | Int32 | Bool | Rank | Nil)

class Replies
  include Tourmaline::Format
  include Tourmaline::Helpers

  getter entity_types : Array(String) # TODO: See if this attribute can be removed entirely

  getter replies : Hash(Symbol, String) = {} of Symbol => String
  getter logs : Hash(Symbol, String) = {} of Symbol => String
  getter command_descriptions : Hash(Symbol, String) = {} of Symbol => String
  getter time_units : Array(String)
  getter time_format : String
  getter toggle : Array(String)
  getter smileys : Array(String)
  getter blacklist_contact : String?
  getter tripcode_salt : String

  # Creates an instance of `Replies`.
  #
  # ## Arguments:
  #
  # `entities`
  # :     an array of strings refering to one or more of the possible message entity types
  #
  # `locale`
  # :     a language code, corresponding to one of the locales in the locales folder
  #
  # `smileys`
  # :     an array of four smileys
  #
  # `salt`
  # :     a salt used for hashing tripcodes
  def initialize(entities : Array(String), locale : String, smileys : Array(String), contact : String?, salt : String)
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
      joined rejoined left already_in_chat registration_closed not_in_chat not_in_cooldown rejected_message deanon_poll
      missing_args command_disabled media_disabled no_reply not_in_cache no_tripcode_set no_user_found no_user_oid_found
      no_rank_found promoted help_header help_rank_commands help_reply_commands toggle_karma toggle_debug gave_upvote got_upvote upvoted_own_message already_voted
      gave_downvote got_downvote downvoted_own_message already_warned private_sign spamming sign_spam 
      upvote_spam downvote_spam invalid_tripcode_format tripcode_set tripcode_info tripcode_unset 
      user_info info_warning ranked_info cooldown_true cooldown_false user_count user_count_full
      message_deleted message_removed reason_prefix cooldown_given on_cooldown media_limit blacklisted 
      blacklist_contact purge_complete inactive success fail
    )

    log_keys = %i(
      start joined rejoined left promoted demoted warned message_deleted message_removed removed_cooldown
      blacklisted reason_prefix spoiled unspoiled ranked_message force_leave
    )

    command_keys = %i(
      start stop info users version upvote downvote toggle_karma toggle_debug tripcode promote demote
      sign tsign ranksay warn delete uncooldown remove purge spoiler blacklist motd help motd_set ranked_info
    )

    @entity_types = entities
    @smileys = smileys
    @blacklist_contact = contact
    @tripcode_salt = salt
    @time_units = yaml["time_units"].as_a.map(&.as_s)
    @time_format = yaml["time_format"].as_s
    @toggle = yaml["toggle"].as_a.map(&.as_s)
    @replies = Hash.zip(reply_keys, yaml["replies"].as_a.map(&.as_s))
    @logs = Hash.zip(log_keys, yaml["logs"].as_a.map(&.as_s))
    @command_descriptions = Hash.zip(command_keys, yaml["command_descriptions"].as_a.map(&.as_s))
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
          replace = variables[placeholder]?.to_s
        when "cooldown_until"
          if variables[placeholder]
            replace = "#{@replies[:cooldown_true]} #{variables[placeholder]}"
          else
            replace = @replies[:cooldown_false]
          end
        when "warn_expiry"
          if variables[placeholder]
            # Skip replace.to_md to prevent escaping Markdown twice
            next replace = @replies[:info_warning].gsub("#\{warn_expiry\}") { "#{variables[placeholder]}".to_md }
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
        when "contact"
          if blacklist_contact
            replace = @replies[:blacklist_contact].gsub("#\{contact\}") { "#{blacklist_contact}"}
          else
            replace = ""
          end
        else
          replace = variables[placeholder]?.to_s
        end

        if replace
          replace = replace.to_html
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

  # Checks the text and entities for a forwarded message to determine if it 
  # was relayed as a regular message
  #
  # Returns true if the forward message was relayed regularly, nil otherwise
  def is_regular_forward?(text : String?, entities : Array(Tourmaline::MessageEntity)) : Bool?
    return unless text
    if ent = entities.first?
      text.starts_with?("Forwarded from") && ent.type == "bold"
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

  # Strips HTML format from a message and escapes formatting found in `MessageEntities`.
  # If the message has `MessageEntities`, replaces any inline links and removes entities found in `entity_types`.
  def strip_format(text : String, entities : Array(Tourmaline::MessageEntity)) : String
    if !entities.empty?
      text = replace_links(text, entities)
      entities = remove_entities(entities)
    end
    unparse_text(text, entities, Tourmaline::ParseMode::HTML, escape: true)
  end

  # Generate a 8chan or Secretlounge-ng style tripcode from a given string in the format `name#pass`.
  #
  # Returns a named tuple containing the tripname and tripcode.
  def generate_tripcode(tripkey : String) : NamedTuple
    split = tripkey.split('#', 2)
    name = split[0]
    pass = split[1]

    salt = @tripcode_salt
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
  def get_arg(msg : String?) : String | Nil
    unless msg
      return
    end

    msg.split(2)[1]?
  end

  def get_args(msg : String?, count : Int) : Array(String) | Nil
    unless msg
      return
    end

    msg.split(count + 1)[1..]?
  end

  # Returns a link to the given user's account.
  def format_user_sign(id : Int64, name : String) : String
    Link.new("~~#{name}", "tg://user?id=#{id}").to_html
  end

  def format_user_forward(name : String, id : Int64, parsemode : Tourmaline::ParseMode) : String
    tokens = Group.new(Bold.new("Forwarded from "), Bold.new(UserMention.new(name, id)))
    case parsemode
    when Tourmaline::ParseMode::MarkdownV2 then tokens.to_md
    when Tourmaline::ParseMode::HTML then tokens.to_html
    else ""
    end
  end

  def format_private_user_forward(name : String, parsemode : Tourmaline::ParseMode) : String
    tokens = Group.new(Bold.new("Forwarded from "), Bold.new(Italic.new(name)))
    case parsemode
    when Tourmaline::ParseMode::MarkdownV2 then tokens.to_md
    when Tourmaline::ParseMode::HTML then tokens.to_html
    else ""
    end
  end

  # For bots or public channels
  def format_username_forward(name : String, username : String?, parsemode : Tourmaline::ParseMode, msid : Int64? = nil) : String
    tokens = Group.new(
      Bold.new("Forwarded from "), 
      Bold.new(Link.new(name, "tg://resolve?domain=#{username}#{"&post=#{msid}" if msid}"))
    )
    case parsemode
    when Tourmaline::ParseMode::MarkdownV2 then tokens.to_md
    when Tourmaline::ParseMode::HTML then tokens.to_html
    else ""
    end
  end

  # Removes the "-100" prefix for private channels
  def format_private_channel_forward(name : String, id : Int64, msid : Int64?, parsemode : Tourmaline::ParseMode) : String
    tokens = Group.new(
      Bold.new("Forwarded from "), 
      Bold.new(Link.new(name, "tg://privatepost?channel=#{id.to_s[4..]}#{"&post=#{msid}" if msid}"))
    )
    case parsemode
    when Tourmaline::ParseMode::MarkdownV2 then tokens.to_md
    when Tourmaline::ParseMode::HTML then tokens.to_html
    else ""
    end
  end

  # Returns a bolded signature showing which type of user sent this message.
  def format_user_say(signature : String) : String
    Bold.new("~~#{signature}").to_html
  end

  # Returns a tripcode (Name!Tripcode) segment.
  def format_tripcode_sign(name : String, tripcode : String) : String
    Group.new(Bold.new(name), Code.new(tripcode)).to_html
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

  # Returns a smiley based on the number of given warnings
  def format_smiley(warnings : Int32) : String
    if warnings <= 0
      @smileys[0]
    elsif warnings == 1
      @smileys[1]
    elsif warnings <= 3
      @smileys[2]
    else
      @smileys[3]
    end
  end

  # Formats a timestamp according to the locale settings
  def format_time(time : Time?) : String?
    if time
      time.to_s(@time_format)
    end
  end

  # Returns a message containing the program version and a link to its Git repo.
  #
  # Feel free to edit this if you fork the code.
  def version : String
    Group.new("Private Parlor v#{VERSION} ~ ", Link.new("[Source]", "https://github.com/Charibdys/Private-Parlor")).to_html
  end

  # Returns a custom text from a given string.
  def custom(text : String) : String
    Section.new(text).to_html
  end

  # Returns a message containing the commands the user can use.
  def format_help(user : Database::User, ranks : Hash(Int32, Rank)) : String
    ranked_keys = %i(
      promote demote ranksay sign tsign 
      uncooldown purge motd_set 
    )

    reply_required_keys = %i(
      upvote downvote warn delete spoiler
      remove blacklist ranked_info
    )

    help_text = String.build do |str|
      str << substitute_reply(:help_header)
      str << "\n/start - #{@command_descriptions[:start]?}".to_html
      str << "\n/stop - #{@command_descriptions[:stop]?}".to_html
      str << "\n/info - #{@command_descriptions[:info]?}".to_html
      str << "\n/users - #{@command_descriptions[:users]?}".to_html
      str << "\n/version - #{@command_descriptions[:version]?}".to_html
      str << "\n/toggle_karma - #{@command_descriptions[:toggle_karma]?}".to_html
      str << "\n/toggle_debug - #{@command_descriptions[:toggle_debug]?}".to_html
      str << "\n/tripcode - #{@command_descriptions[:tripcode]?}".to_html
      str << "\n/motd - #{@command_descriptions[:motd]?}".to_html
      str << "\n/help - #{@command_descriptions[:help]?}".to_html

      if rank = ranks[user.rank]?
        rank_commands = [] of String
        reply_commands = [] of String

        rank.permissions.each do |permission|
          if ranked_keys.includes?(permission)
            case permission
            when :promote, :demote
              rank_commands << "/#{permission.to_s} [name/OID/ID] [rank] - #{command_descriptions[permission]?}"
            when :sign, :tsign
              rank_commands << "/#{permission.to_s} [text] - #{command_descriptions[permission]?}"
            when :ranksay
              ranks.each do |k, v|
                if k <= user.rank && k != -10 && v.permissions.includes?(:ranksay)
                  rank_commands << "/#{v.name.downcase}say [text] - #{command_descriptions[permission]?}"
                end
              end
            when :uncooldown
              rank_commands << "/#{permission.to_s} [name/OID] - #{command_descriptions[permission]?}"
            when :motd_set
              rank_commands << "/motd [text] - #{command_descriptions[permission]?}"
            else
              rank_commands << "/#{permission.to_s} - #{command_descriptions[permission]?}"
            end
          elsif reply_required_keys.includes?(permission)
            case permission
            when :warn, :delete, :remove, :blacklist
              reply_commands << "/#{permission.to_s} [reason] - #{command_descriptions[permission]?}"
            when :ranked_info
              reply_commands << "/info - #{command_descriptions[permission]?}"
            when :upvote
              reply_commands << "+1 - #{command_descriptions[permission]?}"
            when :downvote
              reply_commands << "-1 - #{command_descriptions[permission]?}"
            else
              reply_commands << "/#{permission.to_s} - #{command_descriptions[permission]?}"
            end
          end
        end

        if !rank_commands.empty?
          str << "\n\n"
          str << substitute_reply(:help_rank_commands, {"rank" => rank.name})
          rank_commands.each {|line| str << "\n#{line}".to_html}
        end
        if !reply_commands.empty?
          str << "\n\n"
          str << substitute_reply(:help_reply_commands)
          reply_commands.each {|line| str << "\n#{line}".to_html}
        end
      end
    end
  end
end
