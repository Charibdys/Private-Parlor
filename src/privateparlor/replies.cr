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
    elsif text.codepoints.any?{|codepoint| (0x1D400..0x1D7FF).includes?(codepoint)}
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
  def rejoined() : String
    Italic.new("You rejoined the chat!").to_md
  end

  # Returns an italicized message for when a new user joins the chat.
  def joined() : String
    Italic.new("Welcome to the chat!").to_md
  end

  # Returns an italicized message for when the user leaves the chat.
  def left() : String
    Italic.new("You left the chat.").to_md
  end

  # Returns an italicized message for when the user tries to join the chat, but is already in it.
  def already_in_chat() : String
    Italic.new("You're already in the chat.").to_md
  end
  
  # Returns an italicized message for when a user sends a message, but is not in the chat.
  def not_in_chat() : String
    Italic.new("You're not in this chat! Type /start to join.").to_md
  end

  # Returns an italicized message for when a sent message was rejected.
  def rejected_message() : String
    Italic.new("Your message was not relayed because it contained a special font.").to_md
  end

  # Returns an italicized message for when a poll is sent without anonymous voting.
  def deanon_poll() : String
    Italic.new("Your poll was not sent because it does not allow anonymous voting.").to_md
  end

  # Returns an italicized message for when a command is used without an argument.
  def missing_args() : String
    Italic.new("You need to give an input to use this command").to_md
  end

  # Returns an italicized message for when a user is promoted to a given rank.
  def promoted(rank : Ranks) : String
    Italic.new("You have been promoted to #{rank.to_s.downcase()}!").to_md
  end

  # Returns a checkmark for when a command executed successfully.
  def success() : String
    "✅".to_md
  end

  # Returns an italicized message for when the user is blacklisted.
  #
  # Includes the user's `blacklist_text` if one was given.
  def blacklisted(reason : String | Nil) : String
    message = "You've been blacklisted"

    message += reason ? " for: #{reason}" : "."

    message = Italic.new(message)
    message.to_md
  end

end