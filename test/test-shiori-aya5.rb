require "ninix/dll/aya5"

module NinixTest

  class AYA5Test

    def initialize(top_dir, function, argv, dll_name: 'aya5.dll')
      ## FIXME
      ##logger = logging.getLogger()
      ##logger.setLevel(logging.DEBUG) # XXX
      aya = Aya5::Shiori.new(dll_name)
      aya.show_description
      aya.load(:dir => top_dir)
      result = aya.request("GET SHIORI/3.0\r\n" \
                           "ID: " + function.to_s + "\r\n" \
                           "Sender: AYA\r\n" \
                           "SecurityLevel: local\r\n\r\n".encode(aya.charset))
      #result = aya.dic.get_function(function).call(argv)
      #print(str(result, aya.charset))
      print(result.to_s, "\n")
    end
  end
end

$:.unshift(File.dirname(__FILE__))

USAGE= "Usage(1): test-shiori-aya.rb <dir> <dll_name> <function> [<arguments>]\n" \
       "Usage(2): test-shiori-aya.rb encrypt <in_file> <out_file>\n"
if ARGV.length < 2
  print(USAGE)
elsif ['encrypt', 'decrypt'].include?(ARGV[0])
  if ARGV.length != 3
    print(USAGE)
  else
    path = File.join(".", ARGV[1])
    open(path, 'rb') do |inputf|
      path = File.join(".", ARGV[2])
      open(path, 'wb') do |outputf|
        while true
          c = inputf.read(1)
          if not c or c == ''
            break
          end
          if ARGV[0] == 'encrypt'
            outputf.write(encrypt_char(c))
          else
            outputf.write(decrypt_char(c))
          end
        end
      end
    end
  end
else
  NinixTest::AYA5Test.new(ARGV[0], ARGV[2], ARGV[3..-1], :dll_name => ARGV[1])
end
