require "ninix/logging"
require "ninix/dll/misaka"

module NinixTest

  class MisakaTest

    def initialize()
      Logging::Logging.set_level(Logger::DEBUG)
    end

    def test_ini(dirlist)
      for top_dir in dirlist
        print('Reading', File.join(top_dir, 'misaka.ini'), '...', "\n")
        filelist, debug, error = Misaka.read_misaka_ini(top_dir)
        print('number of dictionaries =', filelist.length, "\n")
        for filename in filelist
          print(filename, "\n")
        end
        print('debug =', debug, "\n")
        print('error =', error, "\n")
      end
    end

    def test_lexer(filelist, charset='CP932')
      lexer = Misaka::Lexer.new(charset: charset)
      for filename in filelist
        if not File.file?(filename)
          next
        end
        print('Reading ', filename, '...', "\n")
        lexer.read(open(filename, :encoding => charset + ":utf-8"))
      end
      token_names = {
        Misaka::TOKEN_WHITESPACE =>    'TOKEN_WHITESPACE',
        Misaka::TOKEN_NEWLINE =>       'TOKEN_NEWLINE',
        Misaka::TOKEN_OPEN_BRACE =>    'TOKEN_OPEN_BRACE',
        Misaka::TOKEN_CLOSE_BRACE =>   'TOKEN_CLOSE_BRACE',
        Misaka::TOKEN_OPEN_PAREN =>    'TOKEN_OPEN_PAREN',
        Misaka::TOKEN_CLOSE_PAREN =>   'TOKEN_CLOSE_PAREN',
        Misaka::TOKEN_OPEN_BRACKET =>  'TOKEN_OPEN_BRACKET',
        Misaka::TOKEN_CLOSE_BRACKET => 'TOKEN_CLOSE_BRACKET',
        Misaka::TOKEN_DOLLAR =>        'TOKEN_DOLLAR',
        Misaka::TOKEN_COMMA =>         'TOKEN_COMMA',
        Misaka::TOKEN_SEMICOLON =>     'TOKEN_SEMICOLON',
        Misaka::TOKEN_OPERATOR =>      'TOKEN_OPERATOR',
        Misaka::TOKEN_DIRECTIVE =>     'TOKEN_DIRECTIVE',
        Misaka::TOKEN_TEXT =>          'TOKEN_TEXT',
      }
      for token, lexeme, position in lexer.buffer
        print('L' + position[0].to_s + ' : C' + position[1..-1].to_s + ' :', token_names[token], ':')
        if [Misaka::TOKEN_WHITESPACE,
            Misaka::TOKEN_NEWLINE,
            Misaka::TOKEN_OPEN_BRACE,
            Misaka::TOKEN_CLOSE_BRACE,
            Misaka::TOKEN_OPEN_PAREN,
            Misaka::TOKEN_CLOSE_PAREN,
            Misaka::TOKEN_OPEN_BRACKET,
            Misaka::TOKEN_CLOSE_BRACKET,
            Misaka::TOKEN_DOLLAR,
            Misaka::TOKEN_COMMA,
            Misaka::TOKEN_SEMICOLON].include?(token)
            print(lexeme.dump)
        else
            print(lexeme)
        end
        print("\n")
      end
    end

    def test_parser(filelist, charset='CP932')
      for filename in filelist
        if not File.file?(filename)
          next
        end
        print('Reading', filename, '...', "\n")
        parser = Misaka::Parser.new(charset: charset)
        parser.read(open(filename, :encoding => charset + ":utf-8"))
        common, dic = parser.get_dict()
        if common != nil
          print('Common', "\n")
          parser.dump_node(common, depth: 2)
        end
        for name, parameters, sentences in dic
          print('Group ', name, "\n")
          if parameters
            print('Parameter:', "\n")
            for parameter in parameters
              print('>>> ', parameter, "\n")
              parser.dump_node(parameter, depth: 2)
            end
          end
          if sentences
            print('Sentence:', "\n")
            for sentence in sentences
              print('>>> ', sentence, "\n")
              parser.dump_list(sentence, depth: 2)
            end
          end
        end
      end
    end
      
    def test_interpreter(top_dir)
      misaka = Misaka::Shiori.new('misaka.dll') # XXX
      misaka.load(dir: top_dir)
      while true
        begin
          print('>>> ')
          line = STDIN.gets or break
          line.chomp!
        rescue Interrupt
          print('Break', "\n")
          next
        end
        command = line.split()
        if command.length == 1 and command[0].start_with?('$')
            print(misaka.eval_variable([[Misaka::NODE_TEXT, command[0]]]), "\n")
        elsif command.length == 1 and command[0] == 'reload'
            misaka.load()
        else
            print('list of commands:', "\n")
            print('  $id     get variable value', "\n")
            print('  reload  reload dictionaries', "\n")
        end
      end
      print("\n") # break
    end
  end
end

$:.unshift(File.dirname(__FILE__))

USAGE = "Usage: test-shiori-misaka.rb [ini|lexer|parser|interp] ...\n"
charset = 'CP932' # XXX
mt = NinixTest::MisakaTest.new()
if ARGV.length == 1
  print(USAGE)
elsif ARGV[0] == 'ini'
  mt.test_ini(ARGV[1..-1])
elsif ARGV[0] == 'lexer'
  mt.test_lexer(ARGV[1..-1], charset)
elsif ARGV[0] == 'parser'
  mt.test_parser(ARGV[1..-1], charset)
elsif ARGV[0] == 'interp'
  mt.test_interpreter(ARGV[1])
else
  print(USAGE)
end
