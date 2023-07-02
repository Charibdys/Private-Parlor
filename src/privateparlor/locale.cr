class Locale
  include YAML::Serializable

  @[YAML::Field(key: "time_units")]
  getter time_units : Array(String)

  @[YAML::Field(key: "time_format")]
  getter time_format : String

  @[YAML::Field(key: "toggle")]
  getter toggle : Array(String)

  @[YAML::Field(key: "replies")]
  getter replies : Replies

  @[YAML::Field(key: "logs")]
  getter logs : Logs

  @[YAML::Field(key: "command_descriptions")]
  getter command_descriptions : CommandDescriptions
end

module Localization
  extend self

  def parse_locale(language_code : String) : Locale
    locale = Locale.from_yaml(File.open("./locales/#{language_code}.yaml"))
  rescue ex : YAML::ParseException
    Log.error(exception: ex) { "Could not parse the given value at row #{ex.line_number}. This could be because a required value was not set or the wrong type was given." }
    exit
  rescue ex : File::NotFoundError | File::AccessDeniedError
    Log.error(exception: ex) { "Could not open \"./locales/#{language_code}.yaml\". Exiting..." }
    exit
  end
end

class Replies
  include YAML::Serializable

  @[YAML::Field(key: "joined")]
  getter joined : String 

  @[YAML::Field(key: "rejoined")]
  getter rejoined : String 

  @[YAML::Field(key: "left")]
  getter left : String
 
	@[YAML::Field(key: "already_in_chat")]
	getter already_in_chat : String

	@[YAML::Field(key: "registration_closed")]
	getter registration_closed : String

	@[YAML::Field(key: "not_in_chat")]
	getter not_in_chat : String
 
	@[YAML::Field(key: "not_in_cooldown")]
	getter not_in_cooldown : String

	@[YAML::Field(key: "rejected_message")]
	getter rejected_message : String

	@[YAML::Field(key: "deanon_poll")]
	getter deanon_poll : String
    
	@[YAML::Field(key: "missing_args")]
	getter missing_args : String
 
	@[YAML::Field(key: "command_disabled")]
	getter command_disabled : String

	@[YAML::Field(key: "media_disabled")]
	getter media_disabled : String

	@[YAML::Field(key: "no_reply")]
	getter no_reply : String

	@[YAML::Field(key: "not_in_cache")]
	getter not_in_cache : String

	@[YAML::Field(key: "no_tripcode_set")]
	getter no_tripcode_set : String

	@[YAML::Field(key: "no_user_found")]
	getter no_user_found : String

	@[YAML::Field(key: "no_user_oid_found")]
	getter no_user_oid_found : String
    
	@[YAML::Field(key: "no_rank_found")]
	getter no_rank_found : String

	@[YAML::Field(key: "promoted")]
	getter promoted : String

	@[YAML::Field(key: "help_header")]
	getter help_header : String

	@[YAML::Field(key: "help_rank_commands")]
	getter help_rank_commands : String
 
	@[YAML::Field(key: "help_reply_commands")]
	getter help_reply_commands : String

	@[YAML::Field(key: "toggle_karma")]
	getter toggle_karma : String
 
	@[YAML::Field(key: "toggle_debug")]
	getter toggle_debug : String
 
	@[YAML::Field(key: "gave_upvote")]
	getter gave_upvote : String
 
	@[YAML::Field(key: "got_upvote")]
	getter got_upvote : String
 
	@[YAML::Field(key: "upvoted_own_message")]
	getter upvoted_own_message : String
 
	@[YAML::Field(key: "already_voted")]
	getter already_voted : String
    
	@[YAML::Field(key: "gave_downvote")]
	getter gave_downvote : String
 
	@[YAML::Field(key: "got_downvote")]
	getter got_downvote : String
 
	@[YAML::Field(key: "downvoted_own_message")]
	getter downvoted_own_message : String

	@[YAML::Field(key: "already_warned")]
	getter already_warned : String
 
	@[YAML::Field(key: "private_sign")]
	getter private_sign : String

	@[YAML::Field(key: "spamming")]
	getter spamming : String

	@[YAML::Field(key: "sign_spam")]
	getter sign_spam : String
    
	@[YAML::Field(key: "upvote_spam")]
	getter upvote_spam : String

	@[YAML::Field(key: "downvote_spam")]
	getter downvote_spam : String

	@[YAML::Field(key: "invalid_tripcode_format")]
	getter invalid_tripcode_format : String
 
	@[YAML::Field(key: "tripcode_set")]
	getter tripcode_set : String
 
	@[YAML::Field(key: "tripcode_info")]
	getter tripcode_info : String

	@[YAML::Field(key: "tripcode_unset")]
	getter tripcode_unset : String
    
	@[YAML::Field(key: "user_info")]
	getter user_info : String

	@[YAML::Field(key: "info_warning")]
	getter info_warning : String

	@[YAML::Field(key: "ranked_info")]
	getter ranked_info : String

	@[YAML::Field(key: "cooldown_true")]
	getter cooldown_true : String
 
	@[YAML::Field(key: "cooldown_false")]
	getter cooldown_false : String

	@[YAML::Field(key: "user_count")]
	getter user_count : String

	@[YAML::Field(key: "user_count_full")]
	getter user_count_full : String
    
	@[YAML::Field(key: "message_deleted")]
	getter message_deleted : String

	@[YAML::Field(key: "message_removed")]
	getter message_removed : String
 
	@[YAML::Field(key: "reason_prefix")]
	getter reason_prefix : String

	@[YAML::Field(key: "cooldown_given")]
	getter cooldown_given : String

	@[YAML::Field(key: "on_cooldown")]
	getter on_cooldown : String

	@[YAML::Field(key: "media_limit")]
	getter media_limit : String
 
	@[YAML::Field(key: "blacklisted")]
	getter blacklisted : String

	@[YAML::Field(key: "blacklist_contact")]
	getter blacklist_contact : String
 
	@[YAML::Field(key: "purge_complete")]
	getter purge_complete : String

	@[YAML::Field(key: "inactive")]
	getter inactive : String

	@[YAML::Field(key: "success")]
	getter success : String

	@[YAML::Field(key: "fail")]
	getter fail : String
end

class CommandDescriptions
  include YAML::Serializable
    
	@[YAML::Field(key: "start")]
	getter start : String
 
	@[YAML::Field(key: "stop")]
	getter stop : String
 
	@[YAML::Field(key: "info")]
	getter info : String
 
	@[YAML::Field(key: "users")]
	getter users : String
 
	@[YAML::Field(key: "version")]
	getter version : String
 
	@[YAML::Field(key: "upvote")]
	getter upvote : String
 
	@[YAML::Field(key: "downvote")]
	getter downvote : String
 
	@[YAML::Field(key: "toggle_karma")]
	getter toggle_karma : String
 
	@[YAML::Field(key: "toggle_debug")]
	getter toggle_debug : String
 
	@[YAML::Field(key: "tripcode")]
	getter tripcode : String
 
	@[YAML::Field(key: "promote")]
	getter promote : String
 
	@[YAML::Field(key: "demote")]
	getter demote : String

	@[YAML::Field(key: "sign")]
	getter sign : String
 
	@[YAML::Field(key: "tsign")]
	getter tsign : String
 
	@[YAML::Field(key: "ranksay")]
	getter ranksay : String
 
	@[YAML::Field(key: "warn")]
	getter warn : String
 
	@[YAML::Field(key: "delete")]
	getter delete : String
 
	@[YAML::Field(key: "uncooldown")]
	getter uncooldown : String
 
	@[YAML::Field(key: "remove")]
	getter remove : String
 
	@[YAML::Field(key: "purge")]
	getter purge : String
 
	@[YAML::Field(key: "spoiler")]
	getter spoiler : String
 
	@[YAML::Field(key: "blacklist")]
	getter blacklist : String
 
	@[YAML::Field(key: "motd")]
	getter motd : String
 
	@[YAML::Field(key: "help")]
	getter help : String
 
	@[YAML::Field(key: "motd_set")]
	getter motd_set : String
 
	@[YAML::Field(key: "ranked_info")]
	getter ranked_info : String
end 

class Logs
  include YAML::Serializable

	@[YAML::Field(key: "start")]
	getter start : String

	@[YAML::Field(key: "joined")]
	getter joined : String

	@[YAML::Field(key: "rejoined")]
	getter rejoined : String

	@[YAML::Field(key: "left")]
	getter left : String

	@[YAML::Field(key: "promoted")]
	getter promoted : String

	@[YAML::Field(key: "demoted")]
	getter demoted : String

	@[YAML::Field(key: "warned")]
	getter warned : String

	@[YAML::Field(key: "message_deleted")]
	getter message_deleted : String

	@[YAML::Field(key: "message_removed")]
	getter message_removed : String

	@[YAML::Field(key: "removed_cooldown")]
	getter removed_cooldown : String

	@[YAML::Field(key: "blacklisted")]
	getter blacklisted : String

	@[YAML::Field(key: "reason_prefix")]
	getter reason_prefix : String

	@[YAML::Field(key: "spoiled")]
	getter spoiled : String

	@[YAML::Field(key: "unspoiled")]
	getter unspoiled : String 

	@[YAML::Field(key: "ranked_message")]
	getter ranked_message : String

	@[YAML::Field(key: "force_leave")]
	getter force_leave : String
end