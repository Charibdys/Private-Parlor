VERSION = "0.4.0"

enum Ranks
  Banned    =  -10
  User      =    0
  Moderator =   10
  Admin     =  100
  Host      = 1000
end

alias MessageProc = Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message))

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
