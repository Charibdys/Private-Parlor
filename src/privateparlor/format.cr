require "digest"

module Format
  extend self
  include Tourmaline::Helpers

  @[Link("crypt")]
  lib LibCrypt
    fun crypt(password : UInt8*, salt : UInt8*) : UInt8*
  end

  # Globally substitutes placeholders in message with the given variables
  def substitute_message(msg : String, locale : Locale, variables : Hash(String, String?) = {"" => ""}) : String
    msg.gsub(/{\w+}/) do |match|
      escape_html(variables[match[1..-2]])
    end
  end

  def format_cooldown_until(expiration : Time?, locale : Locale) : String
    if time = format_time(expiration, locale.time_format)
      "#{locale.replies.cooldown_true} #{time}"
    else
      locale.replies.cooldown_false
    end
  end

  def format_warn_expiry(expiration : Time?, locale : Locale) : String?
    if time = format_time(expiration, locale.time_format)
      locale.replies.info_warning.gsub("{warn_expiry}", "#{time}")
    end
  end

  def format_reason_reply(reason : String?, locale : Locale) : String?
    if reason
      "#{locale.replies.reason_prefix}#{reason}"
    end
  end

  def format_tripcode_reply(tripcode : String?, locale : Locale) : String
    if tripcode
      tripcode
    else
      locale.replies.tripcode_unset
    end
  end

  def format_contact_reply(contact : String?, locale : Locale) : String?
    if contact
      locale.replies.blacklist_contact.gsub("{contact}", "#{escape_html(contact)}")
    end
  end

  def format_reason_log(reason : String?, locale : Locale) : String?
    if reason
      "#{locale.logs.reason_prefix}#{reason}"
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

  # Embeds any occurence of a >>>/chat/ link with a link to that chat.
  def replace_network_links(text : String, linked_network : Hash(String, String)) : String
    text.gsub(/>>>\/\w+\//) do |match|
      chat = match.strip(">>>//")

      if linked_network[chat]?
        "<a href=\"tg://resolve?domain=#{linked_network[chat]}\">#{match}</a>"
      else
        match
      end
    end
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
  def regular_forward?(text : String?, entities : Array(Tourmaline::MessageEntity)) : Bool?
    return unless text
    if ent = entities.first?
      text.starts_with?("Forwarded from") && ent.type == "bold"
    end
  end

  # Strips message entities if they're found in `entity_types`
  def remove_entities(entities : Array(Tourmaline::MessageEntity), entity_types : Array(String)) : Array(Tourmaline::MessageEntity)
    stripped_entities = [] of Tourmaline::MessageEntity

    entities.each do |entity|
      if entity_types.includes?(entity.type)
        stripped_entities << entity
      end
    end

    entities - stripped_entities
  end

  # Strips HTML format from a message and escapes formatting found in `MessageEntities`.
  # If the message has `MessageEntities`, replaces any inline links and removes entities found in `entity_types`.
  def strip_format(text : String, entities : Array(Tourmaline::MessageEntity), entity_types : Array(String), linked_network : Hash(String, String)) : String
    parser = Tourmaline::HTMLParser.new

    text, parsed_ents = parser.parse(text)
    entities = entities | parsed_ents

    text = replace_links(text, entities)
    entities = remove_entities(entities, entity_types)

    text = parser.unparse(text, entities)
    replace_network_links(text, linked_network)
  end

  # Generate a 8chan or Secretlounge-ng style tripcode from a given string in the format `name#pass`.
  #
  # Returns a named tuple containing the tripname and tripcode.
  def generate_tripcode(tripkey : String, salt : String?) : Tuple(String, String)
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

    {name, tripcode}
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
    "<a href=\"tg://user?id=#{id}\"> ~~#{escape_html(name)}</a>"
  end

  def get_forward_header(message : Tourmaline::Message) : String?
    if from = message.forward_from
      if from.bot?
        Format.format_username_forward(from.full_name, from.username)
      elsif from.id
        Format.format_user_forward(from.full_name, from.id)
      end
    elsif (from = message.forward_from_chat) && message.forward_from_message_id
      if from.username
        Format.format_username_forward(from.name, from.username, message.forward_from_message_id)
      else
        Format.format_private_channel_forward(from.name, from.id, message.forward_from_message_id)
      end
    elsif from = message.forward_sender_name
      Format.format_private_user_forward(from)
    end
  end

  # Returns a link to a given user's account, for reveal messages
  def format_user_reveal(id : Int64, name : String, locale : Locale) : String
    locale.replies.username_reveal.gsub("{username}", "<a href=\"tg://user?id=#{id}\">#{escape_html(name)}</a>")
  end

  def format_user_forward(name : String, id : Int64) : String
    "<b>Forwarded from <a href=\"tg://user?id=#{id}\">#{escape_html(name)}</a></b>"
  end

  def format_private_user_forward(name : String) : String
    "<b>Forwarded from <i>#{escape_html(name)}</i></b>"
  end

  # For bots or public channels
  def format_username_forward(name : String, username : String?, msid : Int64? = nil) : String
    "<b>Forwarded from <a href=\"tg://resolve?domain=#{escape_html(username)}#{"&post=#{msid}" if msid}\">#{escape_html(name)}</a></b>"
  end

  # Removes the "-100" prefix for private channels
  def format_private_channel_forward(name : String, id : Int64, msid : Int64?) : String
    "<b>Forwarded from <a href=\"tg://privatepost?channel=#{id.to_s[4..]}#{"&post=#{msid}" if msid}\">#{escape_html(name)}</a></b>"
  end

  # Returns a bolded signature showing which type of user sent this message.
  def format_user_say(signature : String) : String
    "<b> ~~#{escape_html(signature)}</b>"
  end

  # Returns a bolded signature (as terveisin) showing the karma level of the user that sent this message.
  def format_karma_say(signature : String) : String
    "<b><i> t. #{escape_html(signature)}</i></b>"
  end

  def format_tripcode_sign(name : String, tripcode : String) : String
    "<b>#{escape_html(name)}</b><code>#{escape_html(tripcode)}</code>"
  end

  def format_pseudonymous_message(text : String?, tripkey : String, salt : String) : String
    name, tripcode = generate_tripcode(tripkey, salt)
    String.build do |str|
      str << format_tripcode_sign(name, tripcode) << ":"
      str << "\n"
      str << text
    end
  end

  # Formats a timespan, so the duration is marked by its largest unit ("20m", "3h", "5d", etc)
  def format_timespan(cmp : Time::Span, time_units : Array(String)) : String
    case
    when cmp >= Time::Span.new(days: 7)
      "#{cmp.total_weeks.floor.to_i}#{time_units[0]}"
    when cmp >= Time::Span.new(days: 1)
      "#{cmp.total_days.floor.to_i}#{time_units[1]}"
    when cmp >= Time::Span.new(hours: 1)
      "#{cmp.total_hours.floor.to_i}#{time_units[2]}"
    when cmp >= Time::Span.new(minutes: 1)
      "#{cmp.total_minutes.floor.to_i}#{time_units[3]}"
    else
      "#{cmp.to_i}#{time_units[4]}"
    end
  end

  # Returns a smiley based on the number of given warnings
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

  # Formats a timestamp according to the locale settings
  def format_time(time : Time?, format : String) : String?
    if time
      time.to_s(format)
    end
  end

  # Formats a loading bar for the /karmainfo command
  def format_karma_loading_bar(percentage : Float32, locale : Locale) : String
    pips = (percentage.floor.to_i).divmod(10)

    if pips[0] != 10
      String.build(10) do |str|
        str << locale.loading_bar[2] * pips[0]

        if pips[1] >= 5
          str << locale.loading_bar[1]
        else
          str << locale.loading_bar[0]
        end

        str << locale.loading_bar[0] * (10 - (pips[0] + 1))
      end
    else
      locale.loading_bar[2] * 10
    end
  end

  # Parses new MOTD for HTML formatting and returns the MOTD in
  # HTML without the command and whitespace that follows it
  #
  # Returns an empty string if no whitespace or command argument could be found.
  def format_motd(text : String, entities : Array(Tourmaline::MessageEntity), linked_network : Hash(String, String)) : String
    parser = Tourmaline::HTMLParser.new

    text, parsed_ents = parser.parse(text)
    entities = entities | parsed_ents

    whitespace_start = text.index(/\s+/)
    whitespace_end = text.index(/\s\w/)

    text = Format.get_arg(text)

    unless whitespace_start && whitespace_end && text
      return ""
    end

    offset = 1 + entities[0].length + whitespace_end - whitespace_start

    text = parser.unparse(text, entities, offset)
    replace_network_links(text, linked_network)
  end

  # Returns a message containing the program version and a link to its Git repo.
  #
  # Feel free to edit this if you fork the code.
  def format_version : String
    "Private Parlor v#{VERSION} ~ <a href=\"https://github.com/Charibdys/Private-Parlor\">[Source]</a>"
  end

  # Returns a message containing the commands the user can use.
  def format_help(user : Database::User, ranks : Hash(Int32, Rank), locale : Locale) : String
    ranked = {
      CommandPermissions::Promote      => "/promote [name/OID/ID] [rank] - #{locale.command_descriptions.promote}",
      CommandPermissions::PromoteSame  => "/promote [name/OID/ID] [rank] - #{locale.command_descriptions.promote}",
      CommandPermissions::PromoteLower => "/promote [name/OID/ID] [rank] - #{locale.command_descriptions.promote}",
      CommandPermissions::Demote       => "/demote [name/OID/ID] [rank] - #{locale.command_descriptions.demote}",
      CommandPermissions::Ranksay      => "/#{ranks[user.rank].name.downcase}say [text] - #{locale.command_descriptions.ranksay}",
      CommandPermissions::Sign         => "/sign [text] - #{locale.command_descriptions.sign}",
      CommandPermissions::TSign        => "/tsign [text] - #{locale.command_descriptions.tsign}",
      CommandPermissions::Uncooldown   => "/uncooldown [name/OID] - #{locale.command_descriptions.uncooldown}",
      CommandPermissions::Whitelist    => "/whitelist [ID] - #{locale.command_descriptions.whitelist}",
      CommandPermissions::Purge        => "/purge - #{locale.command_descriptions.purge}",
      CommandPermissions::MotdSet      => "/motd - #{locale.command_descriptions.motd_set}",
    }

    reply_required = {
      CommandPermissions::Upvote     => "+1 - #{locale.command_descriptions.upvote}",
      CommandPermissions::Downvote   => "-1 - #{locale.command_descriptions.downvote}",
      CommandPermissions::Warn       => "/warn [reason] - #{locale.command_descriptions.warn}",
      CommandPermissions::Delete     => "/delete [reason] - #{locale.command_descriptions.delete}",
      CommandPermissions::Spoiler    => "/spoiler - #{locale.command_descriptions.spoiler}",
      CommandPermissions::Remove     => "/remove [reason] - #{locale.command_descriptions.remove}",
      CommandPermissions::Blacklist  => "/blacklist [reason] - #{locale.command_descriptions.blacklist}",
      CommandPermissions::RankedInfo => "/info - #{locale.command_descriptions.ranked_info}",
      CommandPermissions::Reveal     => "/reveal - #{locale.command_descriptions.reveal}",
      CommandPermissions::Pin        => "/pin - #{locale.command_descriptions.pin}",
      CommandPermissions::Unpin      => "/unpin - #{locale.command_descriptions.unpin}",
    }

    String.build do |str|
      str << substitute_message(locale.replies.help_header, locale)
      str << escape_html("\n/start - #{locale.command_descriptions.start}")
      str << escape_html("\n/stop - #{locale.command_descriptions.stop}")
      str << escape_html("\n/info - #{locale.command_descriptions.info}")
      str << escape_html("\n/users - #{locale.command_descriptions.users}")
      str << escape_html("\n/version - #{locale.command_descriptions.version}")
      str << escape_html("\n/toggle_karma - #{locale.command_descriptions.toggle_karma}")
      str << escape_html("\n/toggle_debug - #{locale.command_descriptions.toggle_debug}")
      str << escape_html("\n/tripcode - #{locale.command_descriptions.tripcode}")
      str << escape_html("\n/motd - #{locale.command_descriptions.motd}")
      str << escape_html("\n/help - #{locale.command_descriptions.help}")

      rank_commands = [] of String
      reply_commands = [] of String

      if rank = ranks[user.rank]?
        if rank.permissions.includes?(:ranksay_lower)
          ranks.each do |k, v|
            if k <= user.rank && k != -10 && v.permissions.includes?(:ranksay)
              rank_commands << escape_html("/#{v.name.downcase}say [text] - #{locale.command_descriptions.ranksay}")
            end
          end
        end

        rank.permissions.each do |permission|
          if ranked.keys.includes?(permission)
            rank_commands << escape_html(ranked[permission])
          elsif reply_required.keys.includes?(permission)
            reply_commands << escape_html(reply_required[permission])
          end
        end

        unless rank_commands.empty?
          str << "\n\n"
          str << substitute_message(locale.replies.help_rank_commands, locale, {"rank" => rank.name})
          rank_commands.each { |line| str << escape_html("\n#{line}") }
        end
        unless reply_commands.empty?
          str << "\n\n"
          str << substitute_message(locale.replies.help_reply_commands, locale)
          reply_commands.each { |line| str << escape_html("\n#{line}") }
        end
      end
    end
  end
end
