# -*- coding: utf-8 -*-
#
#  script.rb - a Sakura Script parser
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2004-2016 by Shyouzou Sugitani <shy@users.osdn.me>
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

  class ParserError < StandardError
    attr_writer :script

    def initialize(
          error: 'strict',
          script: nil, src: nil, column: nil, length: nil, skip: nil)
      super()
      unless ['strict', 'loose'].include?(error)
        fail ValueError('unknown error scheme: ' + error.to_s)
      end
      @error = error
      @script = (script or [])
      @src = (src or '')
      @column = column
      @length = (length or 0)
      @skip = (skip or 0)
    end

    def get_item
      if @error == 'strict'
        done = []
      else
        done = @script
      end
      if @error == 'strict' or @column.nil?
        script = ''
      else
        script = @src[@column + @skip, @src.length]
      end
      return done, script
    end

    def format
      unless @column.nil?
        column = @column
        unless @src.empty?
          dump = [@src[0..@column-1],
                  "\x1b[7m",
                  (@src[column, @length] or ' '),
                  "\x1b[m",
                  @src[column+@length..@src.length-1]].join('')
        else
          dump = ''
        end
      else
        column = '??'
        dump = @src
      end
      return 'ParserError: column ' + column.to_s + ': ' + message + "\n" + dump
    end
  end

  class Parser

    def initialize(error: 'strict')
      unless ['strict', 'loose'].include?(error)
        fail ArgumentError('unknown error scheme: ' + error.to_s)
      end
      @error = error
    end

    def perror(position: 'column', skip: nil)
      unless ['column', 'eol'].include?(position)
        fail ArgumentError('unknown position scheme: ', position.to_s)
      end
      unless ['length', 'rest', nil].include?(skip)
        fail ArgumentError('unknown skip scheme: ', skip.to_s)
      end
      if position == 'column'
        column = @column
        length = @length
        case skip
        when 'length'
          skip = length
        when 'rest'
          skip = @src[column, @src.length].length
        else
          skip = 0
        end
      else
        column = @src.length
        length = 0
        skip = 0
      end
      return ParserError.new( \
                              :error => @error, \
                              :script => @script, \
                              :src => @src, \
                              :column => column, \
                              :length => length, \
                              :skip => skip \
                            )
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
          match = pattern.match(s, pos)
          break if not match.nil? and match.begin(0) == pos
        end
        fail RuntimeError('should not reach here') if match.nil?
        tokens << [token, match[0]]
        pos = match.end(0)
      end
      return tokens
    end

    def next_token
      begin
        token, lexeme = @tokens.shift
      rescue IndexError
        raise perror(:position => 'eol'), 'unexpected end of script'
      end
      return "", "" if token.nil?
      @column += @length
      @length = lexeme.length
      return token, lexeme
    end

    def parse(s)
      return [] if s.nil? or s.empty?
      # tokenize the script
      @src = s
      @tokens = tokenize(@src)
      @column = 0
      @length = 0
      # parse the sequence of tokens
      @script = []
      text = []
      string_chunks = []
      scope = 0
      anchor = nil
      while not @tokens.empty?
        token, lexeme = next_token()
        if token == TOKEN_STRING and lexeme == '\\'
          unless string_chunks.empty?
            text << [TEXT_STRING, string_chunks.join('')]
          end
          unless text.empty?
            @script << [SCRIPT_TEXT, text, @column]
          end
          fail perror(:skip => 'length'), 'unknown tag'
        elsif token == TOKEN_STRING and lexeme == '%'
          string_chunks << lexeme
          text << [TEXT_STRING, string_chunks.join('')]
          @script << [SCRIPT_TEXT, text, @column]
          fail perror(:skip => 'length'), 'unknown meta string'
          return []
        end
        if [TOKEN_NUMBER, TOKEN_OPENED_SBRA,
            TOKEN_STRING, TOKEN_CLOSED_SBRA].include?(token)
          lexeme = lexeme.gsub('\\\\', '\\')
          lexeme = lexeme.gsub('\\%', '%')
          string_chunks << lexeme
          next
        end
        unless string_chunks.empty?
          text << [TEXT_STRING, string_chunks.join('')]
          string_chunks = []
        end
        if token == TOKEN_META
          if lexeme == '%j'
            argument = read_sbra_id()
            text << [TEXT_META, lexeme, argument]
          elsif lexeme == '%*'
            unless text.empty?
              @script << [SCRIPT_TEXT, text, @column]
              text = []
            end
            @script << [SCRIPT_TAG, "\\!", [[TEXT_STRING, '*'],], @column]
          else
            text << [TEXT_META, lexeme]
          end
          next
        end
        unless text.empty?
          @script << [SCRIPT_TEXT, text, @column]
          text = []
        end
        if ["\\a", "\\c", "\\e", "\\t", "\\_e",
            "\\v", "\\y", "\\z", "\\_q",
            "\\4", "\\5", "\\6", "\\7",
            "\\2", "\\*", "\\-", "\\+", "\\_+",
            "\\_n", "\\_V", "\\__c", "\\__t",
            "\\C"].include?(lexeme)
          @script << [SCRIPT_TAG, lexeme, @column]
        elsif ["\\0", "\\h"].include?(lexeme)
          @script << [SCRIPT_TAG, lexeme, @column]
          scope = 0
        elsif ["\\1", "\\u"].include?(lexeme)
          @script << [SCRIPT_TAG, lexeme, @column]
          scope = 1
        elsif ["\\s", "\\b", "\\p"].include?(lexeme)
          argument = read_sbra_id()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif lexeme.start_with?("\\s") or \
          lexeme.start_with?("\\b") or \
          lexeme.start_with?("\\p") or \
          lexeme.start_with?("\\w")
          num = lexeme[2]
          if lexeme.start_with?("\\s") and scope == 1
            num = (num.to_i + 10).to_s
          end
          @script << [SCRIPT_TAG, lexeme[0, 2], num, @column]
        elsif ["\\_w"].include?(lexeme)
          argument = read_sbra_number()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif ["\\i", "\\j", "\\&", "\\_u", "\\_m"].include?(lexeme)
          argument = read_sbra_id()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif ["\\_b", "\\_c", "\\_l", "\\_v", "\\m",
               "\\3", "\\8", "\\9"].include?(lexeme)
          argument = read_sbra_text()
          @script << [SCRIPT_TAG, lexeme, argument, @column]
        elsif ["\\n", "\\x"].include?(lexeme)
          if not @tokens.empty? and @tokens[0][0] == TOKEN_OPENED_SBRA
            argument = read_sbra_text()
            @script << [SCRIPT_TAG, lexeme, argument, @column]
          else
            @script << [SCRIPT_TAG, lexeme, @column]
          end
        elsif ["\\URL"].include?(lexeme)
          buf = [read_sbra_text()]
          while not @tokens.empty? and @tokens[0][0] == TOKEN_OPENED_SBRA
            buf << read_sbra_text()
            buf << read_sbra_text()
          end
          @script << [SCRIPT_TAG, lexeme] + buf + [@column, ]
        elsif ["\\!"].include?(lexeme)
          args = split_params(read_sbra_text())
          @script << [SCRIPT_TAG, lexeme] + args + [@column, ]
        elsif ["\\q"].include?(lexeme)
          if not @tokens.empty? and @tokens[0][0] == TOKEN_OPENED_SBRA
            args = split_params(read_sbra_text())
            if args.length != 2
              fail perror(:skip => 'length'), 'wrong number of arguments'
              return []
            end
            if args[1].length != 1 or args[1][0][1].empty?
              fail perror(:skip => 'length'), 'syntax error (expected an ID)'
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
        elsif ["\\_s"].include?(lexeme)
          if not @tokens.empty? and @tokens[0][0] == TOKEN_OPENED_SBRA
            args = []
            for arg in split_params(read_sbra_text())
              args  << arg[0][1]
            end
            @script << [SCRIPT_TAG, lexeme] + args + [@column, ]
          else
            @script << [SCRIPT_TAG, lexeme, @column]
          end
        elsif ["\\_a"].include?(lexeme)
          if anchor.nil?
            anchor = perror(:skip => 'rest')
            @script << [SCRIPT_TAG, lexeme, read_sbra_id(), @column]
          else
            anchor = nil
            @script << [SCRIPT_TAG, lexeme, @column]
          end
        elsif ["\\f"].include?(lexeme)
          args = []
          for arg in split_params(read_sbra_text())
            args << arg[0][1]
          end
          @script << [SCRIPT_TAG, lexeme] + args + [@column, ]
        else
          fail perror(:skip => 'length'), 'unknown tag (' + lexeme + ')'
          return []
        end
      end
      unless anchor.nil?
        if @script[-1][0, 2] == [SCRIPT_TAG, '\e']
          @script.insert(@script.length - 1,
                         [SCRIPT_TAG, '\_a', @script[-1][2]])
        else
          @script << [SCRIPT_TAG, '\_a', @column]
        end
        anchor.script = @script
        fail anchor, 'syntax error (unbalanced \_a tag)'
      end
      unless string_chunks.empty?
        text << [TEXT_STRING, string_chunks.join('')]
      end
      unless text.empty?
        @script << [SCRIPT_TEXT, text, @column]
      end
      return @script
    end

    def read_number
      token, number = next_token()
      fail perror, 'syntax error (expected a number)' if token != TOKEN_NUMBER
      return number
    end

    def read_sbra_number
      token, lexeme = next_token()
      fail perror, 'syntax error (expected a square bracket)' if token != TOKEN_OPENED_SBRA
      token, number = next_token()
      fail perror(:skip => 'length'), 'syntax error (expected a number)' if token != TOKEN_NUMBER
      token, lexeme = next_token()
      fail perror(:skip => 'length'), 'syntax error (expected a square bracket)' if token != TOKEN_CLOSED_SBRA
      return number
    end

    def read_sbra_id
      text = read_sbra_text()
      if text.length != 1
        fail perror(:skip => 'length'), 'syntax error (expected a single ID)'
        return []
      end
      begin
        sbra_id = Integer(text[0][1]).to_s
      rescue
        # pass
      else
        return sbra_id
      end
      return text[0][1]
    end

    def read_sbra_text
      token, lexeme = next_token()
      fail perror, 'syntax error (expected a square bracket)' if token != TOKEN_OPENED_SBRA
      text = []
      string_chunks = []
      close_flag = false
      while not @tokens.empty?
        token, lexeme = next_token()
        if [TOKEN_NUMBER, TOKEN_STRING, TOKEN_OPENED_SBRA, TOKEN_TAG].include?(token)
          lexeme = lexeme.gsub('\\', '\\')
          lexeme = lexeme.gsub('\%', '%')
          lexeme = lexeme.gsub('\]', ']')
          string_chunks << lexeme
          next
        end
        unless string_chunks.empty?
          text << [TEXT_STRING, string_chunks.join('')]
          string_chunks = []
        end
        case token
        when TOKEN_CLOSED_SBRA
          close_flag = true
          break
        when TOKEN_META
          text << [TEXT_META, lexeme]
        else
          fail perror(:skip => 'length'), 'syntax error (wrong type of argument)'
          return []
        end
      end
      fail perror(:position => 'eol'), 'unexpected end of script' unless close_flag
      return text
    end

    def split_params(text)
      re_param = Regexp.new(/("[^"]*"|[^,])*/)
      re_quote = Regexp.new(/"([^"]*)"/)

      params = []
      buf = []
      for token, lexeme in text
        i = 0
        j = lexeme.length
        if token == TEXT_STRING
          while i < j
            match = re_param.match(lexeme, i)
            break if match.nil? or match.begin(0) != i
            param = re_quote.match(match[0])
            unless param.nil?
              param = (param.pre_match + param[1] + param.post_match)
            else
              param = match[0]
            end
            unless param.nil? and buf.empty?
              buf << [token, param]
            end
            i = match.end(0)
            if i < j
              fail "assert" unless lexeme[i] == ','
              params << buf
              buf = []
              i += 1
            end
          end
        end
        if i < j
          buf << [token, lexeme[i, lexeme.length]]
        end
      end
      unless buf.empty?
        params << buf
      end
      return params
    end
  end
end
