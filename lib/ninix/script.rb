# -*- coding: utf-8 -*-
#
#  script.rb - a Sakura Script parser
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2004-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module Script

  TOKEN_TAG         = 1
  TOKEN_META        = 2
  TOKEN_OPENED_SBRA = 3
  TOKEN_CLOSED_SBRA = 4
  TOKEN_NUMBER      = 5
  TOKEN_STRING      = 6


  SCRIPT_TAG  = 1
  SCRIPT_TEXT = 2

  TEXT_META   = 1
  TEXT_STRING = 2

  class ParserError < Exception

    def initialize(message, error='strict',
                   script=nil, src=nil, column=nil, length=nil, skip=nil)
      if not ['strict', 'loose'].include?(error)
        raise ValueError('unknown error scheme: {0}'.format(str(error)))
      end
      @message = message
      @error = error
      @script = script or []
      @src = src or ''
      @column = column
      @length = length or 0
      @skip = skip or 0
    end

    def __getitem__(n)
      if n == 0
        if @error == 'strict'
          return []
        else
          return @script
        end
      elsif n == 1
        if @error == 'strict' or @column == nil
          return ''
        else
          return @src[@column + @skip, @src.length]
        end
      else
        raise IndexError('tuple index out of range')
      end
    end

    def __str__
      if @column != nil
        column = @column
        if @src
          dump = [@src[:column],
                  '\x1b[7m',
                  (@src[column, column + @length] or ' '),
                  '\x1b[m',
                  @src[column + @length, @src.length]].join('')
        else
          dump = ''
        end
      else
        column = '??'
        dump = @src
      end
      return 'ParserError: column {0}: {1}\n{2}'.format(column, @message, dump)
    end
  end

  class Parser

    def initialize(error='strict')
      if not ['strict', 'loose'].include?(error)
        raise ValueError('unknown error scheme: {0}'.format(str(error)))
      end
      @error = error
    end

    def perror(msg, position='column', skip=nil)
      if not ['column', 'eol'].include?(position)
#        raise ValueError('unknown position scheme: ', position.to_s)
      end
      if not ['length', 'rest', nil].include?(skip)
#        raise ValueError('unknown skip scheme: ', skip.to_s)
      end
      if position == 'column'
        column = @column
        length = @length
        if skip == 'length'
          skip = length
        elsif skip == 'rest'
          skip = @src[column, @src.length].length
        else
          skip = 0
        end
      else
        column = @src.length
        length = 0
        skip = 0
      end
#      return ParserError(msg, @error,
#                         @script, @src, column, length, skip)
      return "" # XXX
    end

    def tokenize(s)
  patterns = [
              [TOKEN_TAG, Regexp.new(/\\[Cehunjcxtqzy*v0123456789fmia!&+-]|\\[sbp][0-9]?|\\w[0-9]|\\_[wqslvVbe+cumna]|\\__[ct]|\\URL/)],
              [TOKEN_META, Regexp.new(/%month|%day|%hour|%minute|%second|%username|%selfname2?|%keroname|%friendname|%songname|%screen(width|height)|%exh|%et|%m[szlchtep?]|%dms|%j|%c|%wronghour|%\*/)],
              [TOKEN_NUMBER, Regexp.new(/[0-9]+/)],
              [TOKEN_OPENED_SBRA, Regexp.new(/\[/)],
              [TOKEN_CLOSED_SBRA, Regexp.new(/\]/)],
              [TOKEN_STRING, Regexp.new(/(\\\\|\\%|\\\]|[^\\\[\]%0-9])+/)],
              [TOKEN_STRING, Regexp.new(/[%\\]/)],
             ]
      tokens = []
      pos = 0
      end_ = s.length
      while pos < end_
        for token, pattern in patterns
#          print("s, pos: ", s, "  ", pos, "\n")
          match = pattern.match(s, pos)
#          print("MATCH: ", match, "\n")
#          print("MATCH: ", match.begin(0), "\n")
          if match != nil and match.begin(0) == pos
            break
          end
#        else
#          raise RuntimeError('should not reach here')
        end
#        print(match.methods.sort, "\n")
#        print("X: ", match.to_s, "\n")
        if match == nil ## FIXME
          raise RuntimeError('should not reach here')
        end
#        print("MATCH(end):", match.end(0), "\n")
        tokens << [token, match.to_s]
#        print("TOKEN: ", token, " - ", s[pos, match.end(0)], "\n")
        pos += match.to_s.length
#        print("TOKENS: ", tokens, "\n")
#        print("NEXT: ", s[pos, s.length - 1], "\n")
      end
      return tokens
    end

    def next_token
      begin
        token, lexeme = @tokens.shift
      rescue # except IndexError:
        raise perror('unexpected end of script', position='eol')
      end
      print("NEXT: ", token, " ", lexeme, "\n")
      if token == nil
        return "", ""
      end
      @column += @length
      @length = lexeme.length
      return token, lexeme
    end

    def parse(s)
      print("PARSE: ", s, "\n")
      if not s
        return []
      end
      # tokenize the script
      @src = s
      @tokens = tokenize(@src)
      print("TOKENS: ", @tokens, "\n")
      @column = 0
      @length = 0
      # parse the sequence of tokens
      @script = []
      text = []
      string_chunks = []
      scope = 0
      anchor = nil
      while @tokens
        token, lexeme = next_token()
        if token == TOKEN_STRING and lexeme == '\\'
          if string_chunks
            text << [TEXT_STRING, string_chunks.join('')]
          end
          if text
            @script << [SCRIPT_TEXT, text, @column]
          end
#          raise perror('unknown tag', skip='length')
        elsif token == TOKEN_STRING and lexeme == '%'
          string_chunks << lexeme
          text << [TEXT_STRING, string_chunks.join('')]
          @script << [SCRIPT_TEXT, text, @column]
          #raise perror('unknown meta string', skip='length')
          return []
        end
        if [TOKEN_NUMBER, TOKEN_OPENED_SBRA,
            TOKEN_STRING, TOKEN_CLOSED_SBRA].include?(token)
          lexeme = lexeme.gsub('\\', '\\')
          lexeme = lexeme.gsub('\%', '%')
          string_chunks << lexeme
          next
        end
        if string_chunks
          text << [TEXT_STRING, string_chunks.join('')]
          string_chunks = []
        end
        if token == TOKEN_META
          if lexeme == '%j'
            argument = read_sbra_id()
            text << [TEXT_META, lexeme, argument]
          elsif lexeme == '%*'
            if text
              @script << [SCRIPT_TEXT, text, @column]
              text = []
            end
            @script << [SCRIPT_TAG, '\\!', [[TEXT_STRING, '*'],], @column]
          else
            text << [TEXT_META, lexeme]
          end
          next
        end
        if !text.empty?
          print(text, "\n")
          @script << [SCRIPT_TEXT, text, @column]
          text = []
        end
        if ['\\a', '\\c', '\\e', '\\t', '\\_e',
            '\\v', '\\y', '\\z', '\\_q',
            '\\4', '\\5', '\\6', '\\7',
            '\\2', '\\*', '\\-', '\\+', '\\_+',
            '\\_n', '\\_V', '\\__c', '\\__t',
            '\\C'].include?(lexeme)
          @script << [SCRIPT_TAG, lexeme, @column]
        elsif ['\\0', '\\h'].include?(lexeme)
          @script << [SCRIPT_TAG, lexeme, @column]
          scope = 0
        elsif ['\\1', '\\u'].include?(lexeme)
          @script << [SCRIPT_TAG, lexeme, @column]
          scope = 1
        elsif ['\\s', '\\b', '\\p'].include?(lexeme)
          argument = read_sbra_id()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif lexeme.start_with?('\\s') or \
          lexeme.start_with?('\\b') or \
          lexeme.start_with?('\\p') or \
          lexeme.start_with?('\\w')
          num = lexeme[2]
          if lexeme.start_with?('\\s') and scope == 1
            num = str(int(num) + 10)
          end
          @script << [SCRIPT_TAG, lexeme[0, 2], num, @column]
        elsif ['\\_w'].include?(lexeme)
          argument = read_sbra_number()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif ['\\i', '\\j', '\\&', '\\_u', '\\_m'].include?(lexeme)
          argument = read_sbra_id()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif ['\\_b', '\\_c', '\\_l', '\\_v', '\\m',
               '\\3', '\\8', '\\9'].include?(lexeme)
          argument = read_sbra_text()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif ['\\n', '\\x'].include?(lexeme)
          if not @tokens.empty? and @tokens[0][0] == TOKEN_OPENED_SBRA
            argument = read_sbra_text()
            @script << [SCRIPT_TAG, lexeme, argument, @column]
          else
            @script << [SCRIPT_TAG, lexeme, @column]
          end
        elsif ['\\URL'].include?(lexeme)
          buf = [read_sbra_text()]
          while not @tokens.empty? and @tokens[0][0] == TOKEN_OPENED_SBRA
            buf << read_sbra_text()
            buf << read_sbra_text()
          end
          @script << [SCRIPT_TAG, lexeme] + buf + [@column, ]
        elsif ['\\!'].include?(lexeme)
          args = split_params(read_sbra_text())
          @script << [SCRIPT_TAG, lexeme] + args + [@column, ]
        elsif ['\\q'].include?(lexeme)
          if not @tokens.empty? and @tokens[0][0] == TOKEN_OPENED_SBRA
            args = split_params(read_sbra_text())
            if args.length != 2
#              raise perror('wrong number of arguments', skip='length')
              return []
            end
            if args[1].length != 1 or not args[1][0][1]
#              raise perror('syntax error (expected an ID)', skip='length')
              return []
            end
            arg1 = args[0]
            arg2 = args[1][0][1]
            @script << [SCRIPT_TAG, lexeme, arg1, arg2, @column]
          else
            arg1 = read_number()
            arg2 = read_sbra_id()
            arg3 = read_sbra_text()
            @script << [SCRIPT_TAG, lexeme, arg1, arg2, arg3, @column]
          end
        elsif ['\\_s'].include?(lexeme)
          if @tokens and @tokens[0][0] == TOKEN_OPENED_SBRA
            args = []
            for arg in split_params(read_sbra_text())
              print("ARG: ", arg, "\n")
              args  << arg[0][1]
            end
            @script << [SCRIPT_TAG, lexeme] + args + [@column, ]
          else
            @script << [SCRIPT_TAG, lexeme, @column]
          end
        elsif ['\\_a'].include?(lexeme)
          if anchor == nil
            anchor = perror('syntax error (unbalanced \_a tag)', skip='rest')
            @script << [SCRIPT_TAG, lexeme, read_sbra_id(), @column]
          else
            anchor = nil
            @script << [SCRIPT_TAG, lexeme, @column]
          end
        elsif ['\\f'].include?(lexeme)
          args = []
          for arg in split_params(read_sbra_text())
            args << arg[0][1]
          end
          @script << [SCRIPT_TAG, lexeme] + args + [@column, ]
        else
          #raise perror('unknown tag ({0})'.format(lexeme), skip='length')
          return []
        end
        if anchor != nil
          if @script[-1][0, 2] == [SCRIPT_TAG, '\e']
            @script.insert(@script.length - 1,
                           [SCRIPT_TAG, '\_a', @script[-1][2]])
          else
            @script << [SCRIPT_TAG, '\_a', @column]
          end
          #anchor.script = @script
          #raise anchor
          return []
        end
        if string_chunks
          text << [TEXT_STRING, string_chunks.join('')]
        end
        if text
          @script << [SCRIPT_TEXT, text, @column]
        end
        return @script
      end
    end

    def read_number
      token, number = next_token()
      if token != TOKEN_NUMBER
        raise perror('syntax error (expected a number)')
      end
      return number
    end

    def read_sbra_number
      token, lexeme = next_token()
      if token != TOKEN_OPENED_SBRA
        raise perror('syntax error (expected a square bracket)')
      end
      token, number = next_token()
      if token != TOKEN_NUMBER
        raise perror('syntax error (expected a number)', skip='length')
      end
      token, lexeme = next_token()
      if token != TOKEN_CLOSED_SBRA
        raise perror('syntax error (expected a square bracket)', skip='length')
      end
      return number
    end

    def read_sbra_id
      text = read_sbra_text()
      if text.length != 1
        #raise perror('syntax error (expected a single ID)', skip='length')
        return []
      end
      begin
        sbra_id = str(int(text[0][1]))
      rescue #  except:
        # pass
      else
        return sbra_id
      end
      return text[0][1]
    end

    def read_sbra_text
      token, lexeme = next_token()
      if token != TOKEN_OPENED_SBRA
#        raise perror('syntax error (expected a square bracket)')
        print('syntax error (expected a square bracket)', "\n")
      end
      text = []
      string_chunks = []
      while @tokens
        print("TOKENS: ", @tokens, "\n")
        token, lexeme = next_token()
        if [TOKEN_NUMBER, TOKEN_STRING, TOKEN_OPENED_SBRA, TOKEN_TAG].include?(token)
          lexeme = lexeme.gsub('\\', '\\')
          lexeme = lexeme.gsub('\%', '%')
          lexeme = lexeme.gsub('\]', ']')
          string_chunks << lexeme
          next
        end
        print("STR_CH: ", string_chunks, "\n")
        if not string_chunks.empty?
          text << [TEXT_STRING, string_chunks.join('')]
          string_chunks = []
        end
        if token == TOKEN_CLOSED_SBRA
          break
        elsif token == TOKEN_META
          text << [TEXT_META, lexeme]
        else
          #raise perror('syntax error (wrong type of argument)', skip='length')
          return []
        end
#      else
#        raise perror('unexpected end of script', position='eol')
      end
      print("TEXT: ", text, "\n")
      return text
    end

    def split_params(text)
#      re_param = Regexp.new('("[^"]*"|[^,])*')
#      re_quote = Regexp.new('"([^"]*)"')
      re_param = Regexp.new(/("[^"]*"|[^,])*/)
      re_quote = Regexp.new(/([^"]*)/)

      params = []
      buf = []
      for token, lexeme in text
        print("TOKEN: ", token, "\n")
        print("LEXEME: ", lexeme, "\n")
        i = 0
        j = lexeme.length
        if token == TEXT_STRING
          while i < j
            match = re_param.match(lexeme, i)
            print("MATCH: ", match, "\n")
            if match == nil
              break
            end
            
#            param, n = re_quote.subn(lambda m: m.group(1), match.group())
            param = re_quote.match(match[0])
            print("PARAM: ", param, "\n")
            if param != nil
              param = param[1]
            end
            if param != nil or not buf.empty?
              buf << [token, param]
            end
            print("BUF: ", buf, "\n")
            params << buf
            buf = []
            i = match.end(0)
            if i < j
#              assert lexeme[i] == ','
              i += 1
            end
          end
        end
        if i < j
          buf << [token, lexeme[i, lexeme.length]]
        end
        if not buf.empty?
          params << buf
        end
        return params
      end
    end
  end

  class TEST

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
      parser = Parser.new()
      for test in @testcases
#        begin
          print(parser.tokenize(test), "\n")
#        rescue # except ParserError as e:
#          print(e)
#        end
      end
    end

    def test_parser(error='strict')
      parser = Parser.new(error)
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
        if node[0] == SCRIPT_TAG
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
        elsif node[0] == SCRIPT_TEXT
          print('TEXT', "\n")
          print_text(node[1], 1)
        end
      end
    end

    def print_text(text, indent)
      for chunk in text
        if chunk[0] == TEXT_STRING
#          print(['\t' * indent, 'STRING\t"{0}"'.format(chunk[1])].join(''), "\n")
          print(['\t' * indent, 'STRING\t"', chunk[1].to_s, '"'].join(''), "\n")
        elsif chunk[0] == TEXT_META
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

Script::TEST.new

