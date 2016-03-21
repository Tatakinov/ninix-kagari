# -*- coding: utf-8 -*-
#
#  misaka.rb - a "美坂" compatible Shiori module for ninix
#  Copyright (C) 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# error recovery
# - ${foo}
# - $(foo) ?

require "stringio"

require_relative "../home"
require_relative "../logging"

begin
  require 'charlock_holmes'
rescue LoadError
  CharlockHolmes = nil
end

module Misaka

  class MisakaError < StandardError # ValueError
    # pass
  end

  def self.lexical_error(path: nil, position: nil)
    if path == nil and position == nil
      error = 'lexical error'
    elsif path == nil
      at = 'line ' + position[0].to_s + ', column ' + position[1].to_s
      error = 'lexical error at ' + at.to_s
    elsif position == nil
      error = 'lexical error in ' + path.to_s
    else
      at = 'line ' + position[0].to_s + ', column ' + position[1].to_s
      error = 'lexical error at ' + at.to_s + ' in ' + path.to_s
    end
    fail MisakaError.new(error)
  end

  def self.syntax_error(message, path: nil, position: nil)
    if path == nil and position == nil
      error = 'syntax error (' + message.to_s + ')'
    elsif path == nil
      at = 'line ' + position[0].to_s + ', column ' + position[1].to_s
      error = 'syntax error at ' + at.to_s + ' (' + message.to_s{1} + ')'
    elsif position == nil
      error = 'syntax error in ' + path.to_s + ' (' + message.to_s{1} + ')'
    else
      at = 'line ' + position[0].to_s + ', column ' + position[1].to_s
      error = 'syntax error at ' + at.to_s + ' in ' + path.to_s + ' (' + message.to_s + ')'
    end
    fail MisakaError.new(error)
  end

  def self.list_dict(top_dir)
    buf = []
    begin
      filelist, debug, error = Misaka.read_misaka_ini(top_dir)
    rescue #except Exception as e:
      filelist = []
    end
    for filename in filelist
      buf << File.join(top_dir, filename)
    end
    return buf
  end

  def self.read_misaka_ini(top_dir)
    path = File.join(top_dir, 'misaka.ini')
    filelist = []
    debug = 0
    error = 0
    open(path) do |f|
      while true
        line = f.gets
        if line == nil
          break
        end
        line = line.strip()
        if line.empty? or line.start_with?('//')
          next
        end
        if line == 'dictionaries'
          line = f.gets
          if line.strip() != '{'
            Misaka.syntax_error('expected an open brace', :path => path)
          end
          while true
            line = f.gets
            if line == nil
              Misaka.syntax_error('unexpected end of file', :path => path)
            end
            line = line.strip()
            if line == '}'
              break
            end
            if line.empty? or line.start_with?('//')
              next
            end
            filelist << Home.get_normalized_path(line)
          end
        elsif line == 'debug,0'
          debug = 0
        elsif line == 'debug,1'
          debug = 1
        elsif line == 'error,0'
          error = 0
        elsif line == 'error,1'
          error = 1
        elsif line == 'propertyhandler,0'
          #pass
        elsif line == 'propertyhandler,1'
          #pass
        else
          Logging::Logging.debug("misaka.rb: unknown directive '" + line.to_s + "'")
        end
      end
    end
    return filelist, debug, error
  end

  ###   LEXER   ###

  TOKEN_NEWLINE       = 1
  TOKEN_WHITESPACE    = 2
  TOKEN_OPEN_BRACE    = 3
  TOKEN_CLOSE_BRACE   = 4
  TOKEN_OPEN_PAREN    = 5
  TOKEN_CLOSE_PAREN   = 6
  TOKEN_OPEN_BRACKET  = 7
  TOKEN_CLOSE_BRACKET = 8
  TOKEN_DOLLAR        = 9
  TOKEN_COMMA         = 11
  TOKEN_SEMICOLON     = 12
  TOKEN_OPERATOR      = 13
  TOKEN_DIRECTIVE     = 14
  TOKEN_TEXT          = 15


  class Lexer
    attr_reader :buffer

    Re_comment = Regexp.new('\A[ \t]*//[^\r\n]*')
    Re_newline = Regexp.new('\A(\r\n|\r|\n)')
    Patterns = [
        [TOKEN_NEWLINE,       Re_newline],
        [TOKEN_WHITESPACE,    Regexp.new('\A[ \t]+')],
        [TOKEN_OPEN_BRACE,    Regexp.new('\A{')],
        [TOKEN_CLOSE_BRACE,   Regexp.new('\A}')],
        [TOKEN_OPEN_PAREN,    Regexp.new('\A\(')],
        [TOKEN_CLOSE_PAREN,   Regexp.new('\A\)')],
        [TOKEN_OPEN_BRACKET,  Regexp.new('\A\[')],
        [TOKEN_CLOSE_BRACKET, Regexp.new('\A\]')],
        [TOKEN_DOLLAR,        Regexp.new('\A\$')],
        [TOKEN_COMMA,         Regexp.new('\A,')],
        [TOKEN_SEMICOLON,     Regexp.new('\A;')],
        [TOKEN_OPERATOR,      Regexp.new('\A([!=]=|[<>]=?|=[<>]|&&|\|\||\+\+|--|[+\-*/]?=|[+\-*/%\^])')],
        [TOKEN_DIRECTIVE,     Regexp.new('\A#[_A-Za-z][_A-Za-z0-9]*')],
        #[TOKEN_TEXT,          Regexp.new("[!&|]|(\\[,\"]|[\x01\x02#'.0-9:?@A-Z\\_`a-z~]|[\x80-\xff].)+")],
        [TOKEN_TEXT,          Regexp.new("\\A((\"[^\"]*\")|[!&|]|(\\\\[,\"]|[\x01\x02#'.0-9:?@A-Z\\\\_`a-z~\"]|[\\u0080-\\uffff]+)+)")],
        ]
    Token_names = {
        TOKEN_WHITESPACE =>    'whitespace',
        TOKEN_NEWLINE =>       'a newline',
        TOKEN_OPEN_BRACE =>    'an open brace',
        TOKEN_CLOSE_BRACE =>   'a close brace',
        TOKEN_OPEN_PAREN =>    'an open paren',
        TOKEN_CLOSE_PAREN =>   'a close paren',
        TOKEN_OPEN_BRACKET =>  'an open bracket',
        TOKEN_CLOSE_BRACKET => 'a close bracket',
        TOKEN_DOLLAR =>        'a dollar',
        TOKEN_COMMA =>         'a comma',
        TOKEN_SEMICOLON =>     'a semicolon',
        TOKEN_OPERATOR =>      'an operator',
        TOKEN_DIRECTIVE =>     'an directive',
        TOKEN_TEXT =>          'text',
        }

    def initialize(charset: 'CP932')
      @buffer = []
      @charset = charset
    end

    def _match(data, line, column, path)
      temp = data.clone
      while temp.length > 0
        if column == 0
          match = Re_comment.match(temp)
          if match != nil
            column = column + match[0].length
            temp = match.post_match
            next
          end
        end
        break_flag = false
        for token, pattern in Patterns
          match = pattern.match(temp)
          if match != nil
            lexeme = match[0]
            if token == TOKEN_TEXT and \
              lexeme.start_with?('"') and lexeme.end_with?('"')
              if not lexeme.include?('$')
                @buffer << [token, lexeme[1..-2], [line, column]]
              else # XXX
                line, column = _match(lexeme[1..-2], line, column + 1, path)
                column += 1
              end
            else
              @buffer << [token, lexeme, [line, column]]
            end
            temp = match.post_match
            break_flag = true
            break
          end
        end
        if not break_flag
          ###print(temp[0..100 - 1])
          Misaka.lexical_error(:path => path, :position => [line, column])
        end
        if token == TOKEN_NEWLINE
          line = line + 1
          column = 0
        else
          column = column + lexeme.length
        end
      end
      return line, column
    end

    def read(f, path: nil)
      line = 1
      column = 0
      data = f.read()
      line, column = _match(data, line, column, path)
      @buffer << [TOKEN_NEWLINE, '', [line, column]]
      @path = path
    end

    def get_position
      return @position
    end

    def pop
      begin
        token, lexeme, @position = @buffer.shift
      rescue #except IndexError:
        Misaka.syntax_error('unexpected end of file', :path => @path)
      end
      ###print(token, repr(lexeme))
      return token, lexeme
    end

    def pop_check(expected)
      token, lexeme = pop()
      if token != expected
        Misaka.syntax_error(['exptected ', Token_names[expected], ', but returns ', Token_names[token]].join(''),
                            :path => @path, :position => get_position())
      end
      return lexeme
    end

    def look_ahead(index: 0)
      begin
        token, lexeme, position = @buffer[index]
      rescue #except IndexError:
        Misaka.syntax_error('unexpected end of file', :path => @path)
      end
      return token, lexeme
    end

    def skip_space(accept_eof: false)
      while not @buffer.empty?
        token, lexeme = look_ahead()
        if not [TOKEN_NEWLINE, TOKEN_WHITESPACE].include?(token)
          return false
        end
        pop()
      end
      if not accept_eof
        Misaka.syntax_error('unexpected end of file', :path => @path)
      end
      return true
    end

    def skip_line
      while not @buffer.empty?
        token, lexeme = pop()
        if token == TOKEN_NEWLINE
          break
        end
      end
    end
  end

  ###   PARSER   ###

  NODE_TEXT        = 1
  NODE_STRING      = 2
  NODE_VARIABLE    = 3
  NODE_INDEXED     = 4
  NODE_ASSIGNMENT  = 5
  NODE_FUNCTION    = 6
  NODE_IF          = 7
  NODE_CALC        = 8
  NODE_AND_EXPR    = 9
  NODE_OR_EXPR     = 10
  NODE_COMP_EXPR   = 11
  NODE_ADD_EXPR    = 12
  NODE_MUL_EXPR    = 13
  NODE_POW_EXPR    = 14


  class Parser

    def initialize(charset)
      @lexer = Lexer.new(:charset => charset)
      @charset = charset
    end

    def read(f, path: nil)
      @lexer.read(f, :path => path)
      @path = path
    end

    def get_dict
      common = nil
      groups = []
      # skip junk tokens at the beginning of the file
      while true
        if @lexer.skip_space(:accept_eof => true)
          return common, groups
        end
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_DIRECTIVE and lexeme == '#_Common' or \
          token == TOKEN_DOLLAR
          break
        end
        @lexer.skip_line()
      end
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_DIRECTIVE and lexeme == '#_Common'
        common = get_common()
        if @lexer.skip_space(:accept_eof => true)
          return common, groups
        end
      end
      while true
        groups << get_group()
        if @lexer.skip_space(:accept_eof => true)
          return common, groups
        end
      end
      return nil, []
    end

    def get_common
      @lexer.pop()
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_WHITESPACE
        @lexer.pop()
      end
      @lexer.pop_check(TOKEN_NEWLINE)
      condition = get_brace_expr()
      @lexer.pop_check(TOKEN_NEWLINE)
      return condition
    end

    def get_group
      # get group name
      buf = []
      @lexer.pop_check(TOKEN_DOLLAR)
      while true
        token, lexeme = @lexer.look_ahead()
        ##if token == TOKEN_TEXT or \
        ##   token == TOKEN_OPERATOR and \
        ##   ['+', '-', '*', '/', '%'].include?(lexeme)
        ## XXX
        if not [TOKEN_NEWLINE, TOKEN_COMMA, TOKEN_SEMICOLON].include?(token)
          token, lexeme = @lexer.pop()
          buf << unescape(lexeme)
        else
          break
        end
      end
      if buf.empty?
        Misaka.syntax_error('null identifier',
                            :path => @path,
                            :position => @lexer.get_position())
      end
      name = ['$', buf.join('')].join('')
      # get group parameters
      parameters = []
      while true
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_WHITESPACE
          @lexer.pop()
        end
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_NEWLINE
          break
        elsif [TOKEN_COMMA, TOKEN_SEMICOLON].include?(token)
          @lexer.pop()
        else
          Misaka.syntax_error('expected a delimiter',
                              :path => @path,
                              :position => @lexer.get_position())
        end
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_WHITESPACE
          @lexer.pop()
        end
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_NEWLINE
          break
        end
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_OPEN_BRACE
          parameters << get_brace_expr()
        elsif token == TOKEN_TEXT
          token, lexeme = @lexer.pop()
          parameters << [NODE_TEXT, unescape(lexeme)]
        else
          Misaka.syntax_error('expected a parameter or brace expression',
                              :path => @path,
                              :position => @lexer.get_position())
        end
      end
      # get sentences
      @lexer.pop_check(TOKEN_NEWLINE)
      sentences = []
      while true
        if @lexer.skip_space(:accept_eof => true)
          break
        end
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_DOLLAR
          break
        end
        sentence = get_sentence()
        if sentence == nil
          next
        end
        sentences << sentence
      end
      return [name, parameters, sentences]
    end

    def get_sentence
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_OPEN_BRACE
        token, lexeme = @lexer.look_ahead(:index => 1)
        if token == TOKEN_NEWLINE
          @lexer.pop_check(TOKEN_OPEN_BRACE)
          token, lexeme = @lexer.look_ahead()
          if token == TOKEN_WHITESPACE
            @lexer.pop()
          end
          @lexer.pop_check(TOKEN_NEWLINE)
          line = []
          while true
            @lexer.skip_space()
            token, lexeme = @lexer.look_ahead()
            if token == TOKEN_CLOSE_BRACE
              break
            end
            for node in get_line()
              line << node
            end
            @lexer.pop_check(TOKEN_NEWLINE)
          end
          @lexer.pop_check(TOKEN_CLOSE_BRACE)
          token, lexeme = @lexer.look_ahead()
          if token == TOKEN_WHITESPACE
            @lexer.pop()
          end
        else
          begin
            line = get_line() # beginning with brace expression
          rescue # except MisakaError as error:
            Logging::Logging.debug(error)
            @lexer.skip_line()
            return nil
          end
        end
      else
        begin
          line = get_line()
        rescue => error # except MisakaError as error:
          Logging::Logging.debug(error)
          @lexer.skip_line()
          return nil
        end
      end
      @lexer.pop_check(TOKEN_NEWLINE)
      return line
    end

    def is_whitespace(node)
      return (node[0] == NODE_TEXT and node[1].strip().empty?)
    end

    def unescape(text)
      text = text.gsub('\\,', ',')
      text = text.gsub('\\"', '"')
      return text
    end

    def get_word
      buf = []
      while true
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_TEXT
          token, lexeme = @lexer.pop()
          if unescape(lexeme).start_with?('"') and \
            unescape(lexeme).end_with?('"')
            buf << [NODE_STRING, unescape(lexeme)[1..-2]]
          else
            buf << [NODE_TEXT, unescape(lexeme)]
          end
        elsif [TOKEN_WHITESPACE, TOKEN_DOLLAR].include?(token)
          token, lexeme = @lexer.pop()
          buf << [NODE_TEXT, lexeme]
        elsif token == TOKEN_OPEN_BRACE
          buf << get_brace_expr()
        else
          break
        end
      end
      # strip whitespace at the beginning and/or end of line
      if not buf.empty? and is_whitespace(buf[0])
        buf.delete_at(0)
      end
      if not buf.empty? and is_whitespace(buf[-1])
        buf.delete_at(-1)
      end
      return buf
    end

    def get_line
      buf = []
      while true
        token, lexeme = @lexer.look_ahead()
        if [TOKEN_NEWLINE, TOKEN_CLOSE_BRACE].include?(token)
          break
        elsif token == TOKEN_TEXT
          token, lexeme = @lexer.pop()
          buf << [NODE_TEXT, unescape(lexeme)]
        elsif [TOKEN_WHITESPACE, TOKEN_DOLLAR,
               TOKEN_OPEN_PAREN, TOKEN_CLOSE_PAREN,
               TOKEN_OPEN_BRACKET, TOKEN_CLOSE_BRACKET,
               TOKEN_OPERATOR, TOKEN_COMMA, TOKEN_SEMICOLON,
               TOKEN_DIRECTIVE].include?(token)
          token, lexeme = @lexer.pop()
          buf << [NODE_TEXT, lexeme]
        elsif token == TOKEN_OPEN_BRACE
          buf << get_brace_expr()
        else
          fail RuntimeError.new('should not reach here')
        end
      end
      # strip whitespace at the beginning and/or end of line
      if not buf.empty? and is_whitespace(buf[0])
        buf.delete_at(0)
      end
      if not buf.empty? and is_whitespace(buf[-1])
        buf.delete_at(-1)
      end
      return buf
    end

    def get_brace_expr
      @lexer.pop_check(TOKEN_OPEN_BRACE)
      @lexer.skip_space()
      @lexer.pop_check(TOKEN_DOLLAR)
      @lexer.skip_space()
      # get identifier (function or variable)
      nodelist = [[NODE_TEXT, '$']]
      while true
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_TEXT or \
          (token == TOKEN_OPERATOR and ['+', '-', '*', '/', '%'].include?(lexeme))
          token, lexeme = @lexer.pop()
          nodelist << [NODE_TEXT, unescape(lexeme)]
        elsif token == TOKEN_OPEN_BRACE
          nodelist << get_brace_expr()
        else
          break
        end
      end
      if nodelist.length == 1
        Misaka.syntax_error('null identifier',
                            :path => @path,
                            :position => @lexer.get_position())
      end
      @lexer.skip_space()
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_OPEN_PAREN
        # function
        name = nodelist.map {|node| node[1] }.join('')
        if name == '$if'
          cond_expr = get_cond_expr()
          then_clause = [[NODE_TEXT, 'true']]
          else_clause = [[NODE_TEXT, 'false']]
          @lexer.skip_space()
          token, lexeme = @lexer.look_ahead()
          if token == TOKEN_OPEN_BRACE
            @lexer.pop_check(TOKEN_OPEN_BRACE)
            @lexer.skip_space()
            then_clause = []
            while true
              line = get_line()
              for node in line
                then_clause << node
              end
              token, lexem = @lexer.pop()
              if token == TOKEN_CLOSE_BRACE
                break
              end
              fail "assert" unless token == TOKEN_NEWLINE
            end
            @lexer.skip_space()
            token, lexeme = @lexer.look_ahead()
            if token == TOKEN_TEXT and lexeme == 'else'
              @lexer.pop()
              @lexer.skip_space()
              @lexer.pop_check(TOKEN_OPEN_BRACE)
              @lexer.skip_space()
              else_clause = []
              while true
                line = get_line()
                for node in line
                  else_clause << node
                end
                token, lexem = @lexer.pop()
                if token == TOKEN_CLOSE_BRACE
                  break
                end
                fail "assert" unless token == TOKEN_NEWLINE
              end
            elsif token == TOKEN_OPEN_BRACE ## XXX
              @lexer.pop_check(TOKEN_OPEN_BRACE)
              @lexer.skip_space()
              else_clause = []
              while true
                line = get_line()
                for node in line
                  else_clause << node
                end
                token, lexem = @lexer.pop()
                if token == TOKEN_CLOSE_BRACE
                  break
                end
                fail "assert" unless token == TOKEN_NEWLINE
              end
            else
              else_clause = [[NODE_TEXT, '']]
            end
          end
          node = [NODE_IF, cond_expr, then_clause, else_clause]
        elsif name == '$calc'
          node = [NODE_CALC, get_add_expr()]
        else
          @lexer.pop_check(TOKEN_OPEN_PAREN)
          @lexer.skip_space()
          args = []
          token, lexeme = @lexer.look_ahead()
          if token != TOKEN_CLOSE_PAREN
            while true
              args << get_argument()
              @lexer.skip_space()
              token, lexeme = @lexer.look_ahead()
              if token != TOKEN_COMMA
                break
              end
              @lexer.pop()
              @lexer.skip_space()
            end
          end
          @lexer.pop_check(TOKEN_CLOSE_PAREN)
          node = [NODE_FUNCTION, name, args]
        end
      else
        # variable
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_OPERATOR
          operator = @lexer.pop_check(TOKEN_OPERATOR)
          if ['=', '+=', '-=', '*=', '/='].include?(operator)
            @lexer.skip_space()
            value = get_add_expr()
          elsif operator == '++'
            operator = '+='
            value = [[NODE_TEXT, '1']]
          elsif operator == '--'
            operator = '-='
            value = [[NODE_TEXT, '1']]
          else
            Misaka.syntax_error(['bad operator ', operator].join(''),
                                :path => @path,
                                :position => @lexer.get_position())
          end
          node = [NODE_ASSIGNMENT, nodelist, operator, value]
        elsif token == TOKEN_OPEN_BRACKET
          @lexer.pop_check(TOKEN_OPEN_BRACKET)
          @lexer.skip_space()
          index = get_word()
          @lexer.skip_space()
          @lexer.pop_check(TOKEN_CLOSE_BRACKET)
          node = [NODE_INDEXED, nodelist, index]
        else
          node = [NODE_VARIABLE, nodelist]
        end
      end
      @lexer.skip_space()
      @lexer.pop_check(TOKEN_CLOSE_BRACE)
      return node
    end

    def get_argument
      buf = []
      while true
        token, lexeme = @lexer.look_ahead()
        if token == TOKEN_TEXT
          token, lexeme = @lexer.pop()
          if unescape(lexeme).start_with?('"') and \
            unescape(lexeme).end_with?('"')
            buf << [NODE_STRING, unescape(lexeme)[1..-2]]
          else
            buf << [NODE_TEXT, unescape(lexeme)]
          end
        elsif [TOKEN_WHITESPACE, TOKEN_DOLLAR,
               TOKEN_OPEN_BRACKET, TOKEN_CLOSE_BRACKET,
               TOKEN_OPERATOR, TOKEN_SEMICOLON].include?(token)
          token, lexeme = @lexer.pop()
          buf << [NODE_TEXT, lexeme]
        elsif token == TOKEN_OPEN_BRACE
          buf << get_brace_expr()
        elsif token == TOKEN_NEWLINE
          @lexer.skip_space()
        else
          break
        end
      end
      # strip whitespace at the beginning and/or end of line
      if not buf.empty? and is_whitespace(buf[0])
        buf.delete_at(0)
      end
      if not buf.empty? and is_whitespace(buf[-1])
        buf.delete_at(-1)
      end
      return buf
    end

    def get_cond_expr
      @lexer.pop_check(TOKEN_OPEN_PAREN)
      @lexer.skip_space()
      or_expr = get_or_expr()
      @lexer.skip_space()
      @lexer.pop_check(TOKEN_CLOSE_PAREN)
      return or_expr
    end

    def get_or_expr
      buf = [NODE_OR_EXPR]
      buf << get_and_expr()
      while true
        @lexer.skip_space()
        token, lexeme = @lexer.look_ahead()
        if not (token == TOKEN_OPERATOR and lexeme == '||')
          break
        end
        @lexer.pop()
        @lexer.skip_space()
        buf << get_and_expr()
      end
      if buf.length > 2
        return buf
      else
        return buf[1]
      end
    end

    def get_and_expr
      buf = [NODE_AND_EXPR]
      buf << get_sub_expr()
      while true
        @lexer.skip_space()
        token, lexeme = @lexer.look_ahead()
        if not (token == TOKEN_OPERATOR and lexeme == '&&')
          break
        end
        @lexer.pop()
        @lexer.skip_space()
        buf << get_sub_expr()
      end
      if buf.length > 2
        return buf
      else
        return buf[1]
      end
    end

    def get_sub_expr
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_OPEN_PAREN
        return get_cond_expr()
      else
        return get_comp_expr()
      end
    end

    def get_comp_expr
      buf = [NODE_COMP_EXPR]
      buf << get_add_expr()
      @lexer.skip_space()
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_OPERATOR and \
        ['==', '!=', '<', '<=', '=<', '>', '>=', '=>'].include?(lexeme)
        if lexeme == '=<'
          lexeme = '<='
        elsif lexeme == '=>'
          lexeme = '>='
        end
        buf << lexeme
        @lexer.pop()
        @lexer.skip_space()
        buf << get_add_expr()
      end
      if buf.length == 2
        buf << '=='
        buf << [[NODE_TEXT, 'true']]
      end
      return buf
    end

    def get_add_expr
      buf = [NODE_ADD_EXPR]
      buf << get_mul_expr()
      while true
        @lexer.skip_space()
        token, lexeme = @lexer.look_ahead()
        if not (token == TOKEN_OPERATOR and ['+', '-'].include?(lexeme))
          break
        end
        buf << lexeme
        @lexer.pop()
        @lexer.skip_space()
        buf << get_mul_expr()
      end
      if buf.length > 2
        return [buf]
      else
        return buf[1]
      end
    end

    def get_mul_expr
      buf = [NODE_MUL_EXPR]
      buf << get_pow_expr()
      while true
        @lexer.skip_space()
        token, lexeme = @lexer.look_ahead()
        if not (token == TOKEN_OPERATOR and ['*', '/', '%'].include?(lexeme))
          break
        end
        buf << lexeme
        @lexer.pop()
        @lexer.skip_space()
        buf << get_pow_expr()
      end
      if buf.length > 2
        return [buf]
      else
        return buf[1]
      end
    end

    def get_pow_expr
      buf = [NODE_POW_EXPR]
      buf << get_unary_expr()
      while true
        @lexer.skip_space()
        token, lexeme = @lexer.look_ahead()
        if not (token == TOKEN_OPERATOR and lexeme == '^')
          break
        end
        @lexer.pop()
        @lexer.skip_space()
        buf << get_unary_expr()
      end
      if buf.length > 2
        return [buf]
      else
        return buf[1]
      end
    end

    def get_unary_expr
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_OPERATOR and ['+', '-'].include?(lexeme)
        buf = [NODE_ADD_EXPR, [[NODE_TEXT, '0']], lexeme]
        @lexer.pop()
        @lexer.skip_space()
        buf << get_unary_expr()
        return [buf]
      else
        return get_factor()
      end
    end

    def get_factor
      token, lexeme = @lexer.look_ahead()
      if token == TOKEN_OPEN_PAREN
        @lexer.pop_check(TOKEN_OPEN_PAREN)
        @lexer.skip_space()
        add_expr = get_add_expr()
        @lexer.skip_space()
        @lexer.pop_check(TOKEN_CLOSE_PAREN)
        return add_expr
      else
        return get_word()
      end
    end

    # for debug
    def dump_list(nodelist, depth: 0)
      for node in nodelist
        dump_node(node, depth)
      end
    end

    def dump_node(node, depth)
      indent = '  ' * depth
      if node[0] == NODE_TEXT
        print([indent, 'TEXT'].join(''), " ", \
              ['"', node[1], '"'].join(''), "\n")
      elsif node[0] == NODE_STRING
        print([indent, 'STRING'].join(''), " ", \
              ['"', node[1], '"'].join(''), "\n")
      elsif node[0] == NODE_VARIABLE
        print([indent, 'VARIABLE'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
      elsif node[0] == NODE_INDEXED
        print([indent, 'INDEXED'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
        print([indent, 'index'].join(''), "\n")
        dump_list(node[2], :depth => depth + 1)
      elsif node[0] == NODE_ASSIGNMENT
        print([indent, 'ASSIGNMENT'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
        print([indent, 'op'].join(''), " ", node[2], "\n")
        dump_list(node[3], :depth => depth + 1)
      elsif node[0] == NODE_FUNCTION
        print([indent, 'FUNCTION'].join(''), " ", node[1], "\n")
        for i in 0..node[2].length-1
          print([indent, 'args[' + i.to_s + ']'].join(''), "\n")
          dump_list(node[2][i], :depth => depth + 1)
        end
      elsif node[0] == NODE_IF
        print([indent, 'IF'].join(''), "\n")
        dump_node(node[1], depth + 1)
        print([indent, 'then'].join(''), "\n")
        dump_list(node[2], :depth => depth + 1)
        print([indent, 'else'].join(''), "\n")
        dump_list(node[3], :depth => depth + 1)
      elsif node[0] == NODE_CALC
        print([indent, 'CALC'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
      elsif node[0] == NODE_AND_EXPR
        print([indent, 'AND_EXPR'].join(''), "\n")
        for i in 1..node.length-1
          dump_node(node[i], depth + 1)
        end
      elsif node[0] == NODE_OR_EXPR
        print([indent, 'OR_EXPR'].join(''), "\n")
        for i in 1..node.length-1
          dump_node(node[i], depth + 1)
        end
      elsif node[0] == NODE_COMP_EXPR
        print([indent, 'COMP_EXPR'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
        print([indent, 'op'].join(''), " ", node[2], "\n")
        dump_list(node[3], :depth => depth + 1)
      elsif node[0] == NODE_ADD_EXPR
        print([indent, 'ADD_EXPR'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
        for i in 2.step(node.length-1, 2)
          print([indent, 'op'].join(''), " ", node[i], "\n")
          dump_list(node[i + 1], :depth => depth + 1)
        end
      elsif node[0] == NODE_MUL_EXPR
        print([indent, 'MUL_EXPR'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
        for i in 2.step(node.length-1, 2)
          print([indent, 'op'].join(''), " ", node[i], "\n")
          dump_list(node[i + 1], :depth => depth + 1)
        end
      elsif node[0] == NODE_POW_EXPR
        print([indent, 'POW_EXPR'].join(''), "\n")
        dump_list(node[1], :depth => depth + 1)
        for i in 2..node.length-1
          print([indent, 'op ^'].join(''), "\n")
          dump_list(node[i], :depth => depth + 1)
        end
      else
        print(node, "\n")
        fail RuntimeError.new('should not reach here')
      end
    end
  end

# <<< syntax >>>
# dict       := sp ( common sp )? ( group sp )*
# sp         := ( NEWLINE | WHITESPACE )*
# common     := "#_Common" NEWLINE brace_expr NEWLINE
# group      := group_name ( delimiter ( STRING | brace_expr ) )*
#               ( delimiter )? NEWLINE ( sentence )*
# group_name := DOLLAR ( TEXT )+
# delimiter  := ( WHITESPACE )? ( COMMA | SEMICOLON ) ( WHITESPACE )?
# sentence   := line NEWLINE |
#               OPEN_BRACE NEWLINE ( line NEWLINE )* CLOSE_BRACE NEWLINE
# word       := ( TEXT | WHITESPACE | DOLLAR | brace_expr | string )*
# line       := ( TEXT | WHITESPACE | DOLLAR | brace_expr | QUOTE |
#                 OPEN_PAREN | CLOSE_PAREN | OPEN_BRACKET | CLOSE_BRACKET |
#                 OPERATOR | COMMA | SEMICOLON | DIRECTIVE )*
# string     := QUOTE (
#                 TEXT | WHITESPACE | DOLLAR | OPEN_BRACE | CLOSE_BRACE |
#                 OPEN_PAREN | CLOSE_PAREN | OPEN_BRACKET | CLOSE_BRACKET |
#                 OPERATOR | COMMA | SEMICOLON | DIRECTIVE )*
#               QUOTE
# brace_expr := variable | indexed | assignment | increment |
#               function | if | calc
# variable   := OPEN_BRACE sp var_name sp CLOSE_BRACE
# indexed    := OPEN_BRACE sp var_name sp
#               OPEN_BRACKET sp word sp CLOSE_BRACKET sp CLOSE_BRACE
# var_name   := DOLLAR ( TEXT | brace_expr )+
# assignment := OPEN_BRACE sp var_name sp assign_ops sp add_expr sp CLOSE_BRACE
# assign_ops := "=" | "+=" | "-=" | "*=" | "/="
# increment  := OPEN_BRACE sp var_name sp inc_ops sp CLOSE_BRACE
# inc_ops    := "+" "+" | "-" "-"
# function   := OPEN_BRACE sp DOLLAR sp ( TEXT )+ sp OPEN_PAREN
#               ( sp argument ( sp COMMA sp argument )* sp )?
#               CLOSE_PAREN sp CLOSE_BRACE
# argument   := ( TEXT | WHITESPACE | DOLLAR | brace_expr | string |
#                 OPEN_BRACKET | CLOSE_BRACKET | OPERATOR | SEMICOLON )*
# if         := OPEN_BRACE sp DOLLAR sp "if" sp cond_expr
#               ( sp OPEN_BRACE ( sp line )* sp CLOSE_BRACE ( sp "else"
#                 sp OPEN_BRACE ( sp line )* sp CLOSE_BRACE )? sp )?
#               sp CLOSE_BRACE
# calc       := OPEN_BRACE sp DOLLAR sp "calc" sp add_expr sp CLOSE_BRACE
# cond_expr  := OPEN_PAREN sp or_expr sp CLOSE_PAREN
# or_expr    := and_expr ( sp "||" sp and_expr )*
# and_expr   := sub_expr ( sp "&&" sp sub_expr )*
# sub_expr   := comp_expr | cond_expr
# comp_expr  := add_expr ( sp comp_op sp add_expr )?
# comp_op    := "==" | "!=" | "<" | "<=" | ">" | ">="
# add_expr   := mul_expr (sp add_op sp mul_expr)*
# add_op     := "+" | "-"
# mul_expr   := pow_expr (sp mul_op sp pow_expr)*
# mul_op     := "*" | "/" | "%"
# pow_expr   := unary_expr (sp pow_op sp unary_expr)*
# pow_op     := "^"
# unary_expr := unary_op sp unary_expr | factor
# unary_op   := "+" | "-"
# factor     := OPEN_PAREN sp add_expr sp CLOSE_PAREN | word


  ###   INTERPRETER   ###

  class Group

    def initialize(misaka, name, item_list: nil)
      @misaka = misaka
      @name = name
      if item_list == nil ## FIXME
        @list = []
      else
        @list = item_list
      end
    end

    def __len__
      return @list.length
    end

    def __getitem__(index)
      return @list[index]
    end

    def get
      if @list.empty?
        return nil
      end
      return @list.sample
    end

    def copy(name)
      return MisakaArray.new(@misaka, name, @list)
    end
  end


  class NonOverlapGroup < Group

    def initialize(misaka, name, item_list: nil)
      super(misaka, name, :item_list => item_list)
      @indexes = []
    end

    def get
      if @list.empty?
        return nil
      end
      if @indexes.empty?
        @indexes = Array(0..@list.length-1)
      end
      i = Array(0..@indexes.length-1).sample
      index = @indexes[i]
      @indexes.delete_at(i)
      return @list[index]
    end
  end


  class SequentialGroup < Group

    def initialize(misaka, name, item_list: nil)
      super(misaka, name, :item_list => item_list)
      @indexes = []
    end

    def get
      if @list.empty?
        return nil
      end
      if @indexes.empty?
        @indexes = Array(0..@list.length-1)
      end
      index = @indexes.shift
      return @list[index]
    end
  end


  class MisakaArray < Group

    def append(s)
      @list << [[NODE_TEXT, s.to_s]]
    end

    def index(s)
      for i in 0..@list.length-1
        if s == @misaka.expand(@list[i])
          return i
        end
      end
      return -1
    end

    def pop
      if @list.empty?
        return nil
      end
      i = Array(0..@list.length-1).sample
      item = @list[i]
      @list.delete_at(i)
      return item
    end

    def popmatchl(s)
      buf = []
      for i in 0..@list.length-1
        t = @misaka.expand(@list[i])
        if t.start_with?(s)
          buf << i
        end
      end
      if buf.empty?
        return nil
      end
      i = buf.sample
      item = @list[i]
      @list.delete_at(i)
      return item
    end
  end

  
  TYPE_SCHOLAR = 1
  TYPE_ARRAY   = 2


  class Shiori

    DBNAME = 'misaka.db'

    def initialize(dll_name)
      @dll_name = dll_name
      @charset = 'CP932'
    end

    def use_saori(saori)
      @saori = saori
    end

    def find(top_dir, dll_name)
      result = 0
      if not Misaka.list_dict(top_dir).empty?
        result = 210
      elsif File.file?(File.join(top_dir, 'misaka.ini'))
        result = 200
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: MISAKA compatible module for ninix\n" \
        "        Copyright (C) 2002 by Tamito KAJIYAMA\n" \
        "        Copyright (C) 2002, 2003 by MATSUMURA Namihiko\n" \
        "        Copyright (C) 2002-2016 by Shyouzou Sugitani")
    end

    def reset
      @dict = {}
      @variable = {}
      @constant = {}
      @misaka_debug = 0
      @misaka_error = 0
      @reference = [nil, nil, nil, nil, nil, nil, nil, nil]
      @mouse_move_count = {}
      @random_talk = -1
      @otherghost = []
      @communicate = ['', '']
      reset_request()
    end

    def load(dir: Dir::getwd)
      @misaka_dir = dir
      @dbpath = File.join(@misaka_dir, DBNAME)
      @saori_library = SaoriLibrary.new(@saori, @misaka_dir)
      reset()
      begin
        filelist, debug, error = Misaka.read_misaka_ini(@misaka_dir)
      rescue #except IOError:
        Logging::Logging.debug('cannot read misaka.ini')
        return 0
      rescue #except MisakaError as error:
        Logging::Logging.debug(error)
        return 0
      end
      @misaka_debug = debug
      @misaka_error = error
      global_variables = []
      global_constants = []
      # charset auto-detection
      if CharlockHolmes != nil
        detector = CharlockHolmes::EncodingDetector.new
        for filename in filelist
          path = File.join(@misaka_dir, filename)
          begin
            f = open(path, 'rb')
          rescue #except IOError:
            Logging::Logging.debug('cannot read ' + filename.to_s)
            next
          end
          ext = File.extname(filename)
          if ext == '.__1'
            result = detector.detect(crypt(f.read()))
          else
            result = detector.detect(f.read())
          end
          f.close()
          if result[:confidence] > 98 and \
            result[:encoding] != 'ISO-8859-1' # XXX
            @charset = result[:encoding]
            if @charset == 'Shift_JIS'
              @charset = 'CP932' # XXX
            end
            Logging::Logging.debug("CharlockHolmes(misaka.rb): '" + @charset.to_s + "'")
            break
          end
        end
      end
      for filename in filelist
        path = File.join(@misaka_dir, filename)
        basename = File.basename(filename, ".*")
        ext = File.extname(filename)
        begin
          if ext == '.__1' # should read lines as bytes
            f = open(path, 'rb')
          else
            f = open(path, :encoding => @charset + ":utf-8")
          end
        rescue #except IOError:
          Logging::Logging.debug('cannot read ' + filename.to_s)
          next
        end
        if ext == '.__1'
          f = StringIO.new(crypt(f.read()))
        end
        begin
          variables, constants = read(f, :path => path)
        rescue => error #except MisakaError as error:
          Logging::Logging.debug(error)
          next
        end
        global_variables |= variables
        global_constants |= constants
      end
      eval_globals(global_variables, false)
      load_database()
      eval_globals(global_constants, true)
      if @dict.include?('$_OnRandomTalk')
        @random_talk = 0
      end
      return 1
    end

    def crypt(data)
      return data.chars.map {|c| (c.ord ^ 0xff).chr }.join('').force_encoding(@charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
    end

    def eval_globals(sentences, constant)
      for sentence in sentences
        for node in sentence
          if node[0] == NODE_ASSIGNMENT
            eval_assignment(node[1], node[2], node[3], :constant => constant)
          elsif node[0] == NODE_FUNCTION
            eval_function(node[1], node[2])
          end
        end
      end
    end

    def read(f, path: nil)
      parser = Parser.new(@charset)
      parser.read(f, :path => path)
      common, dic = parser.get_dict()
      variables = []
      constants = []
      for name, parameters, sentences in dic
        if sentences == nil
          next
        elsif name == '$_Variable'
          variables |= sentences
          next
        elsif name == '$_Constant'
          constants |= sentences
          next
        end
        _GroupClass = Group
        conditions = []
        if common != nil
          conditions << common
        end
        for node in parameters
          if node[0] == NODE_IF
            conditions << node
          elsif node[0] == NODE_TEXT and node[1] == 'nonoverlap'
            _GroupClass = NonOverlapGroup
          elsif node[0] == NODE_TEXT and node[1] == 'sequential'
            _GroupClass = SequentialGroup
          else
            #pass # ignore unknown parameters
          end
        end
        group = _GroupClass.new(self, name, :item_list => sentences)
        if @dict.include?(name)
          grouplist = @dict[name]
        else
          grouplist = @dict[name] = []
        end
        grouplist << [group, conditions]
      end
      return variables, constants
    end

    def strip_newline(line)
      return line.chomp
    end

    def load_database
      begin
        open(@dbpath) do |f|
          while true
            begin
              line = f.gets
            rescue #except UnicodeError:
              Logging::Logging.debug(
                'misaka.rb: malformed database (ignored)')
              break
            end
            if line == nil
              break
            end
            header = strip_newline(line).split(nil, -1)
            if header[0] == 'SCHOLAR'
              name = header[1]
              value = strip_newline(f.gets)
              @variable[name] = [TYPE_SCHOLAR, value]
            elsif header[0] == 'ARRAY'
              begin
                size = Integer(header[1])
              rescue #except ValueError:
                Logging::Logging.debug(
                  'misaka.rb: malformed database (ignored)')
                break
              end
              name = header[2]
              array = MisakaArray.new(self, name)
              for _ in 0..size-1
                value = strip_newline(f.gets)
                array << value
              end
              @variable[name] = [TYPE_ARRAY, array]
            else
              fail RuntimeError.new('should not reach here')
            end
          end
        end
      rescue #except IOError:
        return
      end
    end

    def save_database
      begin
        open(@dbpath, 'w') do |f|
          for name in @variable.keys
            value_type, value = @variable[name]
            if value_type == TYPE_SCHOLAR
              if value == ''
                next
              end
              f.write('SCHOLAR ' + name.to_s + "\n" + value.to_s + "\n")
            elsif value_type == TYPE_ARRAY
              f.write('ARRAY ' + value.length.to_s + ' ' + name.to_s + "\n")
              for item in value
                f.write(expand(item).to_s + "\n")
              end
            else
              fail RuntimeError.new('should not reach here')
            end
          end
        end
      rescue #except IOError:
        Logging::Logging.debug('misaka.rb: cannot write database (ignored)')
        return
      end
    end

    def unload
      save_database()
      @saori_library.unload()
      return 1
    end

    def reset_request
      @req_command = ''
      @req_protocol = ''
      @req_key = []
      @req_header = {}
    end

    def request(req_string)
      header = req_string.split(/\r?\n/, 0)
      line = header.shift
      if line != nil
        line = line.force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace).strip()
        req_list = line.split(nil, -1)
        if req_list.length >= 2
          @req_command = req_list[0].strip()
          @req_protocol = req_list[1].strip()
        end
        for line in header
          line = line.force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace).strip()
          if line.empty?
            next
          end
          if not line.include?(':')
            next
          end
          key, value = line.split(':', 2)
          key = key.strip()
          begin
            value = Integer(value.strip())
          rescue
            value = value.strip()
          end
          @req_key << key
          @req_header[key] = value
        end
      end
      # FIXME
      ref0 = get_ref(0)
      ref1 = get_ref(1)
      ref2 = get_ref(2)
      ref3 = get_ref(3)
      ref4 = get_ref(4)
      ref5 = get_ref(5)
      ref6 = get_ref(6)
      ref7 = get_ref(7)
      event = @req_header['ID']
      script = nil
      if event == 'otherghostname'
        n = 0
        refs = []
        while true
          ref = get_ref(n)
          if ref != nil
            refs << ref
          else
            break
          end
          n += 1
        end
        @otherghost = []
        for ref in refs
          name, s0, s1 = ref.split(1.chr, 3)
          @otherghost << [name, s0, s1]
        end
      end
      if event == 'OnMouseMove'
        key = [ref3, ref4] # side, part
        if @mouse_move_count.include?(key)
          count = @mouse_move_count[key]
        else
          count = 0
        end
        @mouse_move_count[key] = count + 5
      end
      if event == 'OnCommunicate'
        @communicate = [ref0, ref1]
        script = get('$_OnGhostCommunicateReceive', :default => nil)
      elsif event == 'charset'
        script = @charset
      else
        @reference = [ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7]
        script = get(['$', event].join(''), :default => nil)
      end
      if event == 'OnSecondChange'
        if @random_talk == 0
          reset_random_talk_interval()
        elsif @random_talk > 0
          @random_talk -= 1
          if @random_talk == 0
            script = get('$_OnRandomTalk', :default => nil)
          end
        end
      end
      if script != nil
        script = script.strip()
      else
        script = ''
      end
      reset_request()
      response = ["SHIORI/3.0 200 OK\r\n",
                  "Sender: Misaka\r\n",
                  "Charset: ",
                  @charset.encode(@charset, :invalid => :replace, :undef => :replace),
                  "\r\n",
                  "Value: ",
                  script.encode(@charset, :invalid => :replace, :undef => :replace),
                  "\r\n"].join('')
      to = eval_variable([[NODE_TEXT, '$to']])
      if to != nil
        @variable.delete('$to')
        response = [response,
                    "Reference0: ",
                    to.encode(@charset, :invalid => :replace, :undef => :replace),
                    "\r\n"].join('')
      end
      response = [response, "\r\n"].join('')
      return response
    end

    def get_ref(num)
      key = ['Reference', num.to_s].join('')
      return @req_header[key]
    end

    # internal
    def reset_random_talk_interval
      interval = 0
      if @variable.include?('$_talkinterval')
        value_type, value = @variable['$_talkinterval']
      else
        value_type, value = TYPE_SCHOLAR, ''
      end
      if value_type == TYPE_SCHOLAR
        begin
          interval = [Integer(value), 0].max
        rescue #except ValueError:
          #pass
        end
      end
      @random_talk = (interval * Array(5..15).sample / 10.0).to_i
    end

    def get(name, default: '')
      grouplist = @dict[name]
      if grouplist == nil
        return default
      end
      for group, conditions in grouplist
        if eval_and_expr(conditions) == 'true'
          return expand(group.get())
        end
      end
      return default
    end

    def expand(nodelist)
      if nodelist == nil
        return ''
      end
      buf = []
      for node in nodelist
        buf << eval_(node)
      end
      return buf.join('')
    end

    def expand_args(nodelist)
      tmp = expand(nodelist)
      if tmp.start_with?('$')
        return eval_variable(nodelist)
      else
        return tmp
      end
    end

    def eval_(node)
      if node[0] == NODE_TEXT
        result = node[1]
      elsif node[0] == NODE_STRING
        result = node[1]
      elsif node[0] == NODE_VARIABLE
        result = eval_variable(node[1])
      elsif node[0] == NODE_INDEXED
        result = eval_indexed(node[1], node[2])
      elsif node[0] == NODE_ASSIGNMENT
        result = eval_assignment(node[1], node[2], node[3])
      elsif node[0] == NODE_FUNCTION
        result = eval_function(node[1], node[2])
      elsif node[0] == NODE_IF
        result = eval_if(node[1], node[2], node[3])
      elsif node[0] == NODE_CALC
        result = eval_calc(node[1])
      elsif node[0] == NODE_COMP_EXPR
        result = eval_comp_expr(node[1], node[2], node[3])
      elsif node[0] == NODE_AND_EXPR
        result = eval_and_expr(node[1..-1])
      elsif node[0] == NODE_OR_EXPR
        result = eval_or_expr(node[1..-1])
      elsif node[0] == NODE_ADD_EXPR
        result = eval_add_expr(node[1..-1])
      elsif node[0] == NODE_MUL_EXPR
        result = eval_mul_expr(node[1..-1])
      elsif node[0] == NODE_POW_EXPR
        result = eval_pow_expr(node[1..-1])
      else
        ##print(node)
        fail RuntimeError.new('should not reach here')
      end
      return result
    end

    SYSTEM_VARIABLES = [
        # current date and time
        '$year', '$month', '$day', '$hour', '$minute', '$second',
        # day of week (0 = Sunday)
        '$dayofweek',
        # ghost uptime
        '$elapsedhour', '$elapsedminute', '$elapsedsecond',
        # OS uptime
        '$elapsedhouros', '$elapsedminuteos', '$elapsedsecondos',
        # OS accumlative uptime
        '$elapsedhourtotal', '$elapsedminutetotal', '$elapsedsecondtotal',
        # system information
        '$os.version',
        '$os.name',
        '$os.phisicalmemorysize',
        '$os.freememorysize',
        '$os.totalmemorysize',
        '$cpu.vendorname',
        '$cpu.name',
        '$cpu.clockcycle',
        # number of days since the last network update
        '$daysfromlastupdate',
        # number of days since the first boot
        '$daysfromfirstboot',
        # name of the ghost with which it has communicated
        ##'$to',
        '$sender',
        '$lastsentence',
        '$otherghostlist',
        ]

    def eval_variable(name)
      now = Time.now
      name = expand(name)
      if name == '$year'
        result = now.year
      elsif name == '$month'
        result = now.month
      elsif name == '$day'
        result = now.day
      elsif name == '$hour'
        result = now.hour
      elsif name == '$minute'
        result = now.min
      elsif name == '$second'
        result = now.sec
      elsif name == '$dayofweek'
        result = now.wday
      elsif name == '$lastsentence'
        result = @communicate[1]
      elsif name == '$otherghostlist'
        if not @otherghost.empty?
          ghost = @otherghost.sample
          result = ghost[0]
        else
          result = ''
        end
      elsif name == '$sender'
        result = @communicate[0]
      elsif SYSTEM_VARIABLES.include?(name)
        result = ''
      elsif @dict.include?(name)
        result = get(name)
      elsif @constant.include?(name)
        value_type, value = @constant[name]
        if value_type == TYPE_ARRAY
          result = expand(value.get())
        else
          result = value.to_s
        end
      elsif @variable.include?(name)
        value_type, value = @variable[name]
        if value_type == TYPE_ARRAY
          result = expand(value.get())
        else
          result = value.to_s
        end
      else
        result = ''
      end
      return result
    end

    def eval_indexed(name, index)
      name = expand(name)
      index = expand(index)
      begin
        index = Integer(index)
      rescue #except ValueError:
        index = 0
      end
      if name == '$otherghostlist'
        group = []
        for ghost in @otherghost
          group << ghost[0]
        end
      elsif SYSTEM_VARIABLES.include?(name)
        return ''
      elsif @dict.include?(name)
        grouplist = @dict[name]
        group, constraints = grouplist[0]
      elsif @constant.include?(name)
        return ''
      elsif @variable.include?(name)
        value_type, group = @variable[name]
        if value_type != TYPE_ARRAY
          return ''
        end
      else
        return ''
      end
      if index < 0 or index >= group.length
        return ''
      end
      return expand(group[index])
    end

    def eval_assignment(name, operator, value, constant: false)
      name = expand(name)
      value = expand(value)
      if ['+=', '-=', '*=', '/='].include?(operator)
        begin
          operand = Integer(value)
        rescue #except ValueError:
          operand = 0
        end
        if @constant.include?(name)
          value_type, value = @constant[name]
        else
          value_type, value = nil, ''
        end
        if value_type == nil
          if @variable.include?(name)
            value_type, value = @variable[name]
          else
            value_type, value = TYPE_SCHOLAR, ''
          end
        end
        if value_type == TYPE_ARRAY
          return ''
        end
        begin
          value = Integer(value)
        rescue #except ValueError:
          value = 0
        end
        if operator == '+='
          value += operand
        elsif operator == '-='
          value -= operand
        elsif operator == '*='
          value *= operand
        elsif operator == '/=' and operand != 0
          value /= operand
          value = value.to_i
        end
      end
      if constant or @constant.include?(name)
        @constant[name] = [TYPE_SCHOLAR, value]
      else
        @variable[name] = [TYPE_SCHOLAR, value]
      end
      if name == '$_talkinterval'
        reset_random_talk_interval()
      end
      return ''
    end

    def eval_comp_expr(operand1, operator, operand2)
      value1 = expand(operand1)
      value2 = expand(operand2)
      begin
        operand1 = Integer(value1)
        operand2 = Integer(value2)
      rescue #except ValueError:
        operand1 = value1
        operand2 = value2
      end
      if (operator == '==' and operand1 == operand2) or \
        (operator == '!=' and operand1 != operand2) or \
        (operator == '<'  and operand1 <  operand2) or \
        (operator == '<=' and operand1 <= operand2) or \
        (operator == '>'  and operand1 >  operand2) or \
        (operator == '>=' and operand1 >= operand2)
        return 'true'
      end
      return 'false'
    end

    def eval_and_expr(conditions)
      for condition in conditions
        boolean = eval_(condition)
        if boolean.strip() != 'true'
          return 'false'
        end
      end
      return 'true'
    end

    def eval_or_expr(conditions)
      for condition in conditions
        boolean = eval_(condition)
        if boolean.strip() == 'true'
          return 'true'
        end
      end
      return 'false'
    end

    def eval_add_expr(expression)
      value = expand(expression[0])
      begin
        value = Integer(value)
      rescue #except ValueError:
        value = 0
      end
      for i in 1.step(expression.length-1, 2)
        operand = expand(expression[i + 1])
        begin
          operand = Integer(operand)
        rescue #except ValueError:
          operand = 0
        end
        if expression[i] == '+'
          value += operand
        elsif expression[i] == '-'
          value -= operand
        end
      end
      return value.to_s
    end

    def eval_mul_expr(expression)
      value = expand(expression[0])
      begin
        value = Integer(value)
      rescue #except ValueError:
        value = 0
      end
      for i in 1.step(expression.length-1, 2)
        operand = expand(expression[i + 1])
        begin
          operand = Integer(operand)
        rescue #except ValueError:
          operand = 0
        end
        if expression[i] == '*'
          value *= operand
        elsif expression[i] == '/' and operand != 0
          value /= operand
          value = value.to_i
        elsif expression[i] == '%' and operand != 0
          value = value % operand
        end
      end
      return value.to_s
    end

    def eval_pow_expr(expression)
      value = expand(expression[-1])
      begin
        value = Integer(value)
      rescue #except ValueError:
        value = 0
      end
      for i in 1..expression.length-1
        operand = expand(expression[-i - 1])
        begin
          operand = Integer(operand)
        rescue #except ValueError:
          operand = 0
        end
        value = operand**value
      end
      return value.to_s
    end

    def eval_if(condition, then_clause, else_clause)
      boolean = eval_(condition)
      if boolean.strip() == 'true'
        return expand(then_clause)
      else
        return expand(else_clause)
      end
    end

    def eval_calc(expression)
      return expand(expression)
    end

    def eval_function(name, args)
      function = SYSTEM_FUNCTIONS[name]
      if function == nil
        return ''
      end
      return method(function).call(args)
    end

    def is_number(s)
      return (s and s.chars.map {|c| '0123456789'.include?(c) }.all?)
    end

    def split(s)
      buf = []
      i, j = 0, s.length
      while i < j
        if s[i].ord < 0x80
          buf << s[i]
          i += 1
        else
          buf << s[i..i + 1]
          i += 2
        end
      end
      return buf
    end

    def exec_reference(args)
      if args.length != 1
        return ''
      end
      n = expand_args(args[0])
      if '01234567'.include?(n)
        value = @reference[n.to_i]
        if value != nil
          return value.to_s
        end
      end
      return ''
    end

    def exec_random(args)
      if args.length != 1
        return ''
      end
      n = expand_args(args[0])
      begin
        return Array(0..Integer(n)-1).sample.to_s
      rescue #except ValueError:
        return '' # n < 1 or not a number
      end
    end

    def exec_choice(args)
      if args.empty?
        return ''
      end
      return expand_args(args.sample)
    end

    def exec_getvalue(args)
      if args.length != 2
        return ''
      end
      begin
        n = Integer(expand_args(args[1]))
      rescue #except ValueError:
        return ''
      end
      if n < 0
        return ''
      end
      value_list = expand_args(args[0]).split(',', 0)
      begin
        return value_list[n]
      rescue #except IndexError:
        return ''
      end
    end

    def exec_search(args)
      namelist = []
      for arg in args
        name = expand_args(arg)
        if name.strip()
          namelist << name
        end
      end
      if namelist.empty?
        return ''
      end
      keylist = []
      for key in keys() # dict, variable, constant
        break_flag = false
        for name in namelist
          if not key.include?(name)
            break_flag = true
            break
          end
        end
        if not break_flag
          keylist << key
        end
      end
      if keylist.empty?
        return ''
      end
      return eval_variable([[NODE_TEXT, keylist.sample]])
    end

    def keys
      buf = @dict.keys()
      buf |= @variable.keys()
      buf |= @constant.keys()
      return buf
    end

    def exec_backup(args)
      if args.empty?
        save_database()
      end
      return ''
    end

    def exec_getmousemovecount(args)
      if args.length == 2
        side = expand_args(args[0])
        part = expand_args(args[1])
        begin
          key = [Integer(side), part]
        rescue #except ValueError:
          #pass
        else
          if @mouse_move_count.include?(key)
            return @mouse_move_count[key].to_s
          else
            return 0
          end
        end
      end
      return ''
    end

    def exec_resetmousemovecount(args)
      if args.length == 2
        side = expand_args(args[0])
        part = expand_args(args[1])
        begin
          key = [Integer(side), part]
        rescue #except ValueError:
          pass
        else
          @mouse_move_count[key] = 0
        end
      end
      return ''
    end

    def exec_substring(args)
      if args.length != 3
        return ''
      end
      value = expand_args(args[2])
      begin
        count = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if count < 0
        return ''
      end
      value = expand_args(args[1])
      begin
        offset = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if offset < 0
        return ''
      end
      s = expand_args(args[0]).encode(@charset, :invalid => :replace, :undef => :replace)
      return s[offset..offset + count - 1].force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace)
    end

    def exec_substringl(args)
      if args.length != 2
        return ''
      end
      value = expand_args(args[1])
      begin
        count = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if count < 0
        return ''
      end
      s = expand_args(args[0]).encode(@charset, :invalid => :replace, :undef => :replace)
      return s[0..count-1].force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace)
    end

    def exec_substringr(args)
      if args.length != 2
        return ''
      end
      value = expand_args(args[1])
      begin
        count = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if count < 0
        return ''
      end
      s = expand_args(args[0]).encode(@charset, :invalid => :replace, :undef => :replace)
      return s[s.length - count..-1].force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace)
    end

    def exec_substringfirst(args)
      if args.length != 1
        return ''
      end
      buf = expand_args(args[0])
      if buf.empty?
        return ''
      else
        return buf[0]
      end
    end

    def exec_substringlast(args)
      if args.length != 1
        return ''
      end
      buf = expand_args(args[0])
      if buf.empty?
        return ''
      else
        return buf[-1]
      end
    end

    def exec_length(args)
      if args.length != 1
        return ''
      end
      return expand_args(args[0]).encode(@charset, :invalid => :replace, :undef => :replace).length.to_s
    end

    Katakana2hiragana = {
        'ァ' => 'ぁ', 'ア' => 'あ', 'ィ' => 'ぃ', 'イ' => 'い', 'ゥ' => 'ぅ',
        'ウ' => 'う', 'ェ' => 'ぇ', 'エ' => 'え', 'ォ' => 'ぉ', 'オ' => 'お',
        'カ' => 'か', 'ガ' => 'が', 'キ' => 'き', 'ギ' => 'ぎ', 'ク' => 'く',
        'グ' => 'ぐ', 'ケ' => 'け', 'ゲ' => 'げ', 'コ' => 'こ', 'ゴ' => 'ご',
        'サ' => 'さ', 'ザ' => 'ざ', 'シ' => 'し', 'ジ' => 'じ', 'ス' => 'す',
        'ズ' => 'ず', 'セ' => 'せ', 'ゼ' => 'ぜ', 'ソ' => 'そ', 'ゾ' => 'ぞ',
        'タ' => 'た', 'ダ' => 'だ', 'チ' => 'ち', 'ヂ' => 'ぢ', 'ッ' => 'っ',
        'ツ' => 'つ', 'ヅ' => 'づ', 'テ' => 'て', 'デ' => 'で', 'ト' => 'と',
        'ド' => 'ど', 'ナ' => 'な', 'ニ' => 'に', 'ヌ' => 'ぬ', 'ネ' => 'ね',
        'ノ' => 'の', 'ハ' => 'は', 'バ' => 'ば', 'パ' => 'ぱ', 'ヒ' => 'ひ',
        'ビ' => 'び', 'ピ' => 'ぴ', 'フ' => 'ふ', 'ブ' => 'ぶ', 'プ' => 'ぷ',
        'ヘ' => 'へ', 'ベ' => 'べ', 'ペ' => 'ぺ', 'ホ' => 'ほ', 'ボ' => 'ぼ',
        'ポ' => 'ぽ', 'マ' => 'ま', 'ミ' => 'み', 'ム' => 'む', 'メ' => 'め',
        'モ' => 'も', 'ャ' => 'ゃ', 'ヤ' => 'や', 'ュ' => 'ゅ', 'ユ' => 'ゆ',
        'ョ' => 'ょ', 'ヨ' => 'よ', 'ラ' => 'ら', 'リ' => 'り', 'ル' => 'る',
        'レ' => 'れ', 'ロ' => 'ろ', 'ヮ' => 'ゎ', 'ワ' => 'わ', 'ヰ' => 'ゐ',
        'ヱ' => 'ゑ', 'ヲ' => 'を', 'ン' => 'ん', 'ヴ' => 'う゛',
        }

    def exec_hiraganacase(args)
      if args.length != 1
        return ''
      end
      buf = []
      string = expand_args(args[0]).force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace)
      #string = args[0].force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace)
      for c in string.chars
        if Katakana2hiragana.include?(c)
          c = Katakana2hiragana[c]
        else
          #pass
        end
        buf << c
      end
      return buf.join('')
    end

    def exec_isequallastandfirst(args)
      if args.length != 2
        return 'false'
      end
      buf0 = expand_args(args[0])
      buf1 = expand_args(args[1])
      if not buf0.empty? and not buf1.empty? and buf0[-1] == buf1[0]
        return 'true'
      else
        return 'false'
      end
    end

    def exec_append(args)
      if args.length == 2
        name = expand_args(args[0])
        if not name.empty? and name.start_with?('$')
          if @variable.include?(name)
            value_type, value = @variable[name]
          else
            value_type, value = TYPE_SCHOLAR, ''
          end
          if value_type == TYPE_SCHOLAR
            value_type = TYPE_ARRAY
            array = MisakaArray.new(self, name)
            if value != ''
              array.append(value)
            end
            value = array
          end
          member_list = expand_args(args[1]).split(1.chr, 0)
          for member in member_list
            value.append(member)
          end
          @variable[name] = [value_type, value]
        end
      end
      return ''
    end

    def exec_stringexists(args)
      if args.length != 2
        return ''
      end
      name = expand_args(args[0])
      if @variable.include?(name)
        value_type, value = @variable[name]
      else
        value_type, value = TYPE_SCHOLAR, ''
      end
      if value_type == TYPE_SCHOLAR
        return ''
      end
      if value.index(expand_args(args[1])) == nil # value.index(expand_args(args[1])) < 0
        return 'false'
      else
        return 'true'
      end
    end

    def exec_copy(args)
      if args.length != 2
        return ''
      end
      src_name = expand_args(args[0])
      if not (not src_name.empty? and src_name.start_with?('$'))
        return ''
      end
      new_name = expand_args(args[1])
      if not (not new_name.empty? and new_name.start_with?('$'))
        return ''
      end
      source = nil
      if @dict.include?(src_name)
        grouplist = @dict[src_name]
        source, conditions = grouplist[0]
      elsif @variable.include?(src_name)
        value_type, value = @variable[src_name]
        if value_type == TYPE_ARRAY
          source = value
        end
      end
      if source == nil
        value = MisakaArray.new(self, new_name)
      else
        value = source.copy(new_name)
      end
      @variable[new_name] = [TYPE_ARRAY, value]
      return ''
    end

    def exec_pop(args)
      if args.length == 1
        name = expand_args(args[0])
        if @variable.include?(name)
          value_type, value = @variable[name]
        else
          value_type, value = TYPE_SCHOLAR, ''
        end
        if value_type == TYPE_ARRAY
          return expand(value.pop())
        end
      end
      return ''
    end

    def exec_popmatchl(args)
      if args.length == 2
        name = expand_args(args[0])
        if @variable.include?(name)
          value_type, value = @variable[name]
        else
          value_type, value = TYPE_SCHOLAR, ''
        end
        if value_type == TYPE_ARRAY
          return expand(value.popmatchl(expand_args(args[1])))
        end
      end
      return ''
    end

    def exec_index(args)
      if args.length == 2
        pos = expand_args(args[1]).find(expand_args(args[0]))
        if pos > 0
          s = expand_args(args[0])[pos]
          pos = s.encode(@charset, :invalid => :replace, :undef => :replace).length
        end
        return pos.to_s
      end
      return ''
    end

    def exec_insentence(args)
      if args.empty?
        return ''
      end
      s = expand_args(args[0])
      for i in 1..args.length-1
        if not s.include?(expand_args(args[i]))
          return 'false'
        end
      end
      return 'true'
    end

    def exec_substringw(args)
      if args.length != 3
        return ''
      end
      value = expand_args(args[2])
      begin
        count = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if count < 0
        return ''
      end
      value = expand_args(args[1])
      begin
        offset = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if offset < 0
        return ''
      end
      buf = expand_args(args[0])
      return buf[offset..offset + count - 1]
    end

    def exec_substringwl(args)
      if args.length != 2
        return ''
      end
      value = expand_args(args[1])
      begin
        count = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if count < 0
        return ''
      end
      buf = expand_args(args[0])
      return buf[0..count-1]
    end

    def exec_substringwr(args)
      if args.length != 2
        return ''
      end
      value = expand_args(args[1])
      begin
        count = Integer(value)
      rescue #except ValueError:
        return ''
      end
      if count < 0
        return ''
      end
      buf = expand_args(args[0])
      return buf[buf.length - count..-1]
    end

    Prefixes = ['さん', 'ちゃん', '君', 'くん', '様', 'さま', '氏', '先生']

    def exec_adjustprefix(args)
      if args.length != 2
        return ''
      end
      s = expand_args(args[0])
      for prefix in Prefixes
        if s.end_with?(prefix)
          s = [s[0..-prefix.length-1], expand_args(args[1])].join('')
          break
        end
      end
      return s
    end

    def exec_count(args)
      if args.length != 1
        return ''
      end
      name = expand_args(args[0])
      begin
        value_type, value = @variable[name]
        if value_type == TYPE_SCHOLAR
          return '1'
        end
        return value.length.to_s
      rescue #except KeyError:
        return '-1'
      end
    end

    def exec_inlastsentence(args)
      if args.empty?
        return ''
      end
      s = @communicate[1]
      for i in 1..args.length-1
        if not s.include?(expand_args(args[i]))
          return 'false'
        end
      end
      return 'true'
    end

    def saori(args)
      saori_statuscode = ''
      saori_header = []
      saori_value = {}
      saori_protocol = ''
      req = ["EXECUTE SAORI/1.0\r\n",
             "Sender: MISAKA\r\n",
             "SecurityLevel: local\r\n",
             "Charset: ",
             @charset.encode(@charset, :invalid => :replace, :undef => :replace),
             "\r\n"].join('')
      for i in 1..args.length-1
        req = [req,
               'Argument', i.to_s.encode(@charset, :invalid => :replace, :undef => :replace), ': ', 
               expand_args(args[i]).encode(@charset, :invalid => :replace, :undef => :replace),
               "\r\n"].join('')
      end
      req = [req, "\r\n"].join('')
      response = @saori_library.request(expand_args(args[0]), req)
      header = response.split(/\r?\n/, 0)
      if not header.empty?
        line = header.shift
        line = line.force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace).strip()
        if line.include?(' ')
          saori_protocol, saori_statuscode = line.split(' ', 2)
          saori_protocol.strip!
          saori_statuscode.strip!
        end
        for line in header
          line = line.force_encoding(@charset).encode('utf-8', :invalid => :replace, :undef => :replace).strip()
          if line.empty?
            next
          end
          if not line.include?(':')
            next
          end
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          if not key.empty?
            saori_header << key
            saori_value[key] = value
          end
        end
      end
      if saori_value.include?('Result')
        return saori_value['Result']
      else
        return ''
      end
    end

    def load_saori(args)
      if args.empty?
        return ''
      end
      result = @saori_library.load(expand_args(args[0]),
                                   @misaka_dir)
      if result == 0
        return ''
      else
        result.to_s
      end
    end

    def unload_saori(args)
      if args.empty?
        return ''
      end
      result = @saori_library.unload(:name => expand_args(args[0]))
      if result == 0
        return ''
      else
        return result.to_s
      end
    end

    def exec_isghostexists(args)
      result = 'false'
      if args.length != 1
        if @otherghost.length > 0
          result = 'true'
          @variable['$to'] = [TYPE_SCHOLAR,
                              @otherghost.sample[0]]
        end
      else
        for ghost in @otherghost
          if ghost[0] == expand_args(args[0])
            result = 'true'
            break
          end
        end
      end
      return result
    end
  end

  SYSTEM_FUNCTIONS = {
        '$reference' =>           'exec_reference',
        '$random' =>              'exec_random',
        '$choice' =>              'exec_choice',
        '$getvalue' =>            'exec_getvalue',
        '$inlastsentence' =>      'exec_inlastsentence',
        '$isghostexists' =>       'exec_isghostexists',
        '$search' =>              'exec_search',
        '$backup' =>              'exec_backup',
        '$getmousemovecount' =>   'exec_getmousemovecount',
        '$resetmousemovecount' => 'exec_resetmousemovecount',
        '$substring' =>           'exec_substring',
        '$substringl' =>          'exec_substringl',
        '$substringr' =>          'exec_substringr',
        '$substringfirst' =>      'exec_substringfirst',
        '$substringlast' =>       'exec_substringlast',
        '$length' =>              'exec_length',
        '$hiraganacase' =>        'exec_hiraganacase',
        '$isequallastandfirst' => 'exec_isequallastandfirst',
        '$append' =>              'exec_append',
        '$stringexists' =>        'exec_stringexists',
        '$copy' =>                'exec_copy',
        '$pop' =>                 'exec_pop',
        '$popmatchl' =>           'exec_popmatchl',
        '$index' =>               'exec_index',
        '$insentence' =>          'exec_insentence',
        '$substringw' =>          'exec_substringw',
        '$substringwl' =>         'exec_substringwl',
        '$substringwr' =>         'exec_substringwr',
        '$adjustprefix' =>        'exec_adjustprefix',
        '$count' =>               'exec_count',
        '$saori' =>               'saori',
        '$loadsaori' =>           'load_saori',
        '$unloadsaori' =>         'unload_saori',
        }


  class SaoriLibrary
            
    def initialize(saori, top_dir)
      @saori_list = {}
      @saori = saori
    end

    def load(name, top_dir)
      result = 0
      head, name = File.split(name.gsub('\\', '/')) # XXX: don't encode here
      top_dir = File.join(top_dir, head)
      if @saori != nil and not @saori_list.include?(name)
        module_ = @saori.request(name)
        if module_ != nil
          @saori_list[name] = module_
        end
      end
      if @saori_list.include?(name)
        result = @saori_list[name].load(:dir => top_dir)
      end
      return result
    end

    def unload(name: nil)
      if name != nil
        name = File.split(name.gsub('\\', '/'))[-1] # XXX: don't encode here
        if @saori_list.include?(name)
          @saori_list[name].unload()
          @saori_list.delete(name)
        end
      else
        for key in @saori_list.keys
          @saori_list[key].unload()
        end
      end
      return nil
    end

    def request(name, req)
      result = '' # FIXME
      name = File.split(name.gsub('\\', '/'))[-1] # XXX: don't encode here
      if not name.empty? and @saori_list.include?(name)
        result = @saori_list[name].request(req)
      end
      return result
    end
  end
end                
