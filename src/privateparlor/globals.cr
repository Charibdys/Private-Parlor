VERSION = "0.3.0"

enum Ranks
  Banned    =  -10
  User      =    0
  Moderator =   10
  Admin     =  100
  Host      = 1000
end

alias MessageProc = Proc(Int64, Int64 | Nil, Tourmaline::Message) | Proc(Int64, Int64 | Nil, Array(Tourmaline::Message))
