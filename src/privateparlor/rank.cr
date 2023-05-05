class Rank
    include YAML::Serializable
    
    getter name : String
    getter value : Int32
    getter permissions : Set(Symbol)

    def initialize(@name, @value, @permissions)
    end
end