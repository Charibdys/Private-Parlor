class AuthorizedRanks
  getter ranks : Hash(Int32, Rank)

  def initialize(@ranks : Hash(Int32, Rank))
  end

  # Returns `true` if user rank has the given permission; user is authorized.
  #
  # Returns `false` otherwise, or `nil` if the user rank does not exist in `ranks`
  def authorized?(user_rank : Int32, permission : CommandPermissions) : Bool?
    if rank = @ranks[user_rank]?
      rank.permissions.includes?(permission)
    end
  end

  # Returns the first symbol found from intersecting the user permissions and the given permissions; user is authorized.
  #
  # Returns`nil` if the user rank does not exist in `ranks` or if the rank does not have any of the given permissions.
  #
  # Used for checking groups of permissions that are similar.
  def authorized?(user_rank : Int32, *permissions : CommandPermissions) : CommandPermissions?
    if rank = @ranks[user_rank]?
      (rank.permissions & permissions.to_set).first?
    end
  end

  # Returns the max rank value in the ranks hash
  def max_rank : Int32
    @ranks.keys.max
  end

  # Returns the rank name associated with the given value.
  def rank_name(rank_value : Int32) : String?
    if @ranks[rank_value]?
      @ranks[rank_value].name
    end
  end

  # Finds a rank from a given rank value
  # or iterates through the ranks hash for a rank with a given name
  #
  # Returns a 2-tuple with the rank value and the rank associated with that rank,
  # or `nil` if no rank exists with the given values.
  def find_rank(name : String, value : Int32? = nil) : Tuple(Int32, Rank)?
    if value && @ranks[value]
      {value, @ranks[value]}
    else
      @ranks.find do |k, v|
        v.name.downcase == name || k == value
      end
    end
  end

  # Returns true if the user to be promoted (receiver) can be promoted with the given rank.
  def can_promote?(rank : Int32, invoker : Int32, receiver : Int32, permission : CommandPermissions) : Bool
    if rank <= receiver || rank > invoker || rank == -10
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

  # Returns `true` if the user to be demoted (receiver) can be demoted with the given rank.
  def can_demote?(rank : Int32, invoker : Int32, receiver : Int32) : Bool
    rank < receiver && rank < invoker && rank != -10
  end

  # Returns `true` if the user can sign a message with the given rank.
  def can_ranksay?(rank : Int32, invoker : Int32, permission : CommandPermissions) : Bool
    rank != -10 && (rank < invoker && permission == :ranksay_lower) || rank == invoker
  end

  # Returns an array of all the rank names in the ranks hash.
  def rank_names : Array(String)
    @ranks.compact_map do |_, v|
      v.name
    end
  end

  # Returns an array of all the rank names in the ranks hash, up to a rank value limit.
  def rank_names(limit : Int32) : Array(String)
    @ranks.compact_map do |k, v|
      v.name if k < limit
    end
  end
end
