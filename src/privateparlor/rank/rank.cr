class Rank
  include YAML::Serializable

  getter name : String
  getter command_permissions : Set(CommandPermissions)
  getter message_permissions : Set(MessagePermissions)

  def initialize(@name, @command_permissions, @message_permissions)
  end
end
