require "ninix/dll/aya"

module NinixTest

  class AYATest

    def initialize(top_dir, function, argv)
      aya = Aya::Shiori.new('aya.dll')
      aya.show_description
      aya.load(:dir => top_dir)
      result = aya.dic.get_function(function).call(argv)
      print(result.to_s, "\n")
    end
  end
end

$:.unshift(File.dirname(__FILE__))

USAGE= "Usage(1): test-shiori-aya.rb <dir> <function> [<arguments>]\n" \
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
  NinixTest::AYATest.new(ARGV[0], ARGV[1], ARGV[2..-1])
end
