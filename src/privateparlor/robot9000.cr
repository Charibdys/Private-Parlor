module Robot9000
  extend self

  def ensure_r9k_schema(db : DB::Database, text : Bool?, media : Bool?) : Nil
    if text
      db.exec("
      CREATE TABLE IF NOT EXISTS text (
        line TEXT NOT NULL,
        PRIMARY KEY (line)
      )
      ")
    end
    if media
      db.exec("
      CREATE TABLE IF NOT EXISTS file_id (
        id TEXT NOT NULL,
        PRIMARY KEY (id)
      )
      ")
    end
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      sleep(10.milliseconds)
      ensure_r9k_schema(db, text, media)
    end
  end

  def remove_links(text : String, entities : Array(Tourmaline::MessageEntity)) : String
    entities.reverse.each do |entity|
      if entity.type == "url"
        text = text.delete_at(entity.offset, entity.length)
      end
    end

    text
  end

  def allow_text?(text : String, ranges : Array(Range(Int32, Int32))) : Bool
    return true if text.empty?

    return false if text.codepoints.any? do |codepoint|
                      ranges.none? do |range|
                        range.includes?(codepoint)
                      end
                    end

    true
  end

  def strip_text(text : String, entities : Array(Tourmaline::MessageEntity)) : String
    text = remove_links(text, entities)
    
    text, _ = Tourmaline::HTMLParser.new.parse(text)

    text = text.downcase

    text = text.gsub(/\/\w+\s/, "") # Remove commands

    text = text.gsub(/\s@\w+\s/, " ") # Remove usernames; leave a space

    text = text.gsub(/[[:punct:]]|—/, "") # Remove punctuation and em-dash

    # Reduce repeating characters, excluding digits
    text = text.gsub(/(?![\d])(\w|\w{1,})\1{2,}/) do |_, match|
      match[1]
    end

    # Remove network links
    text = text.gsub(/>>>\/\w+\//, "")

    # Remove repeating spaces and new lines; leave a space
    text = text.gsub(/\s{2,}|\n/, " ")

    # Remove trailing and leading whitespace
    text.strip
  end

  def unoriginal_text?(db : DB::Database, text : String) : Bool?
    db.query_one?("SELECT 1 FROM text WHERE line = ?", text) do
      true
    end
  end

  def add_line(db : DB::Database, text : String) : Nil
    db.exec("INSERT INTO text VALUES (?)", text)
  rescue ex : SQLite3::Exception
    if ex.code == 5 # DB is locked
      sleep(10.milliseconds)
      add_line(db, text)
    end
  end
end
