class Rank
  include YAML::Serializable

  getter name : String
  getter permissions : Set(Symbol)

  def initialize(@name, @permissions)
  end
end