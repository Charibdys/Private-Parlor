class Replies
  include Tourmaline::Format
  include Tourmaline::Helpers

  getter entity_types : Array(String)

  # Creates an instance of `Replies`.
  #
  # ## Arguments:
  #
  # `entities`
  # :     an array of strings refering to one or more of the possible message entity types
  def initialize(entities : Array(String))
    @entity_types = entities
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
      return true
    elsif text.codepoints.any? { |codepoint| (0x1D400..0x1D7FF).includes?(codepoint) }
      return false
    else
      return true
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

    entities = entities - stripped_entities
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

  ###################
  # SYSTEM MESSAGES #
  ###################

  # Returns an italicized message for when the user rejoins the chat.
  def rejoined : String
    Italic.new("You rejoined the chat!").to_md
  end

  # Returns an italicized message for when a new user joins the chat.
  def joined : String
    Italic.new("Welcome to the chat!").to_md
  end

  # Returns an italicized message for when the user leaves the chat.
  def left : String
    Italic.new("You left the chat.").to_md
  end

  # Returns an italicized message for when the user tries to join the chat, but is already in it.
  def already_in_chat : String
    Italic.new("You're already in the chat.").to_md
  end

  # Returns an italicized message for when a user sends a message, but is not in the chat.
  def not_in_chat : String
    Italic.new("You're not in this chat! Type /start to join.").to_md
  end

  # Returns an italicized message for when a sent message was rejected.
  def rejected_message : String
    Italic.new("Your message was not relayed because it contained a special font.").to_md
  end

  # Returns an italicized message for when a poll is sent without anonymous voting.
  def deanon_poll : String
    Italic.new("Your poll was not sent because it does not allow anonymous voting.").to_md
  end

  # Returns an italicized message for when a command is used without an argument.
  def missing_args : String
    Italic.new("You need to give an input to use this command").to_md
  end

  # Returns an italicized message for when a command is disabled
  def command_disabled : String
    Italic.new("This command is disabled.").to_md
  end

  # Returns an italicized message for when a command is used without a reply.
  def no_reply : String
    Italic.new("You need to reply to a message to use this command").to_md
  end

  # Returns an italicized message for when a message could not be found in the message history.
  def not_in_cache : String
    Italic.new("That message could not be found in the cache.").to_md
  end

  # Returns an italicized command for when there is no tripcode set.
  def no_tripcode_set : String
    Italic.new("You do not have a tripcode set. Use the /tripcode command to set one.").to_md
  end

  # Returns an italicized message for when a user could not be found when searching by name.
  def no_user_found : String
    Italic.new("There was no user found with that name.").to_md
  end

  # Returns an italicized message for when a user is promoted to a given rank.
  def promoted(rank : Ranks) : String
    Italic.new("You have been promoted to #{rank.to_s.downcase}!").to_md
  end

  # Returns a link to the given user's account.
  def format_user_sign(id : Int64, name : String) : String
    return Link.new("~~#{name}", "tg://user?id=#{id}").to_md
  end

  # Returns a tripcode (Name!Tripcode) segment.
  def format_tripcode_sign(name : String, tripcode : String) : String
    Group.new(Bold.new(name), Code.new(tripcode)).to_md
  end

  # Returns a message for when a user disables or enables karma notifications.
  def toggle_karma(hide_karma : Bool) : String
    Group.new(Bold.new("Karma notifications"), ": #{hide_karma ? "disabled" : "enabled"}").to_md
  end

  # Returns an italicized message for when a user upvotes a message.
  def gave_upvote : String
    Italic.new("You upvoted this message!").to_md
  end

  # Returns an italicized message for when a user was upvoted.
  def got_upvote : String
    Italic.new("You've just been upvoted! (check /info to see your karma or /toggleKarma to turn these notifications off)").to_md
  end

  # Returns an italicized message for when a user tries to upvote their own message.
  def upvoted_own_message : String
    Italic.new("You can't upvote your own message!").to_md
  end

  # Returns an italicized message for when a user tries to upvote a message they already upvoted.
  def already_upvoted : String
    Italic.new("You have already upvoted this message.").to_md
  end

  # Return a message for when the proposed tripcode is not in the correct format.
  def invalid_tripcode_format : String
    return Section.new(
      Group.new(Italic.new("Invalid tripcode format. The format is:")),
      Group.new(Code.new("name#pass")),
      indent: 0).to_md
  end

  # Return a message containing the user's new tripcode.
  def tripcode_set(name : String, tripcode : String) : String
    return Section.new(
      Group.new(Italic.new("Tripcode set. It will appear as:")),
      Group.new(Bold.new(name), Code.new(tripcode)),
      indent: 0).to_md
  end

  # Return a message containing the user's tripcode name and password.
  def tripcode_info(tripcode : String | Nil) : String
    message = Group.new(Bold.new("Tripcode"), ": ")
    if tripcode
      message << Code.new(tripcode)
    else
      message << "unset"
    end

    return message.to_md
  end

  def user_info(oid : String, username : String, rank : Ranks, karma : Int32, warnings : Int32, warn_expiry : Time | Nil = nil, cooldown_until : Time | Nil = nil) : String
    return Section.new(
      Group.new(Bold.new("id"), ": #{oid}, ", Bold.new("username"), ": #{username}, ", Bold.new("rank"), ": #{rank.value} (#{rank.to_s})"),
      Group.new(Bold.new("karma"), ": #{karma}"),
      Group.new(Bold.new("warnings"), ": #{warnings}#{warn_expiry ? " (one warning will be removed on #{warn_expiry}), " : ", "}",
        Bold.new("cooldown"), ": #{cooldown_until ? "yes, until #{cooldown_until}" : "no"}"),
      indent: 0).to_md
  end

  def user_info_mod(oid : String, karma : Int32, cooldown_until : Time | Nil = nil)
    return Section.new(
      Group.new(Bold.new("id"), ": #{oid}, ", Bold.new("username"), ": anonymous, ", Bold.new("rank"), ": n/a"),
      Group.new(Bold.new("karma"), ": #{karma}"),
      Group.new(Bold.new("cooldown"), ": #{cooldown_until ? "yes, until #{cooldown_until}" : "no"}"),
      indent: 0).to_md
  end

  # Returns an italicized message for when a message is deleted or removed.
  def message_deleted(deleted : Bool, reason : String | Nil = nil) : String
    Italic.new("This message has been #{deleted ? "deleted#{reason ? " for: #{reason}." : "."} You are on cooldown for some amount of time" : "removed#{reason ? " for: #{reason}." : "."} No cooldown has been given, but please refrain from posting the same message again."}").to_md
  end

  # Returns an italicized message for when the user is blacklisted.
  #
  # Includes the user's `blacklist_text` if one was given.
  def blacklisted(reason : String | Nil = nil) : String
    Italic.new("You have been blacklisted#{reason ? " for: #{reason}" : "."}").to_md
  end

  # Returns an italicized message and the number of messages deleted after a purge command was successful.
  def purge_complete(msgs_deleted : Int32) : String
    Italic.new("#{msgs_deleted} messages were matched and deleted.").to_md
  end

  # Returns a custom text from a given string.
  def custom(text : String) : String
    message = Section.new
    message << text
    return message.to_md
  end

  # Returns a checkmark for when a command executed successfully.
  def success : String
    "✅".to_md
  end
end
