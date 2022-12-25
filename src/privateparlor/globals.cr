VERSION = "0.5.0"

enum Ranks
  Banned    =  -10
  User      =    0
  Moderator =   10
  Admin     =  100
  Host      = 1000
end

alias MessageProc = Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message))

# Cooldown constants
COOLDOWN_TIME_BEGIN    = [1, 5, 25, 120, 720, 4320] # begins with 1m, 5m, 25m, 2h, 12h, 3d
COOLDOWN_TIME_LINEAR_M =  4320                      # continues 7d, 10d, 13d, 16d, ... (linear)
COOLDOWN_TIME_LINEAR_B = 10080
WARN_EXPIRE_HOURS      = 7 * 24

KARMA_WARN_PENALTY = 10

# Spam limits
SPAM_LIMIT            = 3.0_f32
SPAM_LIMIT_HIT        = 6.0_f32
SPAM_INTERVAL_SECONDS =      10

# Spam score calculation
SCORE_STICKER        =   1.5_f32
SCORE_ALBUM          =   2.5_f32
SCORE_BASE_MESSAGE   =  0.75_f32
SCORE_BASE_FORWARD   =  1.25_f32
SCORE_TEXT_CHARACTER = 0.002_f32
SCORE_TEXT_LINEBREAK =   0.1_f32

{% if flag?(:musl) %}
  module Tourmaline
    module Helpers
      extend self

      # Same as original unparse text function, but io is encoded in UTF-16LE
      def unparse_text(text : String, entities ents : Array(MessageEntity), parse_mode : ParseMode = :markdown, escape : Bool = false)
        if parse_mode == ParseMode::HTML
          return unparse_html(text, ents)
        end

        end_entities = {} of Int32 => Array(MessageEntity)
        start_entities = ents.reduce({} of Int32 => Array(MessageEntity)) do |acc, e|
          acc[e.offset] ||= [] of MessageEntity
          acc[e.offset] << e
          acc
        end

        entity_map = case parse_mode
                     in ParseMode::Markdown
                       MD_ENTITY_MAP
                     in ParseMode::MarkdownV2
                       MDV2_ENTITY_MAP
                     in ParseMode::HTML
                       HTML_ENTITY_MAP
                     end

        text = text.gsub('\u{0}', "") + ' '
        codepoints = text.to_utf16

        io = IO::Memory.new
        io.set_encoding("UTF-16LE")

        codepoints.each_with_index do |codepoint, i|
          if escape && codepoint < 128
            char = codepoint.chr
            case parse_mode
            in ParseMode::HTML
              char = escape_html(char)
            in ParseMode::Markdown
              char = escape_md(char, 1)
            in ParseMode::MarkdownV2
              char = escape_md(char, 2)
            end
          end

          if entities = end_entities[i]?
            entities.each do |entity|
              if pieces = entity_map[entity.type]?
                io << pieces[1]
                  .sub("{language}", entity.language.to_s)
                  .sub("{id}", entity.user.try &.id.to_s)
                  .sub("{url}", entity.url.to_s)
              end
            end

            end_entities.delete(i)
          end

          if entities = start_entities[i]?
            entities.each do |entity|
              if pieces = entity_map[entity.type]?
                io << pieces[0]
                  .sub("{language}", entity.language.to_s)
                  .sub("{id}", entity.user.try &.id.to_s)
                  .sub("{url}", entity.url.to_s)

                end_entities[entity.offset + entity.length] ||= [] of MessageEntity
                end_entities[entity.offset + entity.length] << entity
              end
            end
          end

          if char
            io << char
          else
            io.write_bytes(codepoint, IO::ByteFormat::LittleEndian)
          end
        end

        io.rewind.gets_to_end
      end
    end
  end
{% end %}
