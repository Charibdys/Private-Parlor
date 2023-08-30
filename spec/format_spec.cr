require "./spec_helper"

describe Format do
  entities = [
    Tourmaline::MessageEntity.new("mention"),
    Tourmaline::MessageEntity.new("text_mention", user: Tourmaline::User.new(
      id: 123456789, bot: false, first_name: "User",
    )),
    Tourmaline::MessageEntity.new("hashtag"),
    Tourmaline::MessageEntity.new("cashtag"),
    Tourmaline::MessageEntity.new("bot_command"),
    Tourmaline::MessageEntity.new("url"),
    Tourmaline::MessageEntity.new("email"),
    Tourmaline::MessageEntity.new("phone_number"),
    Tourmaline::MessageEntity.new("bold"),
    Tourmaline::MessageEntity.new("italic"),
    Tourmaline::MessageEntity.new("code"),
    Tourmaline::MessageEntity.new("pre", language: "ruby"),
    Tourmaline::MessageEntity.new("text_link", url: "http://www.example.com/"),
    Tourmaline::MessageEntity.new("underline"),
    Tourmaline::MessageEntity.new("strikethrough"),
    Tourmaline::MessageEntity.new("spoiler"),
    Tourmaline::MessageEntity.new("custom_emoji", custom_emoji_id: "5368324170671202286"),
  ]

  entities_size = entities.size

  describe "#remove_entities" do 
    it "removes mention" do
      ents_to_strip = ["mention"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("mention")))
    end

    it "removes text_mention" do
      ents_to_strip = ["text_mention"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("text_mention", user: Tourmaline::User.new(
        id: 123456789, bot: false, first_name: "User"
      ))))
    end

    it "removes hashtag" do
      ents_to_strip = ["hashtag"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("hashtag")))
    end

    it "removes cashtag" do
      ents_to_strip = ["cashtag"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("cashtag")))
    end

    it "removes bot_command" do
      ents_to_strip = ["bot_command"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("bot_command")))
    end

    it "removes url" do
      ents_to_strip = ["url"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("url")))
    end

    it "removes email" do
      ents_to_strip = ["email"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("email")))
    end

    it "removes phone_number" do
      ents_to_strip = ["phone_number"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("phone_number")))
    end

    it "removes bold" do
      ents_to_strip = ["bold"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("bold")))
    end

    it "removes italic" do
      ents_to_strip = ["italic"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("italic")))
    end

    it "removes code" do
      ents_to_strip = ["code"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("code")))
    end

    it "removes pre" do
      ents_to_strip = ["pre"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("pre", language: "ruby")))
    end

    it "removes text_link" do
      ents_to_strip = ["text_link"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("text_link", url: "http://www.example.com/")))
    end

    it "removes underline" do
      ents_to_strip = ["underline"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("underline")))
    end

    it "removes strikethrough" do
      ents_to_strip = ["strikethrough"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("strikethrough")))
    end

    it "removes spoiler" do
      ents_to_strip = ["spoiler"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("spoiler")))
    end

    it "removes custom_emoji" do
      ents_to_strip = ["custom_emoji"]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(entities_size - 1))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("custom_emoji", custom_emoji_id: "5368324170671202286")))
    end

    it "removes all entities types" do
      ents_to_strip = [
        "mention", "text_mention", "hashtag", "cashtag", "bot_command", "url", "email", "phone_number",
        "bold", "italic", "code", "pre", "text_link", "underline", "strikethrough", "spoiler", "custom_emoji",
      ]

      new_ents = Format.remove_entities(entities, ents_to_strip)

      new_ents.size.should(eq(0))
      new_ents.should_not(contain(entities))
    end

    it "removes all entities of same type" do
      ents_with_same_types = entities

      ents_with_same_types << Tourmaline::MessageEntity.new("bold", offset: 1, length: 1)
      ents_with_same_types << Tourmaline::MessageEntity.new("bold", offset: 3, length: 1)

      ents_with_same_types_size = ents_with_same_types.size

      ents_to_strip = ["bold"]

      new_ents = Format.remove_entities(ents_with_same_types, ents_to_strip)

      new_ents.size.should(eq(ents_with_same_types_size - 3))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("bold")))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("bold", offset: 1, length: 1)))
      new_ents.should_not(contain(Tourmaline::MessageEntity.new("bold", offset: 3, length: 1)))
    end
  end

end