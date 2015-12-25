require "ninix/logging"
require "ninix/dll/kawari"

module NinixTest

  class Kawari7Test

    def initialize(kawari_dir)
      Logging::Logging.set_level(Logger::DEBUG)
      print("reading kawari.ini...\n")
      kawari = kawari_open(kawari_dir)
      for rdict in kawari.rdictlist
        for k, v in rdict
          print(k, "\n")
          for p in v
            print(['\t', p].join(''), "\n")
          end
        end
      end
      for kdict in kawari.kdictlist
        for k, v in kdict
          print(['[ "', k.join('", "'), '" ]'].join(''), "\n")
          for p in v
            print(['\t', p].join(''), "\n")
          end
        end
      end
      while true
        print('=' * 40, "\n")
        s = kawari.getaistringrandom()
        print('-' * 40, "\n")
        print(s, "\n")
        begin
          STDIN.gets
        rescue EOFError, Interrupt
          break
        end
      end
    end

    def kawari_open(kawari_dir)
      pathlist = [nil]
      rdictlist = [{}]
      kdictlist = [{}]
      for file_type, path in Kawari.list_dict(kawari_dir)
        pathlist << path
        if file_type == Kawari::INI_FILE
          rdict, kdict = Kawari.create_dict(Kawari.read_ini(path))
        elsif Kawari.is_local_script(path)
          rdict, kdict = Kawari.read_local_script(path)
        else
          rdict, kdict = Kawari.create_dict(Kawari.read_dict(path))
        end
        rdictlist << rdict
        kdictlist << kdict
      end
      return Kawari::Kawari7.new(kawari_dir, pathlist, rdictlist, kdictlist)
    end
  end
end

$:.unshift(File.dirname(__FILE__))

USAGE= "Usage: test-shiori-kawari.rb <dir>\n"
if ARGV.length != 1
  print(USAGE)
else
  NinixTest::Kawari7Test.new(ARGV[0])
end
