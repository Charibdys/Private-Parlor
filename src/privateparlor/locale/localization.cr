module Localization
  extend self

  def parse_locale(language_code : String) : Locale
    Locale.from_yaml(File.open("./locales/#{language_code}.yaml"))
  rescue ex : YAML::ParseException
    Log.error(exception: ex) { "Could not parse the given value at row #{ex.line_number}. This could be because a required value was not set or the wrong type was given." }
    exit
  rescue ex : File::NotFoundError | File::AccessDeniedError
    Log.error(exception: ex) { "Could not open \"./locales/#{language_code}.yaml\". Exiting..." }
    exit
  end
end
