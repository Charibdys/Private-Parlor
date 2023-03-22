VERSION = "0.6.0"

enum Ranks
  Banned    =  -10
  User      =    0
  Moderator =   10
  Admin     =  100
  Host      = 1000
end

alias MessageProc = Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message))

alias LocaleParameters = Hash(String, String | Time | Int32 | Bool | Ranks | Nil)

# Cooldown constants
COOLDOWN_TIME_BEGIN    = [1, 5, 25, 120, 720, 4320] # begins with 1m, 5m, 25m, 2h, 12h, 3d
COOLDOWN_TIME_LINEAR_M =  4320                      # continues 7d, 10d, 13d, 16d, ... (linear)
COOLDOWN_TIME_LINEAR_B = 10080
WARN_EXPIRE_HOURS      = 7 * 24

KARMA_WARN_PENALTY = 10

# Spam limits
SPAM_LIMIT            = 3.0_f32
SPAM_LIMIT_HIT        = 6.0_f32
SPAM_INTERVAL_SECONDS =      10

# Spam score calculation
SCORE_STICKER        =   1.5_f32
SCORE_ALBUM          =   2.5_f32
SCORE_BASE_MESSAGE   =  0.75_f32
SCORE_BASE_FORWARD   =  1.25_f32
SCORE_TEXT_CHARACTER = 0.002_f32
SCORE_TEXT_LINEBREAK =   0.1_f32
