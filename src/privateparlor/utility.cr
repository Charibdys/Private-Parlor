require "digest"

# Bind to libcrypt
@[Link("crypt")]
lib LibCrypt
  fun crypt(password : UInt8*, salt : UInt8*) : UInt8*
end

# Generate a 8chan or Secretlounge-ng style tripcode from a given string in the format `name#pass`.
#
# Returns a named tuple containing the tripname and tripcode.
def generate_tripcode(tripkey : String, salt : String) : NamedTuple
  split = tripkey.split('#', 2)
  name = split[0]
  pass = split[1]

  if !salt.empty?
    # Based on 8chan's secure tripcodes
    pass = String.new(pass.encode("Shift_JIS"), "Shift_JIS")
    tripcode = "!#{Digest::SHA1.base64digest(pass + salt)[0...10]}"
  else
    salt = (pass[...8] + "H.")[1...3]
    salt = String.build do |s|
      salt.each_char do |c|
        if ':' <= c <= '@'
          s << c + 7
        elsif '[' <= c <= '`'
          s << c + 6
        elsif '.' <= c <= 'Z'
          s << c
        else
          s << '.'
        end
      end
    end

    tripcode = "!#{String.new(LibCrypt.crypt(pass[...8], salt))[-10...]}"
  end

  {name: name, tripcode: tripcode}
end

# Returns arguments found after a command from a message text.
def get_args(msg : String?, count : Int = 1) : String | Array(String) | Nil
  if msg
    args = msg.split(count + 1)
    case args.size
    when 2
      return args[1]
    when 2..
      return args.shift
    else
      return nil
    end
  end
end
