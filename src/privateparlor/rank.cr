class AuthorizedRanks
  getter ranks : Hash(Int32, Rank)

  def initialize(@ranks : Hash(Int32, Rank))
  end

  # Returns `true` if user rank has the given permission; user is authorized.
  #
  # Returns `false` otherwise, or `nil` if the user rank does not exist in `ranks`
  def authorized?(user_rank : Int32, permission : Symbol) : Bool?
    if rank = @ranks[user_rank]?
      rank.permissions.includes?(permission)
    end
  end

  # Returns `true` if user rank has any of the given permissions; user is authorized.
  #
  # Returns `false` otherwise, or `nil` if the user rank does not exist in `ranks`
  def authorized?(user_rank : Int32, *permissions : Symbol) : Symbol?
    if rank = @ranks[user_rank]?
      (rank.permissions & permissions.to_set).first?
    end
  end

  def max_rank : Int32
    @ranks.keys.max
  end

  def rank_name(rank_value : Int32) : String?
    if @ranks[rank_value]?
      @ranks[rank_value].name
    end
  end

  def find_rank(name : String, value : Int32? = nil) : Tuple(Int32, Rank)?
    if value && @ranks[value]
      {value, @ranks[value]}
    else
      @ranks.find do |k, v| 
        v.name.downcase == name || k == value
      end
    end
  end

  def find_ranksay_rank_name(rank : String, user_rank : Int32) : String?
    return unless ranksay_rank = @ranks.find {|k, v|
      (v.name.downcase == rank.downcase && v.permissions.intersects?([:ranksay, :ranksay_lower].to_set)) || 
      (rank == "rank" && k == user_rank)}
    return unless ranksay_rank[0] != -10
    return unless (ranksay_rank[0] < user_rank) && :ranksay_lower.in?(@ranks[user_rank].permissions) ||
      (ranksay_rank[0] == user_rank)

    ranksay_rank[1].name
  end

  def can_promote?(rank : Int32, invoker : Int32, receiver : Int32, permission : Symbol) : Bool
    if rank <= receiver || rank > invoker || rank == -10 || rank < 0
      return false
    end
    
    if rank <= invoker && permission == :promote
      true
    elsif rank < invoker && permission == :promote_lower
      true
    elsif rank == invoker && permission == :promote_same
      true
    else 
      false
    end
  end

  def rank_names : Array(String)
    @ranks.compact_map do |k, v| 
      v.name
    end
  end

  def rank_names(limit : Int32) : Array(String)
    @ranks.compact_map do |k, v| 
      v.name if k < limit
    end
  end

end

class Rank
  include YAML::Serializable

  getter name : String
  getter permissions : Set(Symbol)

  def initialize(@name, @permissions)
  end
end