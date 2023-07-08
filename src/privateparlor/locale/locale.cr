class Locale
  include YAML::Serializable

  @[YAML::Field(key: "time_units")]
  getter time_units : Array(String)

  @[YAML::Field(key: "time_format")]
  getter time_format : String

  @[YAML::Field(key: "toggle")]
  getter toggle : Array(String)

  @[YAML::Field(key: "loading_bar")]
  getter loading_bar : Array(String)

  @[YAML::Field(key: "replies")]
  getter replies : Replies

  @[YAML::Field(key: "logs")]
  getter logs : Logs

  @[YAML::Field(key: "command_descriptions")]
  getter command_descriptions : CommandDescriptions
end
