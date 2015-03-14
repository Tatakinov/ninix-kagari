# coding: utf-8

require "ninix/script"

module NinixTest

  class ScriptTest

    def initialize
      @testcases = [
        # legal cases
        '\s[4]ちゃんと選んでよう〜っ。\w8\uまあ、ユーザさんも忙しいんやろ‥‥\e',
        '%selfnameと%keroname\e',
        'エスケープのテスト \\, \%, [, ], \] どーかな?\e',
        '\j[http://www.asahi.com]\e',
        '\j[http://www.asahi.com/[escape\]/\%7Etest]\e',
        '\j[http://www.asahi.com/%7Etest/]\e',
        '\h\s[0]%usernameさんは今どんな感じ？\n\n\q0[#temp0][まあまあ]\q1[#temp1][今ひとつ]\z',
        '\q0[#temp0][今日は%month月%day日だよ]\e',
        '\q0[#cancel][行かない]\q1[http://www.asahi.com/%7Etest/][行く]\e',
        '\q[テスト,test]\q[%month月%day日,date]\e',
        '\q[テスト,http://www.asahi.com/]\e',
        '\q[テスト,http://www.asahi.com/%7Etest/]\e',
        '\h\s[0]%j[#temp0]\e',
        '\URL[http://www.asahi.com/]\e',
        '\URL[http://www.asahi.com/%7Etest/]\e',
        '\URL[行かない][http://www.asahi.com/][トップ][http://www.asahi.com/%7Etest/][テスト]\e',
        '\_s\s5\w44えんいー%c\e',
        '\h%m?\e',
        '\URL[http://www.foo.jp/%7Ebar/]',
        '\b[0]\b[normal]\i[0]\i[eyeblink]',
        '\c\x\t\_q\*\1\2\4\5\-\+\_+\a\__c\__t\_n',
        '\_l[0,0]\_v[test.wav]\_V\_c[test]',
        '\h\s0123\u\s0123\h\s1234\u\s1234',
        '\s[-1]\b[-1]',
        '\_u[0x0010]\_m[0x01]\&[Uuml]\&[uuml]',
        '\n\n[half]\n',
        '\![open,teachbox]\e',
        '\![raise,OnUserEvent,"0,100"]\e',
        '\![raise,"On"User"Event",%username,,"",a"","""","foo,bar"]\e',
        '\_a[http://www.asahi.com/]Asahi.com\_a\_s\_a[test]foo\_a\e',
        '\_a[test]%j[http://www.asahi.com]%hour時%minute分%second秒\_a',
        '\![raise,OnWavePlay,voice\hello.mp3]\e',
        '\q[Asahi.com,新聞を読む]',
        '\j[\s4]\e',
        '\p[2]\s[100]3人目\p3\s[0]4人目',
        '\_s[0,2]keroは\_s仲間はずれ\_sです。\e',
        # illegal cases (to be passed)
        '20%終了 (%hour時%minute分%second秒)',
        '\g',
        # illegal cases
        '\j[http://www.asahi',
        '\s\e',
        '\j4\e',
        '\q0[#temp0]\e',
        '\q[test]\e',
        '\q[foo,bar,test]\e',
        '\q[起動時間,%exh時間]\e',
        '\q[,]\e',
        '\URL[しんぶーん][http://www.asahi.com/]\e',
        '\_atest\_a',
        '\_a[test]',
        '\s[normal]',
        '\s[0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001]',
      ]
      run()
    end

    def test_tokenizer()
      parser = Script::Parser.new
      for test in @testcases
#        begin
          print(parser.tokenize(test), "\n")
#        rescue # except ParserError as e:
#          print(e)
#        end
      end
    end

    def test_parser(error='strict')
      parser = Script::Parser.new(error)
      for test in @testcases
        print('*' * 60, "\n")
        print(test, "\n")
        script = []
        while true
#          begin
#            script.extend(parser.parse(test))
          script.concat(parser.parse(test))
#          rescue # except ParserError as e:
#            print('-' * 60, "\n")
##            print(e)
##            done, test = e
##            script.extend(done)
#            break # XXX
#          else
            break
#          end
        end
        print('-' * 60, "\n")
        print_script_tree(script)
      end
    end

    def print_script_tree(tree)
      for node in tree
        if node[0] == Script::SCRIPT_TAG
          name, args = node[1], node[2, -1]
          print('TAG', name, "\n")
          print("ARGS: ", args, "\n")
#          for n in range(args.length)
          if args != nil
            for arg in 0..(args.length - 1)
              if isinstance(args[n], str)
                print('\tARG#{0:d}\t{1}'.format(n + 1, args[n]), "\n")
              else
                print('\tARG#{0:d}\tTEXT'.format(n + 1), "\n")
                print_text(args[n], 2)
              end
            end
          end
        elsif node[0] == Script::SCRIPT_TEXT
          print('TEXT', "\n")
          print_text(node[1], 1)
        end
      end
    end

    def print_text(text, indent)
      for chunk in text
        if chunk[0] == Script::TEXT_STRING
#          print(['\t' * indent, 'STRING\t"{0}"'.format(chunk[1])].join(''), "\n")
          print(['\t' * indent, 'STRING\t"', chunk[1].to_s, '"'].join(''), "\n")
        elsif chunk[0] == Script::TEXT_META
          name, args = chunk[1], chunk[2, chunk.length]
          print(['\t' * indent, 'META\t', name].join(''), "\n")
          for n in 0..(args.length - 1)
            print(['\t' * indent, '\tARG#{0:d}\t{1}'.format(n + 1, args[n])].join(''), "\n")
          end
        end
      end
    end

    def run
#    import os
#      if len(sys.argv) == 2 and sys.argv[1] == 'tokenizer'
        test_tokenizer()
#      elsif len(sys.argv) == 3 and sys.argv[1] == 'parser'
#        test_parser(sys.argv[2])
      test_parser("loose") # XXX
#      else
#        print('Usage:', os.path.basename(sys.argv[0]), \
#              '[tokenizer|parser [strict|loose]]')
#      end
    end
  end
end

# Syntax of the Sakura Script:
#   "\e"
#   "\h"
#   "\u"
#   "\s" OpenedSbra Number ClosedSbra
#   "\b" OpenedSbra Number ClosedSbra
#   "\n" (OpenedSbra Text ClosedSbra)?
#   "\w" Number
#   "\_w" OpenedSbra Number ClosedSbra
#   "\j" OpenedSbra ID ClosedSbra
#   "\c"
#   "\x"
#   "\t"
#   "\_q"
#   "\_s"
#   "\_n"
#   "\q" Number OpenedSbra Text ClosedSbra OpenedSbra Text ClosedSbra
#   "\q" OpenedSbra Text "," ID ClosedSbra
#   "\z"
#   "\y"
#   "\*"
#   "\v"
#   "\8" OpenedSbra ID ClosedSbra
#   "\m" OpenedSbra ID ClosedSbra
#   "\i" OpenedSbra ID ClosedSbra
#   "\_e"
#   "\a"
#   "\!" OpenedSbra Text ClosedSbra
#   "\_c" OpenedSbra Text ClosedSbra
#   "\__c"
#   "\URL" OpenedSbra Text ClosedSbra [ OpenedSbra Text ClosedSbra OpenedSbra Text ClosedSbra ]*
#   "\&" OpenedSbra ID ClosedSbra
#   "\_u" OpenedSbra ID ClosedSbra
#   "\_m" OpenedSbra ID ClosedSbra
#   "\_a" OpenedSbra ID ClosedSbra Text "\_a"

NinixTest::ScriptTest.new
