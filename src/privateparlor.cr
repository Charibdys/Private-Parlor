require "tourmaline"
require "yaml"
require "sqlite3"
require "./privateparlor/*"

CONFIG = File.open(File.expand_path("config.yaml")) do |file|
  YAML.parse(file)
end

TOKEN = CONFIG["api-token"].to_s
DB_PATH = Path.new(CONFIG["database"].to_s) # TODO: We'll want check if this works on Windows later

db = DB.open("sqlite3://#{DB_PATH}")

bot = PrivateParlor.new(bot_token: TOKEN, config: CONFIG, connection: db)
bot.poll