require "ninix/logging"
require "ninix/dll/niseshiori"

module NinixTest

  class NISESHIORITest

    def initialize(top_dir)
      niseshiori = Niseshiori::Shiori.new('niseshiori.dll')
      niseshiori.show_description
      niseshiori.load(:dir => top_dir)
      dump_dict(niseshiori)
      while true
        print(niseshiori.getaistringrandom(), "\n")
        begin
          STDIN.gets
        rescue EOFError, Interrupt
          break
        end
      end
    end

    def dump_dict(ns)
      print('DICT')
      for k, v in ns.dict
        if k.is_a?(Array)
          k = '(' + k[0].to_s, ', ' + k[1..-1].to_s, ')'
        end
        print(k, "\n")
        for e in v
          print("\t", e, "\n")
        end
      end
      print('*' * 50, "\n")
      print('CHAINS', "\n")
      for t, chain_list in ns.type_chains
        print(t, "\n")
        for c, w in chain_list
          print('-> ' + c.to_s, ', ' + w.to_s, "\n")
        end
      end
      for key, dic in ns.word_chains
        print('(' + key[0].to_s + ', ' + key[1..-1].to_s + ')', "\n")
        for t, chain_list in dic
          prefix = '-> ' + t.to_s
          for c, w in chain_list
            print(prefix, ('-> ' + c.to_s + ', ' + w.to_s), "\n")
            prefix = ['   ', ' ' * t.length].join('')
          end
        end
      end
      print('*' * 50, "\n")
      print('KEYWORDS', "\n")
      for (t, w), s in ns.keywords
        print(t, w, "\n")
        print('->', s, "\n")
      end
      print('*' * 50, "\n")
      print('RESPONSES', "\n")
      for k, v in ns.responses
        print_condition(k)
        print('->', v, "\n")
      end
      print('*' * 50, "\n")
      print('GREETINGS', "\n")
      for k, v in ns.greetings
        print(k, "\n")
        print('->', v, "\n")
      end
      print('*' * 50, "\n")
      print('EVENTS', "\n")
      for k, v in ns.events
        print_condition(k)
        for e in v
          print('->', e, "\n")
        end
      end
    end

    def print_condition(condition)
      prefix = 'Condition'
      for cond_type, expr in condition
        if cond_type == Niseshiori::Shiori::COND_COMPARISON
          print(prefix, ("'" + expr[0].to_s + "' '" + expr[1].to_s + "' '" + expr[2..-1].to_s + "'"), "\n")
        elsif cond_type == Niseshiori::Shiori::COND_STRING
          print(prefix, "'" + expr.to_s + "'", "\n")
        end
        prefix = '      and'
      end
    end
  end
end

$:.unshift(File.dirname(__FILE__))

USAGE= "Usage: test-shiori-niseshiori.rb <dir>\n"
if ARGV.length != 1
  print(USAGE)
else
  top_dir = ARGV[0]
  if not Niseshiori.list_dict(top_dir)
    print('no dictionary')
    return
  end
  Logging::Logging.set_level(Logger::DEBUG)
  NinixTest::NISESHIORITest.new(top_dir)
end
