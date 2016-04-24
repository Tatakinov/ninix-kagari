# coding: utf-8
require_relative "../lib/ninix/logging"
require_relative "../lib/ninix/dll/satori"

module NinixTest

  class SatoriTest

    def initialize()
      Logging::Logging.set_level(Logger::DEBUG)
    end

    def test_ini(top_dir)
      dic_list = Satori.list_dict(top_dir)
      print('number of files = ', dic_list.length, "\n")
      for dic in dic_list
        print(dic, "\n")
      end
    end

    def test_parser(path)
      if not File.file?(path)
        return
      end
      parser = Satori::Parser.new()
      parser.read(path)
      for name, talk in parser.talk
        for node_list in talk
          print('＊', " ", name, "\n")
          parser.print_nodelist(node_list)
          print("\n")
        end
      end
      for name, word in parser.word
        print('＠', " ", name, "\n")
        for node_list in word
          print('>>>', " ", test_expand(node_list), "\n")
          parser.print_nodelist(node_list, :depth => 2)
        end
        print("\n")
      end
    end

    def test_expand(node_list)
      buf = []
      for node in node_list
        if node[0] == Satori::NODE_TEXT
          buf.concat(node[1])
        elsif node[0] == Satori::NODE_REF
          buf.concat([test_expand(node[1])])
        else
          raise RuntimeError('should not reach here')
        end
      end
      return buf.join('')
    end

    def test_interp(top_dir)
      satori = Satori::SATORI.new(:satori_dir => top_dir)
      satori.load()
      while true
        begin
          print('>>> ')
          name = STDIN.gets or break
          name.chomp!
          name = name.encode('utf-8', :invalid => :replace, :undef => :replace) ## FIXME
        rescue Interrupt
          break
        end
        if name.start_with?('＠')
          print(satori.getstring(name[1..-1]), "\n")
        elsif name.start_with?('＊')
          print(satori.get_event_response(name[1..-1]), "\n")
        else
          print(satori.get_event_response(name), "\n")
        end
        print(satori.get_script(name), "\n")
      end
      print("\n") # break
    end
  end
end

$:.unshift(File.dirname(__FILE__))

USAGE = "Usage: test-shiori-satori.rb [ini|parser|interp] ...\n"
st = NinixTest::SatoriTest.new()
if ARGV[0] == 'ini'
  st.test_ini(ARGV[1])
elsif ARGV[0] == 'parser'
  st.test_parser(ARGV[1])
elsif ARGV[0] == 'interp'
  st.test_interp(ARGV[1])
else
  print(USAGE)
end
