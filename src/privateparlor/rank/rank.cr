class Rank
  include YAML::Serializable

  getter name : String
  getter permissions : Set(CommandPermissions)

  def initialize(@name, @permissions)
  end
end
