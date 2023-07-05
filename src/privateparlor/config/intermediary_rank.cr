class IntermediaryRank
  include YAML::Serializable

  @[YAML::Field(key: "name")]
  getter name : String

  @[YAML::Field(key: "value")]
  getter value : Int32

  @[YAML::Field(key: "permissions")]
  property permissions : Array(String)
end
