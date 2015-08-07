# -*- coding: utf-8 -*-
#
#  aya5.rb - an aya.dll(Ver.5) compatible Shiori module for ninix
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#
#

# TODO:
# - 文字列内埋め込み要素の展開の動作が非互換.
# - システム関数:
# - たくさん.

require_relative "../home"
require_relative "../logging"


module Aya5

  class AyaError < StandardError # XXX
    #pass
  end

  def self.encrypt_char(char)
    c = char[0].ord
    j = 0
    while j < 3
      msb = c & 0x80
      c <<= 1
      c &= 0xff
      if msb != 0
        c |= 0x01
      else
        c &= 0xfe
      end
      j += 1
    end
    c ^= 0xd2
    return c.chr
  end

  def self.decrypt_char(char)
    c = char[0].ord
    c ^= 0xd2
    j = 0
    while j < 3
      lsb = c & 0x01
      c >>= 1
      if lsb != 0
        c |= 0x80
      else
        c &= 0x7f
      end
      j += 1
    end
    return c.chr
  end

  def self.decrypt_readline(f)
    line = ''
    while true
      c = f.read(1)
      if c == ''
        break
      end
      line = [line, Aya5.decrypt_char(c)].join('')
      if line.end_with?(10.chr) or \
        line.end_with?(0xda.chr)
        break
      end
    end
    return line
  end

  def self.find_not_quoted(line, token)
    position = 0
    while true
      pos_new = line.index(token, position)
      if not pos_new
        pos_new = -1
        break
      elsif pos_new == 0
        break
      end
      position = line.index('"', position)
      if position and 0 <= position and position < pos_new
        position += 1
        while position < line.length - 1
          if line[position] == '"'
            position += 1
            break
          else
            position += 1
            next
          end
        end
      else
        break
      end
    end
    return pos_new
  end

  def self.find_comment(line)
    if line.start_with?("//")
      return 0, line.length
    end
    start = line.length # not line.length - 1
    end_ = -1
    for token in ["//", "/*"]
      pos_new = Aya5.find_not_quoted(line, token)
      if 0 <= pos_new and pos_new < start
        start = pos_new
        if token == "/*"
          end_ = Aya5.find_not_quoted(line, "*/")
          if end_ >= 0
            end_ += 2
          end
        else
          end_ = line.length
        end
      end
    end
    if start == line.length
      start = -1
    end
    return start, end_
  end

  def self.get_aya_version(filelist)
    if not filelist
      return 0
    end
    dic_files = filelist
    for filename in dic_files
      if filename.downcase.end_with?('_shiori3.dic') # XXX
        open(filename, 'rb', :encoding => 'CP932') do |f|
          for line in f
            begin
              line = line.encode("UTF-8", :invalid => :replace, :undef => :replace)
              v4 = line.index('for 文 version 4')
              v5 = line.index('for AYA5')
              if v4 and v4 > 0
                return 4
              elsif v5 and v5 > 0
                return 5
              end
            rescue
              return 5
            end
          end
        end
      end
    end
    return 3
  end

  def self.find_dict(aya_dir, f)
    comment = 0
    dic_files = []
    for line in f
      line = line.encode("UTF-8", :invalid => :replace, :undef => :replace)
      if comment != 0
        end_ = Aya5.find_not_quoted(line, '*/')
        if end_ < 0
          next
        else
          line = line[end_ + 2..-1]
          comment = 0
        end
      end
      while true
        start, end_ = Aya5.find_comment(line)
        if start < 0
          break
        end
        if start == 0
          line = ""
        end
        if end_ < 0
          comment = 1
          line = line[0..start-1]
          break
        end
        line = [line[0..start-1], line[end_..-1]].join(' ')
      end
      line = line.strip()
      if line.empty?
        next
      end
      if not line.include?(',')
        next
      end
      key, value = line.split(',', 2)
      key.strip!
      value.strip!
      if key == 'dic'
        filename = Home.get_normalized_path(value)
        path = File.join(aya_dir, filename)
        dic_files << path
      end
    end
    return dic_files
  end

  def self.check_version(top_dir, dll_name)
    filename = nil
    if File.file?(File.join(top_dir, 'aya.txt'))
      filename = File.join(top_dir, 'aya.txt')
    elsif File.file?(File.join(top_dir, 'yaya.txt'))
      return 6 # XXX: YAYA
    elsif dll_name != nil and \
         File.file?(File.join(top_dir, [dll_name[0..-4], 'txt'].join('')))
      filename = File.join(top_dir, [dll_name[0..-4], 'txt'].join(''))
    end
    version = 0
    if filename != nil
      open(filename, :encoding => 'CP932') do |f|
        version = Aya5.get_aya_version(Aya5.find_dict(top_dir, f))
      end
    end
    return version
  end


  class Shiori
    attr_reader :charset

    def initialize(dll_name)
      @dll_name = dll_name
      if dll_name != nil
        @__AYA_TXT = [dll_name[0..-4], 'txt'].join('')
        @__DBNAME = [dll_name[0..-5], '_variable.cfg'].join('')
      else
        @__AYA_TXT = 'aya5.txt'
        @__DBNAME = 'aya5_variable.cfg'
      end
      @saori = nil
      @dic_files = []
    end

    def use_saori(saori)
      @saori = saori
    end

    def find(top_dir, dll_name)
      return 0 ### FIXME
      result = 0
      version = Aya5.check_version(top_dir, dll_name)
      if version == 5
        result = 200
      elsif version == 6
        @__AYA_TXT = 'yaya.txt'
        @__DBNAME = 'yaya_variable.cfg'
        result = 100
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: AYA5 compatible module for ninix\n" \
        "        Copyright (C) 2002-2015 by Shyouzou Sugitani\n" \
        "        Copyright (C) 2002, 2003 by MATSUMURA Namihiko")
    end

    def reset
      @boot_time = Time.new
      @aitalk = 0
      @dic_files = []
      @dic = AyaDictionary.new(self)
      @global_namespace = AyaGlobalNamespace.new(self)
      @system_functions = AyaSystemFunctions.new(self)
      @logfile = nil
      @filelist = {}
    end

    def load(dir: nil)
      @aya_dir = dir
      @dbpath = File.join(@aya_dir, @__DBNAME)
      @saori_library = AyaSaoriLibrary.new(@saori, @aya_dir)
      reset()
      begin
        path = File.join(@aya_dir, @__AYA_TXT)
        open(path, :encoding => 'CP932') do |aya_txt|
          load_aya_txt(aya_txt)
        end
      rescue #except IOError:
        Logging::Logging.debug('cannot read aya.txt')
        return 0
      rescue #except AyaError as error:
        Logging::Logging.debug(error)
        return 0
      end
      @global_namespace.load_database(self)
      # default setting
      if not @global_namespace.exists('log')
        @global_namespace.put('log', '')
      end
      for path in @dic_files
        basename = File.basename(path, '.*')
        ext = File.extname(path)
        ext = ext.downcase
        if ext == '.ayc'
          encrypted = true
        else
          encrypted = false
        end
        begin
          open(path, 'rb') do |dicfile|
            @dic.load(dicfile, encrypted)
          end
        rescue
          Logging::Logging.debug('cannot read ' + path.to_s)
          next
        end
      end    
      func = @dic.get_function('load')
      if func
        func.call([@aya_dir.gsub('/', "\\")])
      end
      return 1
    end

    def load_aya_txt(f)
      comment = 0
      @charset = 'CP932' # default
      for line in f
        line = line.force_encoding(@charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
        if comment != 0
          end_ = Aya5.find_not_quoted(line, '*/')
          if end_ < 0
            next
          else
            line = line[end_ + 2..-1]
            comment = 0
          end
        end
        while true
          start, end_ = Aya5.find_comment(line)
          if start < 0
            break
          end
          if start == 0
            line = ""
          end
          if end_ < 0
            comment = 1
            line = line[0..start-1]
            break
          end
          line = [line[0..start-1], line[end_..-1]].join(' ')
        end
        line = line.strip()
        if line.empty?
          next
        end
        if not line.include?(',')
          next
        end
        key, value = line.split(',', 2)
        key.strip!
        value.strip!
        evaluate_config(key, value)
      end
    end

    def evaluate_config(key, value)
      if key == 'charset'
        if ['Shift_JIS', 'ShiftJIS', 'SJIS'].include?(value)
          @charset = 'CP932'
        elsif value == 'UTF-8'
          @charset = 'UTF-8'
        else # default and error
          @charset = 'CP932'
        end
      elsif key == 'dic'
        filename = Home.get_normalized_path(value)
        path = File.join(@aya_dir, filename)
        @dic_files << path
      elsif key == 'msglang'
        #pass ## FIXME
      elsif key == 'log'
        #assert value.is_a?(String)
        filename = value
        path = File.join(@aya_dir, filename)
        begin
          f = open(path, 'w')
        rescue
          Logging::Logging.debug('cannnot open ' + path)
        else
          if @logfile
            @logfile.close()
          end
          @logfile = f
          @global_namespace.put('log', value.to_s)
        end
      elsif key == 'iolog'
        #pass ## FIXME
      elsif key == 'fncdepth'
        #pass ## FIXME
      end
    end

    def get_dictionary
      return @dic
    end

    def get_ghost_dir
      return @aya_dir
    end

    def get_global_namespace
      return @global_namespace
    end

    def get_system_functions
      return @system_functions
    end

    def get_boot_time
      return @boot_time
    end

    def unload
      func = @dic.get_function('unload')
      if func
        func.call([])
      end
      @global_namespace.save_database()
      @saori_library.unload()
      if @logfile != nil
        @logfile.close()
      end
      for key in @filelist.keys()
        @filelist[key].close()
      end
    end

    # SHIORI API
    def request(req_string)
      result = ''
      func = @dic.get_function('request')
      if func
        req = req_string.force_encoding(@charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
        result = func.call([req])
      end
      if result == nil
        result = ''
      end
      return result.encode(@charset)
    end
  end


  class AyaDictionary
    attr_reader :aya

    def initialize(aya)
      @aya = aya
      @functions = {}
      @global_macro = {}
    end

    def get_function(name)
      if @functions.has_key?(name)
        return @functions[name]
      else
        return nil
      end
    end

    def load(f, encrypted)
      all_lines = []
      local_macro = {}
      logical_line = ''
      comment = 0
      while true
        if encrypted
          line = Aya5.decrypt_readline(f)
        else
          line = f.gets
        end
        if not line
          break # EOF
        end
        line = line.force_encoding(@aya.charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
        if comment != 0
          end_ = Aya5.find_not_quoted(line, '*/')
          if end_ < 0
            next
          else
            line = line[end_ + 2..-1]
            comment = 0
          end
        end
        line = line.strip()
        if line.empty?
          next
        end
        if line.end_with?('/') and \
          not line.end_with?('*/') and not line.end_with?('//')
          logical_line = [logical_line, line[0..-2]].join('')
        else
          logical_line = [logical_line, line].join('')
          while true
            start, end_ = Aya5.find_comment(logical_line)
            if start < 0
              break
            end
            if start == 0
              logical_line = ""
            end
            if end_ < 0
              comment = 1
              logical_line = logical_line[0..start-1]
              break
            end
            logical_line = [logical_line[0..start-1], ' ', logical_line[end_..-1]].join('')
          end
          logical_line = logical_line.strip()
          if not logical_line
            next
          end
          buf = logical_line
          # preprosess
          if buf.start_with?('#')
            buf = buf[1..-1].strip()
            for (tag, target) in [['define', local_macro],
                                  ['globaldefine', @global_macro]]
              if buf.start_with?(tag)
                buf = buf[tag.length..-1].strip()
                i = 0
                while i < buf.length
                  if buf[i] == " " or buf[i] == "\t" or \
                    buf[i] == "　"
                    key = buf[0..i-1].strip()
                    target[key] = buf[i..-1].strip()
                    break
                  end
                  i += 1
                end
                break
              end
            end
            logical_line = '' # reset
            next
          end
          for macro in [local_macro, @global_macro]
            logical_line = preprocess(macro, logical_line)
          end
          # multi statement
          list_lines = split_line(logical_line.strip())
          if not list_lines.empty?
            all_lines.concat(list_lines)
          end
          logical_line = '' # reset
        end
      end
      evaluate_lines(all_lines, File.split(f.path)[1])
    end

    def split_line(line)
      lines = []
      while true
        if not line or line.empty?
          break
        end
        pos = line.length # not line.length - 1
        token = ''
        for x in ['{', '}', ';']
          pos_new = Aya5.find_not_quoted(line, x)
          if 0 <= pos_new and pos_new < pos
            pos = pos_new
            token = x
          end
        end
        if pos != 0
          new = line[0..pos-1].strip()
        else # '{' or '}'
          new = ""
        end
        line = line[pos + token.length..-1].strip()
        if not new.empty?
          lines << new
        end
        if not ['', ';'].include?(token)
          lines << token
        end
      end
      return lines
    end

    def preprocess(macro, line)
      for key in macro.keys
        value = macro[key]
        line = line.gsub(key, value)
      end
      return line
    end

    SPECIAL_CHARS = [']', '(', ')', '[', '+', '-', '*', '/', '=',
                     ':', ';', '!', '{', '}', '%', '&', '#', '"',
                     '<', '>', ',', '?']

    def evaluate_lines(lines, file_name)
      prev = nil
      name = nil
      function = []
      option = nil
      block_nest = 0
      for i in 0..lines.length-1
        line = lines[i]
        if line == '{'
          if name != nil
            if block_nest > 0
              function << line
            end
            block_nest += 1
          else
            if prev == nil
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "{" at ' \
                                                      'the top of file')
            else
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "{" at ' \
                                                      'the bottom of function "' + prev.to_s + '"')
            end
          end
        elsif line == '}'
          if name != nil
            block_nest -= 1
            if block_nest > 0
              function << line
            elsif block_nest == 0
              @functions[name] = AyaFunction.new(self, name,
                                                 function, option)
              # reset
              prev = name
              name = nil
              function = []
              option = nil
            end
          else
            if prev == nil
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "}" at ' \
                                                      'the top of file')
            else
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "}" at ' \
                                                      'the bottom of function "' + prev.to_s + '"')
            end
            block_nest = 0
          end
        elsif name == nil
          if line.include?(':')
            name, option = line.split(':', 2)
            name.strip!
            option.strip!
          else
            name = line
          end
          for char in SPECIAL_CHARS
            if name.include?(char)
              Logging::Logging.debug(
                'illegal function name "' + name.to_s + '" in ' + file_name.to_s)
            end
          end
          function = []
        else
          if name != nil and block_nest > 0
            function << line
          else
            Logging::Logging.debug('syntax error in ' + file_name + ': ' + line)
          end
        end
      end
    end
  end

  class AyaFunction

    TYPE_INT = 10
    TYPE_FLOAT = 11
    TYPE_DECISION = 12
    TYPE_RETURN = 13
    TYPE_BLOCK = 14
    TYPE_SUBSTITUTION = 15
    TYPE_INC = 16
    TYPE_DEC = 17
    TYPE_IF = 18
    TYPE_WHILE = 19
    TYPE_FOR = 20
    TYPE_BREAK = 21
    TYPE_CONTINUE = 22
    TYPE_SWITCH = 23
    TYPE_CASE = 24
    TYPE_STRING_LITERAL = 25
    TYPE_STRING = 26
    TYPE_OPERATOR = 27
    TYPE_STATEMENT = 28
    TYPE_CONDITION = 29
    TYPE_SYSTEM_FUNCTION = 30
    TYPE_FUNCTION = 31
    TYPE_ARRAY_POINTER = 32
    TYPE_ARRAY = 33
    TYPE_VARIABLE_POINTER = 34
    TYPE_VARIABLE = 35
    TYPE_TOKEN = 36
    TYPE_NEW_ARRAY = 37
    TYPE_FOREACH = 38
    TYPE_PARALLEL = 39
    TYPE_FORMULA = 40
    CODE_NONE = 50
    CODE_RETURN = 51
    CODE_BREAK = 52
    CODE_CONTINUE = 53
    Re_f = Regexp.new('^[-+]?\d+(\.\d*)$')
    Re_d = Regexp.new('^[-+]?\d+$')
    Re_b = Regexp.new('^[-+]?0[bB][01]+$')
    Re_x = Regexp.new('^[-+]?0[xX][\dA-Fa-f]+$')
    Re_if = Regexp.new('^if\s')
    Re_others = Regexp.new('^others\s')
    Re_elseif = Regexp.new('^elseif\s')
    Re_while = Regexp.new('^while\s')
    Re_for = Regexp.new('^for\s')
    Re_foreach = Regexp.new('^foreach\s')
    Re_switch = Regexp.new('^switch\s')
    Re_case = Regexp.new('^case\s')
    Re_when = Regexp.new('^when\s')
    Re_parallel = Regexp.new('^parallel\s')
    SPECIAL_CHARS = [']', '(', ')', '[', '+', '-', '*', '/', '=',
                     ':', ';', '!', '{', '}', '%', '&', '#', '"',
                     '<', '>', ',', '?']

    def initialize(dic, name, lines, option)
      @dic = dic
      @name = name
      @status = CODE_NONE
      @lines = parse(lines)
      if option == 'nonoverlap'
        @nonoverlap = [[], [], []]
      else
        @nonoverlap = nil
      end
      if option == 'sequential'
        @sequential = [[], []]
      else
        @sequential = nil
      end
      ## FIXME: void, array
    end

    def parse(lines)
      result = []
      i = 0
      while i < lines.length
        line = lines[i]
        if line == '--'
          result << [TYPE_DECISION, []]
        elsif line == 'return'
          result << [TYPE_RETURN, []]
        elsif line == 'break'
          result << [TYPE_BREAK, []]
        elsif line == 'continue'
          result << [TYPE_CONTINUE, []]
        elsif line == '{'
          inner_func = []
          i, inner_func = get_block(lines, i)
          result << [TYPE_BLOCK, parse(inner_func)]
        elsif Re_if.match(line)
          inner_blocks = []
          while true
            current_line = lines[i]
            if Re_if.match(current_line)
              condition = parse_(current_line[2..-1].strip())
            elsif Re_elseif.match(current_line)
              condition = parse_(current_line[6..-1].strip())
            else
              condition = [TYPE_CONDITION, nil]
            end
            inner_block = []
            i, inner_block = get_block(lines, i + 1)
            if condition == nil
              inner_blocks = []
              break
            end
            entry = []
            entry << condition
            entry << parse(inner_block)
            inner_blocks << entry
            if i + 1 >= lines.length
              break
            end
            next_line = lines[i + 1]
            if not Re_elseif.match(next_line) and \
              next_line != 'else'
              break
            end
            i = i + 1
          end
          if not inner_blocks.empty?
            result << [TYPE_IF, inner_blocks]
          end
        elsif Re_while.match(line)
          condition = parse_(line[5..-1].strip())
          inner_block = []
          i, inner_block = get_block(lines, i + 1)
          result << [TYPE_WHILE,
                     [condition, parse(inner_block)]]
        elsif Re_for.match(line)
          init = parse([line[3..-1].strip()]) ## FIXME(?)
          condition = parse_(lines[i + 1])
          reset = parse([lines[i + 2]]) ## FIXME(?)
          inner_block = []                
          i, inner_block = get_block(lines, i + 3)
          if condition != nil
            result << [TYPE_FOR,
                           [[init, condition, reset],
                            parse(inner_block)]]
          end
        elsif Re_foreach.match(line)
          name = line[7..-1].strip()
          var = lines[i + 1]
          i, inner_block = get_block(lines, i + 2)
          result << [TYPE_FOREACH,
                         [[name, var], parse(inner_block)]]
        elsif Re_switch.match(line)
          index = parse_(line[6..-1].strip())
          inner_block = []
          i, inner_block = get_block(lines, i + 1)
          result << [TYPE_SWITCH,
                     [index, parse(inner_block)]]
        elsif Re_case.match(line)
          left = parse_(line[4..-1].strip())
          i, block = get_block(lines, i + 1)
          inner_blocks = []
          j = 0
          while true
            current_line = block[j]
            if Re_when.match(current_line)
              right = current_line[4..-1].strip()
            else # 'others'
              right = nil
            end
            inner_block = []
            j, inner_block = get_block(block, j + 1)
            if right != nil
              argument = AyaArgument.new(right)
              while argument.has_more_tokens()
                entry = []
                right = argument.next_token()
                tokens = AyaStatement.new(right).tokens
                if ['-', '+'].include?(tokens[0])
                  value_min = parse_statement([tokens.shift,
                                               tokens.shift]) ## FIXME: parse_
                else
                  value_min = parse_statement([tokens.shift]) ## FIXME: parse_
                end
                value_max = value_min
                if not tokens.empty?
                  if tokens[0] != '-'
                    Logging::Logging.debug(
                      'syntax error in function ' \
                      '"' + @name.to_s + '": when ' + right.to_s)
                    next
                  else
                    tokens.shift
                  end
                  if tokens.length > 2 or \
                    (tokens.length == 2 and \
                     not ['-', '+'].include?(tokens[0]))
                    Logging::Logging.debug(
                      'syntax error in function ' \
                      '"' + @name + '": when ' + right.to_s)
                    next
                  else
                    value_max = parse_statement(tokens) ## FIXME: parse_
                  end
                end
                entry << [value_min, value_max]
                entry << parse(inner_block)
                inner_blocks << entry
              end
            else
              entry = []
              entry << right
              entry << parse(inner_block)
              inner_blocks << entry
            end
            if j + 1 == block.length
              break
            end
            next_line = block[j + 1]
            if not Re_when.match(next_line) and \
              next_line != 'others'
              break
            end
            j += 1
          end
          result << [TYPE_CASE, [left, inner_blocks]]
        elsif Re_parallel.match(line) ## FIXME
          #pass
        else
          result << [TYPE_FORMULA, parse_(line)] ## FIXME
        end
        i += 1
      end
      result << [TYPE_DECISION, []]
      return result
    end

    def find_close_(token_open, tokens, position)
      nest = 0
      current = position
      if token_open == '['
        token_close = ']'
      elsif token_open == '('
        token_close = ')'
      end
      while tokens[current..-1].count(token_close) > 0
        pos_new = tokens[current..-1].index(token_close)
        pos_new += current
        if pos_new == 0
          break
        end
        nest = tokens[position..pos_new-1].count(token_open) - tokens[position..pos_new-1].count(token_close) # - 1
        if nest > 0
          current = pos_new + 1
        else
          current = pos_new
          break
        end
      end
      return current
    end

    def iter_position(tokens, ope_list, reverse=0)
      position = 0
      len_tokens = tokens.length
      result = []
      while true
        new_pos = len_tokens
        if reverse != 0
          tokens.reverse()
        end
        for ope in ope_list
          if tokens[position..-1].include?(ope)
            temp_pos = tokens[position..-1].index(ope)
            temp_pos += position
            new_pos = [new_pos, temp_pos].min
          end
        end
        if reverse != 0
          tokens.reverse()
        end
        position = new_pos
        if position >= len_tokens
          break
        else
          if reverse != 0
            result <<  (len_tokens - position)
          else
            result << position
          end
        end
        position += 1
      end
      return result
    end

    def find_position(tokens, ope_list, position, reverse=0)
      len_tokens = tokens.length
      new_pos = len_tokens
      if reverse != 0
        tokens.reverse()
      end
      for ope in ope_list
        if tokens[position..-1].include?(ope)
          temp_pos = tokens[position..-1].index(ope)
          temp_pos += position
          new_pos = [new_pos, temp_pos].min
        end
      end
      if reverse != 0
        tokens.reverse()
      end
      position = new_pos
      if position >= len_tokens
        return -1
      else
        if reverse != 0
          return len_tokens - 1 - position
        else
          return position
        end
      end
    end

    def get_left_(tokens, position)
      position -= 1
      left = tokens[position]
      tokens.delete_at(position)
      if left.is_a?(String) # not processed
        left = new_parse([left])
      end
      return left
    end

    def get_right_(tokens, position)
      right = tokens[position]
      tokens.delete_at(position)
      if right.is_a?(String) # not processed
        if ['-', '+'].include?(right)
          tmp_token = tokens[position]
          tokens.delete_at(position)
          right = new_parse([right, tmp_token])
        else
          right = new_parse([right])
        end
      end
      return right
    end

    def new_parse(tokens) ## FIXME
      if tokens.length == 0 ## FIXME
        return []
      end
      position = find_position(tokens, ['(', '['], 0)
      while position >= 0
        pos_end = find_close_(tokens[position], tokens, position + 1)
        temp = []
        token_open = tokens[position] # open
        tokens.delete_at(position)
        for i in 0..pos_end - position - 2
          temp << tokens[position]
          tokens.delete_at(position)
        end
        tokens.delete_at(position) # close
        if token_open == '[' # array
          name = tokens[position - 1]
          tokens.delete_at(position - 1)
          tokens.insert(position - 1, [TYPE_ARRAY,
                                       [name, [TYPE_FORMULA, new_parse(temp)]]])
        else
          ope_list = ['!', '++', '--', '*', '/', '%', '+', '-', '&',
                      '==', '!=', '>=', '<=', '>', '<', '_in_', '!_in_',
                      '&&', '||', '=', ':=',
                      '+=', '-=', '*=', '/=', '%=',
                      '+:=', '-:=', '*:=', '/:=', '%:=', ',=', ','] ## FIXME
          if position == 0 or \
            ope_list.include?(tokens[position - 1]) # FORMULA
            tokens.insert(position, [TYPE_FORMULA,
                                     new_parse(temp)])
          else # should be function
            name = tokens[position - 1]
            tokens.delete_at(position - 1)
            if @dic.aya.get_system_functions().exists(name)
              tokens.insert(position - 1, [TYPE_SYSTEM_FUNCTION,
                                           [name,
                                            [new_parse(temp)]]]) ## CHECK: arguments
            else
              tokens.insert(position - 1, [TYPE_FUNCTION,
                                           [name,
                                            [new_parse(temp)]]]) ## CHECK: arguments
            end
          end
        end
        position = find_position(tokens, ['(', '['], 0)
      end
      for position in iter_position(tokens, ['!'])
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        tokens.insert(position, [TYPE_CONDITION,
                                 [nil, [TYPE_OPERATOR, '!'], right]])
      end
      for position in iter_position(tokens, ['++', '--'])
        if tokens[position] == '++'
          type_ = TYPE_INC
        else
          type_ = TYPE_DEC
        end
        tokens.delete_at(position)
        var = tokens[position - 1]
        tokens.delete_at(position - 1)
        if var.is_a?(String) # not processed
          right = new_parse([var]) ## FIXME
        end
        tokens.insert(position - 1, [type_, var])
      end
      position = find_position(tokens, ['*', '/', '%'], 0, reverse=1)
      while position >= 0
        ope = [TYPE_OPERATOR, tokens[position]]
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        left = get_left_(tokens, position)
        tokens.insert(position - 1, [TYPE_STATEMENT, left, ope, right])
        position = find_position(tokens, ['*', '/', '%'], 0, reverse=1)
      end
      position = 0
      position = find_position(tokens, ['+', '-'], position)
      while position >= 0
        ope = [TYPE_OPERATOR, tokens[position]]
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        ope_list = ['!_in_', '_in_',
                    '+:=', '-:=', '*:=', '/:=', '%:=',
                    ':=', '+=', '-=', '*=', '/=', '%=', '<=',
                    '>=', '==', '!=', '&&', '||', ',=', '++', '--',
                    ',', '=', '!', '+', '-', '/', '*', '%', '&']
        if position == 0 or ope_list.include?(tokens[position - 1])
          left = [TYPE_INT, 0]
          tokens.insert(position, [TYPE_STATEMENT, left, ope, right])
        else
          left = get_left_(tokens, position)
          tokens.insert(position - 1, [TYPE_STATEMENT, left, ope, right])
        end
        position = find_position(tokens, ['+', '-'], position)
      end
      for position in iter_position(tokens, ['&'])
        type_ = tokens[position + 1][0]
        var_ = tokens[position + 1][1]
        tokens.delete_at(position)
        tokens.delete_at(position) # +1
        if type_ == TYPE_ARRAY
          tokens.insert(position, [TYPE_ARRAY_POINTER, var_])
        elsif type_ == TYPE_VARIABLE
          tokens.insert(position, [TYPE_VARIABLE_POINTER, var_])
        elsif type_ == TYPE_TOKEN
          tokens.insert(position, [TYPE_VARIABLE_POINTER,
                                   [var_, nil]])
        else
          Logging::Logging.debug(
            'syntax error in function "' + @name.to_s + '": ' \
            'illegal argument "' + tokens.to_s + '"')
        end
      end
      position = find_position(tokens, ['==', '!=', '>=', '<=', '>', '<', '_in_', '!_in_'], 0, reverse=1)
      while position >= 0
        ope = [TYPE_OPERATOR, tokens[position]]
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        left = get_left_(tokens, position)
        tokens.insert(position - 1, [TYPE_CONDITION, [left, ope, right]])
        position = find_position(tokens, ['==', '!=', '>=', '<=', '>', '<', '_in_', '!_in_'], 0, reverse=1)
      end
      position = find_position(tokens, ['&&'], 0, reverse=1)
      while position >= 0
        ope = [TYPE_OPERATOR, tokens[position]]
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        left = get_left_(tokens, position)
        tokens.insert(position - 1, [TYPE_CONDITION, [left, ope, right]])
        position = find_position(tokens, ['&&'], 0, reverse=1)
      end
      position = find_position(tokens, ['||'], 0, reverse=1)
      while position >= 0
        ope = [TYPE_OPERATOR, tokens[position]]
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        left = get_left_(tokens, position)
        tokens.insert(position - 1, [TYPE_CONDITION, [left, ope, right]])
        position = find_position(tokens, ['||'], 0, reverse=1)
      end
      position = find_position(tokens, ['=', ':='], 0, reverse=1)
      while position >= 0
        ope = [TYPE_OPERATOR, tokens[position]]
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        left = get_left_(tokens, position)
        tokens.insert(position - 1, [TYPE_SUBSTITUTION, [left, ope, right]])
        position = find_position(tokens, ['=', ':='], 0, reverse=1)
      end
      position = find_position(tokens, ['+=', '-=', '*=', '/=', '%=', '+:=', '-:=', '*:=', '/:=', '%:=', ',='], 0, reverse=1)
      while position >= 0
        ope = [TYPE_OPERATOR, tokens[position]]
        tokens.delete_at(position)
        right = get_right_(tokens, position)
        left = get_left_(tokens, position)
        tokens.insert(position - 1, [TYPE_SUBSTITUTION, [left, ope, right]])
        position = find_position(tokens, ['+=', '-=', '*=', '/=', '%=', '+:=', '-:=', '*:=', '/:=', '%:=', ',='], 0, reverse=1)
      end
      temp = []
      position = find_position(tokens, [','], 0, reverse=0)
      while position >= 0
        tokens.delete_at(position)
        temp << get_right_(tokens, position)
        if position > 0
          temp.insert(-1, get_left_(tokens, position))
        end
        position = find_position(tokens, [','], 0, reverse=0)
      end
      if temp
        tokens.insert(position, [TYPE_NEW_ARRAY, temp])
      end
      for i in 0..tokens.length-1
        if tokens[i].is_a?(String)
          token = tokens[i]
          tokens.delete_at(i)
          tokens.insert(i, parse_token(token))
        end
      end
      return tokens[0] ## FIXME
    end

    def parse_(line) ## FIXME
      statement = AyaStatement.new(line)
      return new_parse(statement.tokens)
    end

    def parse_statement(statement_tokens)
      n_tokens = statement_tokens.length
      statement = []
      if n_tokens == 1
        statement = [TYPE_STATEMENT,
                     parse_token(statement_tokens[0])]
      elsif statement_tokens[0] == '+'
        statement = parse_statement(statement_tokens[1..-1])
      elsif statement_tokens[0] == '-'
        tokens = ['0']
        tokens.concat(statement_tokens)
        statement = parse_statement(tokens)
      else
        ope_index = nil
        for ope in ['+', '-']
          if statement_tokens.include?(ope)
            new_index = statement_tokens.index(ope)
            if ope_index == nil or new_index < ope_index
              ope_index = new_index
            end
          end
        end
        if ope_index == nil
          statement_tokens.reverse()
          begin
            for ope in ['*', '/', '%']
              if statement_tokens.include?(ope)
                new_index = statement_tokens.index(ope)
                if ope_index == nil or new_index < ope_index
                  ope_index = new_index
                end
              end
            end
            if ope_index != nil
              ope_index = -1 - ope_index
            end
          ensure
            statement_tokens.reverse()
          end
        end
        if [nil, -1, 0, n_tokens - 1].include?(ope_index)
          return nil
        else
          ope = [TYPE_OPERATOR, statement_tokens[ope_index]]
          if statement_tokens[0..ope_index-1].length == 1
            if statement_tokens[0].start_with?('(')
              tokens = AyaStatement.new(statement_tokens[0][1..-2]).tokens
              left = parse_statement(tokens)
            else
              left = parse_token(
                statement_tokens[0..ope_index-1][0])
            end
          else
            left = parse_statement(statement_tokens[0..ope_index-1])
          end
          if statement_tokens[ope_index + 1..-1].length == 1
            if statement_tokens[-1].start_with?('(')
              tokens = AyaStatement(
                statement_tokens[ope_index + 1][1..-2]).tokens
              right = parse_statement(tokens)
            else
              right = parse_token(
                statement_tokens[ope_index + 1..-1][0])
            end
          else
            right = parse_statement(
              statement_tokens[ope_index + 1..-1])
          end
          statement = [TYPE_STATEMENT, left, ope, right]
        end
      end
      return statement
    end

    def parse_condition(condition_tokens)
      n_tokens = condition_tokens.length
      condition = nil
      ope_index = nil
      condition_tokens.reverse()
      begin
        for ope in ['&&', '||']
          if condition_tokens.include?(ope)
            new_index = condition_tokens.index(ope)
            if ope_index == nil or new_index < ope_index
              ope_index = new_index
            end
          end
        end
        if ope_index != nil
          ope_index = -1 - ope_index
        end
      ensure
        condition_tokens.reverse()
      end
      if ope_index == nil
        for ope in ['==', '!=', '>', '<', '>=', '<=', '_in_', '!_in_']
          if condition_tokens.include?(ope)
            new_index = condition_tokens.index(ope)
            if ope_index == nil or new_index < ope_index
              ope_index = new_index
            end
          end
        end
        if [nil, -1, 0, n_tokens - 1].include?(ope_index)
          Logging::Logging.debug(
            'syntax error in function "' + @name.to_s + '": ' \
                                                        'illegal condition "' + condition_tokens.join(' ') + '"')
          return nil
        end
        ope = [TYPE_OPERATOR, condition_tokens[ope_index]]
        if condition_tokens[0..ope_index-1].length == 1
          left = parse_statement([condition_tokens[0..ope_index-1][0]])
        else
          left = parse_statement(condition_tokens[0..ope_index-1])
        end
        if condition_tokens[ope_index + 1..-1].length == 1
          right = parse_statement([condition_tokens[ope_index + 1..-1][0]])
        else
          right = parse_statement(condition_tokens[ope_index + 1..-1])
        end
        condition = [TYPE_CONDITION, [left, ope, right]]
      else
        ope = [TYPE_OPERATOR, condition_tokens[ope_index]]
        left = parse_condition(condition_tokens[0..ope_index-1])
        right = parse_condition(condition_tokens[ope_index + 1..-1])
        if left != nil and right != nil
          condition = [TYPE_CONDITION, [left, ope, right]]
        end
      end
      return condition
    end

    def parse_argument(args) ## FIXME
      argument = AyaArgument.new(args)
      arguments = []
      while argument.has_more_tokens()
        token = argument.next_token()
        if token.start_with?('&')
          result = parse_token(token[1..-1])
          if result[0] == TYPE_ARRAY
            arguments << [TYPE_ARRAY_POINTER, result[1]]
          elsif result[0] == TYPE_VARIABLE
            arguments << [TYPE_VARIABLE_POINTER, result[1]]
          elsif result[0] == TYPE_TOKEN
            arguments << [TYPE_VARIABLE_POINTER,
                          [result[1], nil]]
          else
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
              'illegal argument "' + token.to_s + '"')
          end
        elsif token.start_with?('(')
          if not token.end_with?(')')
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
              'unbalanced "(" in the string(' + token.to_s + ')')
            return nil
          else
            statement = AyaStatement.new(token[1..-2])
            arguments << parse_statement(statement.tokens)
          end
        else
          arguments << parse_statement([token])
        end
      end
      return arguments
    end

    def parse_token(token)
      result = []
      if Re_f.match(token)
        result = [TYPE_FLOAT, token]
      elsif Re_d.match(token)
        result = [TYPE_INT, token]
      elsif token.start_with?('"')
        text = token[1..-1]
        if text.end_with?('"')
          text = text[0..-2]
        end
        if text.count('"') > 0
          Logging::Logging.debug(
            'syntax error in function "' + @name.to_s + '": ' \
            '\'"\' in string "' + text.to_s + '"')
        end
        if not text.include?('%')
          result = [TYPE_STRING_LITERAL, text]
        else
          result = [TYPE_STRING, text]
        end
      elsif token.start_with?("'")
        text = token[1..-1]
        if text.end_with?("'")
          text = text[0..-2]
        end
        if text.count("'") > 0
          Logging::Logging.debug(
            'syntax error in function "' + @name.to_s + '": ' \
            "\"'\" in string \"' + text.to_s + '\"")
        end
        result = [TYPE_STRING_LITERAL, text]
      else
        pos_parenthesis_open = token.index('(')
        pos_block_open = token.index('[')
        if not pos_parenthesis_open # XXX
          pos_parenthesis_open = -1
        end
        if not pos_block_open # XXX
          pos_block_open = -1
        end
        if pos_parenthesis_open == 0 and Aya5.find_not_quoted(token, ',') != -1 ## FIXME: Array
          if not token.end_with?(')')
            Logging::Logging.debug(
              'syntax error: unbalnced "(" in "{0}"'.format(token))
          else
            result = [TYPE_NEW_ARRAY,
                      parse_argument(token[1..-2])] ## FIXME
          end
        elsif pos_parenthesis_open != -1 and \
             (pos_block_open == -1 or \
              pos_parenthesis_open < pos_block_open) # function
          if not token.end_with?(')')
            Logging::Logging.debug(
              'syntax error: unbalnced "(" in "' + token.to_s + '"')
          else
            func_name = token[0..pos_parenthesis_open-1]
            arguments = parse_argument(
              token[pos_parenthesis_open + 1..-2])
            break_flag = false
            for char in SPECIAL_CHARS
              if func_name.include?(char)
                Logging::Logging.debug(
                  'illegal character "' + char + '" in ' \
                                                 'the name of function "' + token.to_s + '"')
                break_flag = true
                break
              end
            end
            if not break_flag
              if @dic.aya.get_system_functions().exists(
                func_name)
                if func_name == 'LOGGING'
                  result = [TYPE_SYSTEM_FUNCTION,
                            [func_name, arguments,
                             token[pos_parenthesis_open + 1..-2]]]
                else
                  result = [TYPE_SYSTEM_FUNCTION,
                            [func_name, arguments]]
                end
              else
                result = [TYPE_FUNCTION,
                          [func_name, arguments]]
              end
            end
          end
        elsif pos_block_open != nil and pos_block_open != -1 # array
          if not token.end_with?(']')
            Logging::Logging.debug(
              'syntax error: unbalanced "[" in "' + token.to_s + '"')
          else
            array_name = token[0..pos_block_open-1]
            index = parse_token(token[pos_block_open + 1..-2])
            break_flag = false
            for char in SPECIAL_CHARS
              if array_name.include?(char)
                Logging::Logging.debug(
                  'illegal character "' + char.to_s + '" in ' \
                  'the name of array "' + token.to_s + '"')
                break_flag = true
                break
              end
            end
            if not break_flag
              result = [TYPE_ARRAY, [array_name, index]]
            end
          end
        else # variable or function
          break_flag = false
          for char in SPECIAL_CHARS
            if token.include?(char)
              Logging::Logging.debug(
                'syntax error in function "' + @name.to_s + '": ' \
                                                            'illegal character "' + char + '" in the name of ' \
                                                                                           'function/variable "' + token + '"')
              break_flag = true
              break
            end
          end
          if not break_flag
            result = [TYPE_TOKEN, token]
          end
        end
      end
      return result
    end

    def call(argv=nil)
      namespace = AyaNamespace.new(@dic.aya)
      _argv = []
      if not argv
        namespace.put('_argc', 0)
      else
        namespace.put('_argc', argv.length)
        for i in 0..argv.length-1
          if argv[i].is_a?(Hash)
            _argv << argv[i]['value']
          else
            _argv << argv[i]
          end
        end
      end
      namespace.put('_argv', _argv)
      @status = CODE_NONE
      result = evaluate(namespace, @lines, -1, 0) ## FIXME
      if argv
        for i in 0..argv.length-1
          if argv[i].is_a?(Hash)
            value = _argv[i]
            name = argv[i]['name']
            namespace = argv[i]['namespace']
            index = argv[i]['index']
            namespace.put(name, value, index)
          end
        end
      end
      return result
    end

    def evaluate(namespace, lines, index_to_return, is_inner_block, is_block=1, connect=0) ## FIXME
      result = []
      alternatives = []
      for line in lines
        if not line or line.empty?
          next
        end
        if [TYPE_DECISION, TYPE_RETURN,
            TYPE_BREAK, TYPE_CONTINUE].include?(line[0]) or \
          [CODE_RETURN, CODE_BREAK,
           CODE_CONTINUE].include?(@status)
          if not alternatives.empty?
            if is_inner_block != 0
              if index_to_return < 0
                result << alternatives.sample
              elsif index_to_return <= alternatives.length - 1
                result << alternatives[index_to_return]
              else # out of range
                result << ''
              end
            else
              result << alternatives
            end
            alternatives = []
          end
          if line[0] == TYPE_RETURN or \
            @status == CODE_RETURN
            @status = CODE_RETURN
            break
          elsif line[0] == TYPE_BREAK or \
               @status == CODE_BREAK
            @status = CODE_BREAK
            break
          elsif line[0] == TYPE_CONTINUE or \
               @status == CODE_CONTINUE
            @status = CODE_CONTINUE
            break
          end
        elsif line[0] == TYPE_BLOCK
          inner_func = line[1]
          local_namespace = AyaNamespace.new(@dic.aya, namespace)
          result_of_inner_func = evaluate(local_namespace,
                                          inner_func, -1, 1) ## FIXME
          if result_of_inner_func
            alternatives << result_of_inner_func
          end
        elsif line[0] == TYPE_SUBSTITUTION
          left, ope, right = line[1]
          ope = ope[1]
          if [':=', '+:=', '-:=', '*:=', '/:=', '%:='].include?(ope)
            type_float = 1
          else
            type_float = 0
          end
          right_result = evaluate(namespace, [right], -1 , 1, 0, 1) ## FIXME
          if not ['=', ':='].include?(ope)
            left_result = evaluate_token(namespace, left) 
            right_result = operation(left_result, ope[0],
                                     right_result, type_float)
            ope = ope[1..-1]
          end
          result_of_substitution = substitute(namespace, left, ope, right_result)
          if connect ## FIXME
            alternatives << result_of_substitution
          end
        elsif line[0] == TYPE_INC or \
             line[0] == TYPE_DEC # ++/--
          if line[0] == TYPE_INC
            ope = '++'
          elsif line[0] == TYPE_DEC
            ope = '--'
          else
            return nil # should not reach here
          end
          var_name = line[1]
          if var_name.start_with?('_')
            target_namespace = namespace
          else
            target_namespace = @dic.aya.get_global_namespace()
          end
          value = evaluate(namespace, [[TYPE_TOKEN, var_name]], -1, 1, 0) ## FIXME
          index = nil
          if value.is_a?(Fixnum) or value.is_a?(Float)
            if ope == '++'
              target_namespace.put(var_name, value.to_i + 1, index)
            elsif ope == '--'
              target_namespace.put(var_name, value.to_i - 1, index)
            else
              return nil # should not reach here
            end
          else
            Logging::Logging.debug(
              'illegal increment/decrement:' \
              'type of variable ' + var_name.to_s + ' is not number')
          end
        elsif line[0] == TYPE_IF
          inner_blocks = line[1]
          n_blocks = inner_blocks.length
          for j in 0..n_blocks-1
            entry = inner_blocks[j]
            condition = entry[0]
            inner_block = entry[1]
            if evaluate(namespace, [condition], -1, 1, 0) ## FIXME
              local_namespace = AyaNamespace.new(@dic.aya, namespace)
              result_of_inner_block = evaluate(local_namespace,
                                               inner_block,
                                               -1, 1) ## FIXME
              if result_of_inner_block
                alternatives << result_of_inner_block
              end
              break
            end
          end
        elsif line[0] == TYPE_WHILE
          condition = line[1][0]
          inner_block = line[1][1]
          ##assert condition[0] == TYPE_CONDITION or condition[0] == TYPE_INT
          while evaluate_condition(namespace, condition)
            local_namespace = AyaNamespace.new(@dic.aya, namespace)
            result_of_inner_block = evaluate(local_namespace,
                                             inner_block, -1, 1) ## FIXME
            if result_of_inner_block
              alternatives << result_of_inner_block
            end
            if @status == CODE_RETURN
              break
            end
            if @status == CODE_BREAK
              @status = CODE_NONE
              break
            end
            if @status == CODE_CONTINUE
              @status = CODE_NONE
            end
          end
        elsif line[0] == TYPE_FOR
          init = line[1][0][0]
          condition = line[1][0][1]
          reset = line[1][0][2]
          inner_block = line[1][1]
          evaluate(namespace, init, -1, 1, 0) ## FIXME
          ##assert condition[0] == TYPE_CONDITION or condition[0] == TYPE_INT
          while evaluate_condition(namespace, condition)
            local_namespace = AyaNamespace.new(@dic.aya, namespace)
            result_of_inner_block = evaluate(local_namespace,
                                             inner_block, -1, 1) ## FIXME
            if result_of_inner_block
              alternatives << result_of_inner_block
            end
            if @status == CODE_RETURN
              break
            end
            if @status == CODE_BREAK
              @status = CODE_NONE
              break
            end
            if @status == CODE_CONTINUE
              @status = CODE_NONE
            end
            evaluate(namespace, reset, -1, 1, 0) ## FIXME
          end
        elsif line[0] == TYPE_SWITCH
          index = evaluate_token(namespace, line[1][0])
          inner_block = line[1][1]
          begin
            index = Integer(index)
          rescue
            index = 0
          end
          local_namespace = AyaNamespace.new(@dic.aya, namespace)
          result_of_inner_block = evaluate(local_namespace,
                                           inner_block, index, 1) ## FIXME
          if result_of_inner_block
            alternatives << result_of_inner_block
          end
        elsif line[0] == TYPE_CASE
          left = evaluate_token(namespace, line[1][0])
          inner_blocks = line[1][1]
          n_blocks = inner_blocks.length
          default_result = nil
          break_flag = false
          for j in 0..n_blocks-1
            entry = inner_blocks[j]
            inner_block = entry[1]
            local_namespace = AyaNamespace.new(@dic.aya, namespace)
            if entry[0] != nil
              value_min, value_max = entry[0]
              value_min = evaluate_statement(namespace, value_min, 1)
              value_max = evaluate_statement(namespace, value_max, 1)
              if value_min <= left and left <= value_max
                result_of_inner_block = evaluate(
                  local_namespace, inner_block, -1, 1) ## FIXME
                if result_of_inner_block
                  alternatives << result_of_inner_block
                  break_flag = true
                  break
                end
              end
            else
              default_result = evaluate(local_namespace,
                                        inner_block, -1, 1) ## FIXME
            end
          end
          if not break_flag
            if default_result
              alternatives << default_result
            end
          end
        elsif line[0] == TYPE_STATEMENT
          result_of_func = evaluate_statement(namespace, line, 0)
          if result_of_func
            alternatives << result_of_func
          end
        elsif line[0] == TYPE_CONDITION
          condition = line
          if condition == nil or \
            evaluate_condition(namespace, condition)
            alternatives << true
          else
            alternatives << false
          end
        elsif line[0] == TYPE_FORMULA
          result_of_formula = evaluate(namespace, [line[1]], -1, 1, 0, connect=connect) ## FIXME
          if result_of_formula
            alternatives << result_of_formula
          end
        elsif line[0] == TYPE_NEW_ARRAY
          temp = []
          for item in line[1]
            member_of_array = evaluate(namespace, [item], -1, 1, 0, 1) ## FIXME
            temp << member_of_array
          end
          alternatives << temp
        elsif line[0] == TYPE_ARRAY
          system_functions = @dic.aya.get_system_functions()
          if line[1][0].is_a?(Array) or \
            system_functions.exists(line[1][0])
            if line[1][0].is_a?(Array) ## FIXME
              array = evaluate(namespace, [line[1][0]], -1, 1, 0) ## FIXME
            else
              array = evaluate(namespace, [[TYPE_SYSTEM_FUNCTION, [line[1][0], []]]], -1, 1, 0)
            end
            if array.is_a?(String)
              temp = evaluate(namespace, [line[1][1]], -1, 1, 0) ## FIXME
              if temp.is_a?(Array)
                #assert temp.length == 2
                index, delimiter = temp
              else
                index = temp
                delimiter = ','
              end
              ##assert index.is_a?(Fixnum)
              ##assert delimiter.is_a?(String)
              result_of_array = array.split(delimiter)[index]
              alternatives << result_of_array
            elsif array.is_a?(Array)
              index = evaluate(namespace, [line[1][1]], -1, 1, 0) ## FIXME
              ##assert index.is_a?(Fixnum)
              result_of_array = array[index]
              alternatives << result_of_array
            else
              Logging::Logging.debug(
                'Oops: ' + array.to_s + ' ' + line[1][1].to_s)
            end
          else
            var_name = line[1][0]
            if var_name.start_with?('_')
              target_namespace = namespace
            else
              target_namespace = @dic.aya.get_global_namespace()
            end
            temp = evaluate(namespace, [line[1][1]], -1, 1, 0) ## FIXME
            if temp.is_a?(Array) and temp.length > 1
              ##assert temp.length == 2
              index, delimiter = temp
              ##assert delimiter.is_a?(String)
            else
              index = temp
              delimiter = nil
            end
            ##assert index.is_a?(Fixnum)
            if index.is_a?(Fixnum) and \
              target_namespace.exists(var_name)
              if delimiter != nil
                array = target_namespace.get(var_name)
                temp = array.to_s.split(delimiter)
                if temp.length > index
                  result_of_array = array.to_s.split(delimiter)[index]
                else
                  result_of_array = ''
                end
              else
                result_of_array = target_namespace.get(var_name, index)
              end
              alternatives << result_of_array
            else
              result_of_array = ''
              alternatives << result_of_array
            end
          end
        elsif [TYPE_INT, TYPE_TOKEN,
               TYPE_SYSTEM_FUNCTION,
               TYPE_STRING_LITERAL,
               TYPE_FUNCTION,
               TYPE_STRING,
               TYPE_ARRAY_POINTER,
               TYPE_VARIABLE_POINTER].include?(line[0])
          result_of_eval = evaluate_token(namespace, line)
          if result_of_eval
            alternatives << result_of_eval
          end
        elsif line[0] == TYPE_FOREACH
          var_name, temp = line[1][0]
          if var_name.start_with?('_')
            target_namespace = namespace
          else
            target_namespace = @dic.aya.get_global_namespace()
          end
          array = target_namespace.get_array(var_name)
          for item in array
            if temp.start_with?('_')
              target_namespace = namespace
            else
              target_namespace = @dic.aya.get_global_namespace()
            end
            target_namespace.put(temp, item)
            result_of_block = evaluate(namespace, line[1][1], -1, 1) ## FIXME
            if @status == CODE_RETURN
              break
            end
            if @status == CODE_BREAK
              @status = CODE_NONE
              break
            end
            if @status == CODE_CONTINUE
              @status = CODE_NONE
            end
          end
        else ## FIXME
          result_of_eval = evaluate_token(namespace, line)
          if result_of_eval
            alternatives << result_of_eval
          end
        end
      end
      if is_inner_block == 0
        if @sequential != nil
          list_ = []
          for alt in result
            list_ << alt.length
          end
          if @sequential[0] != list_
            @sequential[0] = list_
            @sequential[1] = [0] * result.length
          else
            for index in 0..result.length-1
              current = @sequential[1][index]
              if current < result[index].length - 1
                @sequential[1][index] = current + 1
                break
              else
                @sequential[1][index] = 0
              end
            end
          end
        end
        if @nonoverlap != nil
          list_ = []
          for alt in result
            list_ << alt.length
          end
          if @nonoverlap[0] != list_
            @nonoverlap[0] = list_
            @nonoverlap[2] = []
          end
          if @nonoverlap[2].empty?
            @nonoverlap[2] << ([0] * result.length)
            while true
              new = []
              new.concat(@nonoverlap[2][-1])
              break_flag = false
              for index in 0..result.length-1
                if new[index] < result[index].length - 1
                  new[index] += 1
                  @nonoverlap[2] << new
                  break_flag = true
                  break
                else
                  new[index] = 0
                end
              end
              if not break_flag
                break
              end
            end
          end
          next_ = Random.rand(0..@nonoverlap[2].length-1)
          @nonoverlap[1] = @nonoverlap[2][next_]
          @nonoverlap[2].delete(next_)
        end
        for index in 0..result.length-1
          if @sequential != nil
            result[index] = result[index][@sequential[1][index]]
          elsif @nonoverlap != nil
            result[index] = result[index][@nonoverlap[1][index]]
          else
            result[index] = result[index].sample
          end
        end
      end
      if not result or result.empty?
        if not is_block != 0 and not alternatives.empty? ## FIXME
          return alternatives[-1] ## FIXME
        end
        return nil
      elsif result.length == 1
        return result[0]
      else
        return result.map {|s| s.to_s}.join('')
      end
    end

    def substitute(namespace, left, ope, right)
      if left[0] != TYPE_ARRAY
        var_name = left[1]
      else
        var_name = left[1][0]
      end
      if var_name.start_with?('_')
        target_namespace = namespace
      else
        target_namespace = @dic.aya.get_global_namespace()
      end
      if left[0] != TYPE_ARRAY
        target_namespace.put(var_name, right)
      else
        index = evaluate(namespace, [left[1][1]], -1, 1, 0)
        begin
          index = Integer(index)
        rescue
          Logging::Logging.debug('Could not convert ' + index.to_s + ' to an integer')
        else
          if ope == '='
            elem = right
          elsif ope == ':='
            if right.is_a?(Fixnum)
              elem = right.to_f
            else
              elem = right
            end
          else
            return nil # should not reach here
          end
          target_namespace.put(var_name, elem, index)
        end
      end
      return right
    end

    def evaluate_token(namespace, token)
      result = '' # default
      if token[0] == TYPE_TOKEN
        if Re_b.match(token[1])
          pos = Re_d.search(token[1]).start()
          result = token[1][pos..-1].to_i(2)
        elsif Re_x.match(token[1])
          result = token[1].to_i(16)
        else
          func = @dic.get_function(token[1])
          system_functions = @dic.aya.get_system_functions()
          if func
            result = func.call()
          elsif system_functions.exists(token[1])
            result = system_functions.call(namespace, token[1], [])
          else
            if token[1].start_with?('_')
              target_namespace = namespace
            else
              target_namespace = @dic.aya.get_global_namespace()
            end
            if target_namespace.exists(token[1])
              result = target_namespace.get(token[1])
            end
          end
        end
      elsif token[0] == TYPE_STRING_LITERAL
        result = token[1]
      elsif token[0] == TYPE_STRING
        result = evaluate_string(namespace, token[1])
      elsif token[0] == TYPE_INT
        result = token[1].to_i
      elsif token[0] == TYPE_FLOAT
        result = token[1].to_f
      elsif token[0] == TYPE_SYSTEM_FUNCTION
        system_functions = @dic.aya.get_system_functions()
        func_name = token[1][0]
        ##assert system_functions.exists(func_name)
        ##raise Exception(['function ', func_name, ' not found.'].join(''))
        arguments = evaluate(namespace, token[1][1], -1, 1, 0, 1) ## FIXME
        if not arguments.is_a?(Array) ## FIXME
          arguments = [arguments]
        end
        if func_name == 'LOGGING'
          arguments.insert(0, token[1][2])
          arguments.insert(0, @name)
          arguments.insert(0, @dic.aya.logfile)
          result = system_functions.call(namespace, func_name, arguments)
        else
          result = system_functions.call(namespace, func_name, arguments)
        end
      elsif token[0] == TYPE_FUNCTION
        func_name = token[1][0]
        func = @dic.get_function(func_name)
        ##assert func != nil
        ##raise Exception(['function ', func_name, ' not found.'].join(''))
        arguments = evaluate_argument(namespace, func_name,
                                      token[1][1], 0)
        result = func.call(arguments)
      elsif token[0] == TYPE_ARRAY
        result = evaluate(namespace, [token], -1, 1, 0) ## FIXME
      elsif token[0] == TYPE_NEW_ARRAY
        result = evaluate(namespace, [token], -1, 1, 0) ## FIXME
      elsif token[0] == TYPE_VARIABLE
        var_name = token[1][0]
        if var_name.start_with?('_')
          target_namespace = namespace
        else
          target_namespace = @dic.aya.get_global_namespace()
        end
        if target_namespace.exists(var_name)
          result = target_namespace.get(var_name)
        end
      elsif token[0] == TYPE_ARRAY_POINTER
        var_name = token[1][0]
        if var_name.start_with?('_')
          target_namespace = namespace
        else
          target_namespace = @dic.aya.get_global_namespace()
        end
        index = evaluate(namespace, [token[1][1]], -1, 1, 0)
        begin
          index = Integer(index)
        rescue
          Logging::Logging.debug(
            'index of array has to be integer: ' + var_name.to_s + '[' + token[1][1].to_s + ']')
        else
          value = target_namespace.get(var_name, index)
          result = {'name' => var_name,
                    'index' => index,
                    'namespace' => target_namespace,
                    'value' => value}
        end
      elsif token[0] == TYPE_VARIABLE_POINTER
        var_name = token[1][0]
        if var_name.start_with?('_')
          target_namespace = namespace
        else
          target_namespace = @dic.aya.get_global_namespace()
        end
        value = target_namespace.get(var_name)
        result = {'name' => var_name,
                  'index' => nil,
                  'namespace' => target_namespace,
                  'value' => value}
      else
        Logging::Logging.debug('error in evaluate_token: ' + token.to_s)
      end
      return result
    end

    def evaluate_condition(namespace, condition)
      result = false
      if condition[0] == TYPE_INT
        if Integer(condition[1]) != 0
          return true
        else
          return false
         end
      end
      if condition[1] == nil
        return true
      end
      left = condition[1][0]
      ope = condition[1][1]
      right = condition[1][2]
      ##assert ope[0] == TYPE_OPERATOR
      if left == nil # '!'
        left_result = true
      else
        left_result = evaluate(namespace, [left], -1, 1, 0, 1) ## FIXME
      end
      right_result = evaluate(namespace, [right], -1, 1, 0, 1) ## FIXME
      if ope[1] == '=='
        result = (left_result == right_result)
      elsif ope[1] == '!='
        result = (left_result != right_result)
      elsif ope[1] == '_in_'
        if right_result.is_a?(String) and left_result.is_a?(String)
          if right_result.include?(left_result)
            result = true
          else
            result = false
          end
        else
          result = false
        end
      elsif ope[1] == '!_in_'
        if right_result.is_a?(String) and left_result.is_a?(String)
          if not right_result.include?(left_result)
            result = true
          else
            result = false
          end
        else
          result = false
        end
      elsif ope[1] == '<'
        if right_result.is_a?(String) != left_result.is_a?(String)
          begin
            left_result = Float(left_result)
            right_result = Float(right_result)
          rescue
            return false # XXX
          end
        end
        result = left_result < right_result
      elsif ope[1] == '>'
        if right_result.is_a?(String) != left_result.is_a?(String)
          begin
            left_result = Float(left_result)
            right_result = Float(right_result)
          rescue
            return false # XXX
          end
        end
        result = left_result > right_result
      elsif ope[1] == '<='
        if right_result.is_a?(String) != left_result.is_a?(String)
          begin
            left_result = Float(left_result)
            right_result = Float(right_result)
          rescue
            return false # XXX
          end
        end
        result = left_result <= right_result
      elsif ope[1] == '>='
        if right_result.is_a?(String) != left_result.is_a?(String)
          begin
            left_result = Float(left_result)
            right_result = Float(right_result)
          rescue
            return false # XXX
          end
        end
        result = left_result >= right_result
      elsif ope[1] == '||'
        result = left_result or right_result
      elsif ope[1] == '&&'
        result = left_result and right_result
      elsif ope[1] == '!'
        result = (not right_result)
      else
        #pass
      end
      return result
    end

    def evaluate_statement(namespace, statement, type_float)
      num = statement[1..-1].length
      if num == 0
        return ''
      end
      type_ = statement[0]
      token = statement[1]
      if type_ == TYPE_STATEMENT
        left = evaluate_statement(namespace, token, type_float)
      else
        left = evaluate_token(namespace, statement)
      end
      if num == 3
        ope = statement[2][1]
        type_ = statement[3][0]
        if type_ == TYPE_INT
          token = statement[3][1]
          if type_float != 0
            right = token.to_f
          else
            right = token.to_i
          end
        elsif type_ == TYPE_FLOAT
          token = statement[3][1]
          if type_float != 0
            right = token.to_f
          else
            right = token.to_f.to_i
          end
        elsif type_ == TYPE_STATEMENT
          right = evaluate_statement(namespace, statement[3],
                                     type_float)
        else
          right = evaluate(namespace, [statement[3]], -1, 1, 0) ## FIXME
        end
        result = operation(left, ope, right, type_float)
      else
        result = left
      end
      return result
    end

    def operation(left, ope, right, type_float)
      if not left.is_a?(Array)
        begin
          if type_float != 0
            left = Float(left)
            right = Float(right)
          elsif ope != '+' or \
               (not left.is_a?(String) and not right.is_a?(String))
            left = Integer(left)
            right = Integer(right)
          else
            left = left.to_s
            right = right.to_s
          end
        rescue
          left = left.to_s
          right = right.to_s
        end
      end
      begin
        if ope == '+'
          return left + right
        elsif ope == '-'
          return left - right
        elsif ope == '*'
          return left * right
        elsif ope == '/'
          if right == 0
            return 0
          else
            if left.is_a?(Fixnum) and right.is_a?(Fixnum)
              return (left / right).to_i
            else
              return left / right
            end
          end
        elsif ope == '%'
          return left % right
        elsif ope == ','
          ##assert left.is_a?(Array)
          result = []
          result.concat(left)
          if right.is_a?(Array)
            result.concat(right)
          else
            result << right
          end
          return result
        end
      rescue
        Logging::Logging.debug(
          'illegal operation: ' + [left.to_s, ope.to_s, right.to_s].join(' '))
        return ''
      end
    end

    def get_block(parent, startpoint)
      result = []
      n_lines = parent.length
      inner_nest_level = 0
      for i in startpoint..n_lines-1
        inner_content = parent[i]
        if inner_content == '{'
          if inner_nest_level > 0
            result << inner_content
          end
          inner_nest_level += 1
        elsif inner_content == '}'
          inner_nest_level -= 1
          if inner_nest_level > 0
            result << inner_content
          end
        else
        result << inner_content
        end
        if inner_nest_level == 0
          return i, result
        end
      end
      return startpoint, result
    end

    def evaluate_string(namespace, line)
      history = [] # %[n]
      buf = ''
      startpoint = 0
      system_functions = @dic.aya.get_system_functions()
      while startpoint < line.length
        pos = line.index('%', startpoint)
        if not pos or pos < 0
          buf = [buf, line[startpoint..-1]].join('')
          startpoint = line.length
          next
        else
          if pos != 0
            buf = [buf, line[startpoint..pos-1]].join('')
          end
          startpoint = pos
        end
        if pos == line.length - 1 # XXX
          break
        end
        if line[pos + 1] == '('
          start_ = pos + 2
          nest = 0
          current_ = start_
          while line[current_..-1].count(')') > 0
            close_ = line.index(')', current_)
            if close_ == 0
              break
            end
            nest = line[start_..close_-1].count('(') - line[start_..close_-1].count(')')
            if nest > 0
              current_ = close_ + 1
            else
              current_ = close_
              break
            end
          end
          lines_ = parse([line[start_..current_-1]])
          result_ = evaluate(namespace, lines_, -1, 1, 0, 1)
          buf = [buf, result_.to_s].join('')
          startpoint = current_ + 1
          next
        end
        endpoint = line.length
        for char in SPECIAL_CHARS
          pos = line[0..endpoint-1].index(char, startpoint + 2)
          if pos and 0 < pos and pos < endpoint
            endpoint = pos
          end
        end
        if  line[startpoint + 1] == '[' # history
          if line[endpoint] != ']'
            Logging::Logging.debug(
              'unbalanced "%[" or illegal index in ' \
              'the string(' + line + ')')
            buf = ''
            break
          end
          index_token = parse_token(line[startpoint + 2..endpoint-1])
          index = evaluate_token(namespace, index_token)
          begin
            index = Integer(index)
          rescue
            Logging::Logging.debug(
              'illegal history index in the string(' + line + ')')
          else
            if 0 <= index and index < history.length
              buf = [buf, format(history[index])].join('')
            end
          end
          startpoint = endpoint + 1
          next
        end
        replaced = false
        while endpoint > startpoint + 1
          token = line[startpoint + 1..endpoint-1]
          func = @dic.get_function(token)
          is_system_func = system_functions.exists(token)
          if func != nil or is_system_func
            if endpoint < line.length and \
              line[endpoint] == '('
              end_of_parenthesis = line.index(')', endpoint + 1)
              if not end_of_parenthesis or end_of_parenthesis < 0
                Logging::Logging.debug(
                  'unbalanced "(" in the string(' + line + ')')
                startpoint = line.length
                buf = ''
                break
              end
              func_name = token
              arguments = parse_argument(
                line[endpoint + 1..end_of_parenthesis-1])
              arguments = evaluate_argument(
                namespace, func_name, arguments, is_system_func)
              if is_system_func
                if func_name == 'LOGGING'
                  arguments.insert(
                    0, line[endpoint + 1..end_of_parenthesis-1])
                  arguments.insert(0, @name)
                  arguments.insert(0, @dic.aya.logfile)
                  result_of_func = system_functions.call(
                    namespace, func_name, arguments)
                else
                  result_of_func = system_functions.call(
                    namespace, func_name, arguments)
                end
              else
                result_of_func = func.call(arguments)
              end
              if result_of_func == nil
                result_of_func = ''
              end
              history << result_of_func
              buf = [buf, format(result_of_func)].join('')
              startpoint = end_of_parenthesis + 1
              replaced = true
              break
            elsif func != nil
              result_of_func = func.call()
              history << result_of_func
              buf = [buf, format(result_of_func)].join('')
              startpoint = endpoint
              replaced = true
              break
            else
              result_of_func = system_functions.call(
                namespace, token, [])
              if result_of_func == nil
                result_of_func = ''
              end
              history << result_of_func
              buf = [buf, format(result_of_func)].join('')
              startpoint = endpoint
              replaced = true
              break
            end
          else
            if token.start_with?('_')
              target_namespace = namespace
            else
              target_namespace = @dic.aya.get_global_namespace()
            end
            if target_namespace.exists(token)
              have_index = false
              index = nil
              if endpoint < line.length and line[endpoint] == '['
                end_of_block = line.index(']', endpoint + 1)
                if not end_of_block or end_of_block < 0
                  Logging::Logging.debug(
                    'unbalanced "[" or ' \
                    'illegal index in the string(' + line + ')')
                  startpoint = line.length
                  buf = ''
                  break
                end
                have_index = true
                index_token = parse_token(
                  line[endpoint + 1..end_of_block-1])
                index = evaluate_token(namespace, index_token)
                begin
                  index = Integer(index)
                rescue
                  have_index = false
                  index = nil
                end
              end
              value = target_namespace.get(token, index)
              if value != nil
                content_of_var = value
                history << content_of_var
                buf = [buf,
                       format(content_of_var)].join('')
                if have_index
                  startpoint = end_of_block + 1
                else
                  startpoint = endpoint
                end
                replaced = true
                break
              end
            end
          end
          endpoint -= 1
        end
        if not replaced
          buf = [buf, line[startpoint]].join('')
          startpoint += 1
        end
      end
      return buf
    end

    def format(input_num)
      if input_num.is_a?(Float)
        result = round(input_num, 6).to_s
      else
        result = input_num.to_s
      end
      return result
    end

    def evaluate_argument(namespace, name, argument, is_system_func)
      arguments = []
      for i in 0..argument.length-1
        if is_system_func != 0 and \
          @dic.aya.get_system_functions().not_to_evaluate(name, i)
          arguments << argument[i][1][1]
        else
          value = evaluate_statement(namespace, argument[i], 1)
          if value.is_a?(Array)
            arguments.concat(value)
          else
            arguments << value
          end
        end
      end
      return arguments
    end

    def is_substitution(line)
      statement = AyaStatement.new(line)
      if statement.countTokens() >= 3
        statement.next_token() # left
        ope = statement.next_token()
        ope_list = ['=', ':=',
                    '+=', '-=', '*=', '/=', '%=',
                    '+:=', '-:=', '*:=', '/:=', '%:=',
                    ',=']
        if ope_list.include?(ope)
          return true
        end
      end
      return false
    end

    def is_inc_or_dec(line)
      if line.length <= 2
        return false
      end
      if line.end_with?('++') or line.end_with?('--')
        return true
      else
        return false
      end
    end
  end


  class AyaSystemFunctions

    def initialize(aya)
      @aya = aya
      @current_charset = nil
      @fcharset = {}
      @charsetlib = nil
      @saori_statuscode = ''
      @saori_header = []
      @saori_value = {}
      @saori_protocol = ''
      @errno = 0
      @re_result = []
      @functions = {
        'ACOS' => ['ACOS', [nil], [1], nil],
        'ANY' => [],
        'ARRAYSIZE' => ['ARRAYSIZE', [0], [1], nil],
        'ASEARCH' => [],
        'ASEARCHEX' => [],
        'ASIN' => ['ASIN', [nil], [1], nil],
        'ATAN' => ['ATAN', [nil], [1], nil],
        'BINSTRTOI' => ['BINSTRTOI', [nil], [1], nil],
        'CEIL' => ['CEIL', [nil], [1], nil],
        'CHARSETLIB' => ['CHARSETLIB', [nil], [1], nil],
        'CHR' => ['CHR', [nil], [1], nil],
        'CHRCODE' => ['CHRCODE', [nil], [1], nil],
        'COS' => ['COS', [nil], [1], nil],
        'CUTSPACE' => ['CUTSPACE', [nil], [1], nil],
        'CVINT' => ['CVINT', [0], [1], nil],
        'CVREAL' => ['CVREAL', [0], [1], nil],
        'CVSTR' => ['CVSTR', [0], [1], nil],
        'ERASE' => ['ERASE', [nil], [3], nil],
        'ERASEVAR' => ['ERASEVAR', [nil], [1], nil],
        'EVAL' => ['EVAL', [nil], [1], nil],
        'FATTRIB' => [],
        'FCHARSET' => ['FCHARSET', [nil], [1], nil],
        'FCLOSE' => ['FCLOSE', [nil], [1], nil],
        'FCOPY' => ['FCOPY', [nil], [2], 259],
        'FDEL' => ['FDEL', [nil], [1], 269],
        'FENUM' => ['FENUM', [nil], [1, 2], 290],
        'FLOOR' => ['FLOOR', [nil], [1], nil],
        'FMOVE' => ['FMOVE', [nil], [2], 264],
        'FOPEN' => ['FOPEN', [nil], [2], 256],
        'FREAD' => ['FREAD', [nil], [1], nil],
        'FRENAME' => ['FRENAME', [nil], [2], 273],
        'FSIZE' => ['FSIZE', [nil], [1], 278],
        'FWRITE' => ['FWRITE', [nil], [2], nil],
        'FWRITE2' => ['FWRITE2', [nil], [2], nil],
        'GETDELIM' => ['GETDELIM', [0], [1], nil],
        'GETLASTERROR' => ['GETLASTERROR', [nil], [nil], nil],
        'GETMEMINFO' => [],
        'GETSETTING' => ['GETSETTING', [nil], [1], nil],
        'GETSTRBYTES' => ['GETSTRBYTES', [nil], [1, 2], nil],
        'GETTICKCOUNT' => ['GETTICKCOUNT', [nil], [0], nil],
        'GETTIME' => ['GETTIME', [nil], [0], nil],
        'GETTYPE' => ['GETTYPE', [nil], [1], nil],
        'HEXSTRTOI' => ['HEXSTRTOI', [nil], [1], nil],
        'IARRAY' => ['IARRAY', [nil], [nil], nil],
        'INSERT' => ['INSERT', [nil], [3], nil],
        'ISFUNC' => ['ISFUNC', [nil], [1], nil],
        'ISINTSTR' => ['ISINTSTR', [nil], [1], nil],
        'ISREALSTR' => ['ISREALSTR', [nil], [1], nil],
        'ISVAR' => ['ISVAR', [nil], [1], nil],
        'LETTONAME' => ['LETTONAME', [nil], [2], nil],
        'LOADLIB' => ['LOADLIB', [nil], [1], 16],
        'LOG' => ['LOG', [nil], [1], nil],
        'LOG10' => ['LOG10', [nil], [1], nil],
        'LOGGING' => [],
        'LSO' => [],
        'MKDIR' => ['MKDIR', [nil], [1], 282],
        'POW' => ['POW', [nil], [2], nil],
        'RAND' => ['RAND', [nil], [0, 1], nil],
        'RE_GETLEN' => [],
        'RE_GETPOS' => [],
        'RE_GETSTR' => ['RE_GETSTR', [nil], [0], nil],
        'RE_GREP' => [],
        'RE_MATCH' => [],
        'RE_REPLACE' => [],
        'RE_SEARCH' => [],
        'RE_SPLIT' => ['RE_SPLIT', [nil], [2], nil],
        'REPLACE' => ['REPLACE', [nil], [3], nil],
        'REQUESTLIB' => ['REQUESTLIB', [nil], [2], nil],
        'RMDIR' => ['RMDIR', [nil], [1], 286],
        'ROUND' => ['ROUND', [nil], [1], nil],
        'SAVEVAR' => ['SAVEVAR', [nil], [nil], nil],
        'SETDELIM' => ['SETDELIM', [0], [2], nil],
        'SETLASTERROR' => ['SETLASTERROR', [nil], [1], nil],
        'SIN' => ['SIN', [nil], [1], nil],
        'SPLIT' => ['SPLIT', [nil], [2, 3], nil],
        'SPLITPATH' => ['SPLITPATH', [nil], [1], nil ],
        'SQRT' => ['SQRT', [nil], [1], nil],
        'STRFORM' => [],
        'STRLEN' => ['STRLEN', [1], [1], nil],
        'STRSTR' => ['STRSTR', [3], [3], nil],
        'SUBSTR' => ['SUBSTR', [nil], [3], nil],
        'TAN' => ['TAN', [nil], [1], nil],
        'TOBINSTR' => ['TOBINSTR', [nil], [1], nil],
        'TOHEXSTR' => ['TOHEXSTR', [nil], [1], nil],
        'TOINT' => ['TOINT', [nil], [1], nil],
        'TOLOWER' => ['TOLOWER', [nil], [1], nil],
        'TOREAL' => ['TOREAL', [nil], [1], nil],
        'TOSTR' => ['TOSTR', [nil], [1], nil],
        'TOUPPER' => ['TOUPPER', [nil], [1], nil],
        'UNLOADLIB' => ['UNLOADLIB', [nil], [1], nil],
        #'LOGGING' => ['LOGGING', [nil], [4], nil]
      }
    end

    def exists(name)
      return @functions.include?(name)
    end

    def call(namespace, name, argv)
      @errno = 0
      if not @functions.include?(name)
        return ''
      elsif not @functions[name] # not implemented yet
        Logging::Logging.warning(
          'aya5.py: SYSTEM FUNCTION "' + name.to_s + '" is not implemented yet.')
        return ''
      elsif check_num_args(name, argv)
        return method(@functions[name][0]).call(namespace, argv)
      else
        return ''
      end
    end

    def not_to_evaluate(name, index)
      if @functions[name][1].include?(index)
        return true
      else
        return false
      end
    end

    def check_num_args(name, argv)
      list_num = @functions[name][2]
      if list_num == [nil]
        return 1
      else
        if list_num.include?(argv.length)
          return 1
        end
        list_num.sort()
        if argv.length < list_num[0]
          errno = @functions[name][3]
          if errno != nil
            @errno = errno
          end
          Logging::Logging.debug(
            [name.to_s, ': called with too few argument(s)'].join(''))
          return 0
        end
        return 1
      end
    end

    def ACOS(namespace, argv)
      begin
        result = math.acos(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def ANY(namespace, argv)
      #pass
    end

    def ARRAYSIZE(namespace, argv)
      return argv.length ## FIXME
    end

    def ASEARCH(namespace, argv)
      #pass
    end

    def ASEARCHEX(namespace, argv)
      #pass
    end

    def ASIN(namespace, argv)
      begin
        result = math.asin(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def ATAN(namespace, argv)
      begin
        result = math.atan(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def BINSTRTOI(namespace, argv)
      begin
        return argv[0].to_s.to_i(2)
      rescue
        return 0
      end
    end

    def CEIL(namespace, argv)
      begin
        return math.ceil(argv[0].to_f).to_i
      rescue
        return -1
      end
    end

    def CHARSETLIB(namespace, argv)
      begin
        value = Integer(argv[0])
      rescue
        return
      end
      if value == 0
        @charsetlib = 'CP932'
      elsif value == 1
        @charsetlib = 'UTF-8'
      elsif value == 127
        @charsetlib = @aya.charset
      end
    end

    def CHR(namespace, argv)
      begin
        return chr(argv[0])
      rescue
        return ''
      end
    end

    def CHRCODE(namespace, argv)
      line = argv[0].to_s
      if line
        return line[0].encode('utf-16', 'ignore') # UCS-2
      else
        return ''
      end
    end

    def COS(namespace, argv)
      begin
        result = math.cos(argv[0].to_f)
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def CUTSPACE(namespace, argv)
      return argv[0].to_s.strip()
    end

    def CVINT(namespace, argv)
      var = argv[0].to_s
      target_namespace = select_namespace(namespace, var)
      token = target_namespace.get(var)
      begin
        result = Integer(token)
      rescue
        result = 0
      end
      target_namespace.put(var, result)
      return nil
    end

    def CVREAL(namespace, argv)
      var = argv[0].to_s
      target_namespace = select_namespace(namespace, var)
      token = target_namespace.get(var)
      begin
        result = Float(token)
      rescue
        result = 0.0
      end
      target_namespace.put(var, result)
      return nil
    end

    def CVSTR(namespace, argv)
      name = argv[0].to_s
      target_namespace = select_namespace(namespace, name)
      value = target_namespace.get(name).to_s
      target_namespace.put(name, value)
      return nil
    end

    def ERASE(namespace, argv)
      line = argv[0].to_s
      begin
        start = argv[1].to_i
        bytes = argv[2].to_i
      rescue
        return ''
      end
      return [line[0..start-1], line[start + bytes..-1]].join('').encode("UTF-8", :invalid => :replace, :undef => :replace) # XXX
    end

    def ERASEVAR(namespace, argv)
      var = argv[0].to_s
      target_namespace = select_namespace(namespace, var)
      target_namespace.remove(var)
    end

    def EVAL(namespace, argv)
      script = argv[0]
      func = AyaFunction(@aya.dic, '', [script], nil)
      result = func.call()
      return result
    end

    def FATTRIB(namespace, argv)
      #pass
    end

    def FCHARSET(namespace, argv)
      begin
        value = Integer(argv[0])
      rescue
        return
      end
      if value == 0
        @current_charset = 'CP932'
      elsif value == 1
        @current_charset = 'UTF-8'
      elsif value == 127
        @current_charset = @aya.charset
      end
    end

    def FCLOSE(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      if @aya.filelist.include?(norm_path)
        @aya.filelist[norm_path].close()
        @aya.filelist.delete(norm_path)
        @f_charset.delete(norm_path)
      end
      return nil
    end

    def FCOPY(namespace, argv)
      src = Home.get_normalized_path(argv[0].to_s)
      head, tail = File.split(src)
      dst = [Home.get_normalized_path(argv[1].to_s), '/', tail].join('')
      src_path = File.join(@aya.aya_dir, src)
      dst_path = File.join(@aya.aya_dir, dst)
      result = 0
      if not File.file?(src_path)
        @errno = 260
      elsif not File.directory?(dst_path)
        @errno = 261
      else
        begin
          shutil.copyfile(src_path, dst_path)
        rescue
          @errno = 262
        else
          result = 1
        end
      end
      return result
    end

    def FDEL(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      result = 0
      if not File.file?(path)
        @errno = 270
      else
        begin
          File.delete(path)
        rescue
          @errno = 271
        else
          result = 1
        end
      end
      return result
    end

    def FENUM(namespace, argv)
      if argv.length >= 2
        separator = argv[1].to_s
      else
        separator = ','
      end
      dirname = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, dirname)
      filelist = []
      begin
        filelist = Dir.entries(path).reject{|entry| entry =~ /^\.{1,2}$/}
      rescue
        @errno = 291
      end
      result = ''
      for index in 0..filelist.length-1
        path = File.join(@aya.aya_dir, dirname, filelist[index])
        if File.directory?(path)
          result = [result, "\\"].join('')
        end
        result = [result, filelist[index]].join('')
        if index != filelist.length - 1
          result = [result, separator].join('')
        end
      end
      return result
    end

    def FLOOR(namespace, argv)
      begin
        return math.floor(argv[0].to_f).to_i
      rescue
        return -1
      end
    end

    def FMOVE(namespace, argv)
      src = Home.get_normalized_path(argv[0].to_s)
      head, tail = File.split(src)
      dst = [Home.get_normalized_path(argv[1].to_s), '/', tail].join('')
      src_path = File.join(@aya.aya_dir, src)
      dst_path = File.join(@aya.aya_dir, dst)
      result = 0
      head, tail = File.split(dst_path)
      if not File.file?(src_path)
        @errno = 265
      elsif not File.directory?(head)
        @errno = 266
      else
        begin
          File.rename(src_path, dst_path)
        rescue
          @errno = 267
        else
          result = 1
        end
      end
      return result
    end

    def FOPEN(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      accessmode = argv[1].to_s
      result = 0
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      if @aya.filelist.include?(norm_path)
        result = 2
      else
        begin
          @aya.filelist[norm_path] = open(path, [accessmode[0], 'b'].join('')) # XXX
        rescue
          @errno = 257
        else
          if @current_charset == nil
            @current_charset = @aya.charset
          end
          @f_charset[norm_path] = @current_charset
          result = 1
        end
      end
      return result
    end

    def FREAD(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      result = -1
      if @aya.filelist.include?(norm_path)
        f = @aya.filelist[norm_path]
        result = f.readline().force_encoding(@fcharset[norm_path])
        if not result
          result = -1
        elsif result.end_with?("\r\n")
          result = result[0..-3]
        elsif result.end_with?("\n")
          result = result[0..-2]
        end
      end
      return result
    end

    def FRENAME(namespace, argv)
      src = Home.get_normalized_path(argv[0].to_s)
      dst = Home.get_normalized_path(argv[1].to_s)
      src_path = File.join(@aya.aya_dir, src)
      dst_path = File.join(@aya.aya_dir, dst)
      result = 0
      head, tail = File.split(dst_path)
      if not File.exist?(src_path)
        @errno = 274
      elsif not File.directory?(head)
        @errno = 275
      else
        begin
          File.rename(src_path, dst_path)
        rescue
          @errno = 276
        else
          result = 1
        end
      end
      return result
    end

    def FSIZE(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      size = -1
      if not File.exist?(path)
        @errno = 279
      else
        begin
          size = File.size(path)
        rescue
          @errno = 280
        end
      end
      return size
    end

    def FWRITE(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      data = [argv[1].to_s, "\n"].join('')
      if @aya.filelist.include?(norm_path)
        f = @aya.filelist[norm_path]
        f.write(data.encode(@fcharset[norm_path], 'ignore'))
      end
      return nil
    end

    def FWRITE2(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      data = argv[1].to_s
      if @aya.filelist.include?(norm_path)
        f = @aya.filelist[norm_path]
        f.write(data.encode(@fcharset[norm_path], 'ignore'))
      end
      return nil
    end

    def GETDELIM(namespace, argv)
      name = argv[0].to_s
      target_namespace = select_namespace(namespace, name)
      return target_namespace.get_separator(name)
    end

    def GETLASTERROR(namespace, argv)
      return @errno
    end

    def GETMEMINFO(namespace, argv)
      #pass
    end

    def GETSETTING(namespace, argv)
      begin
        value = Integer(argv[0])
      rescue
        return ''
      end
      if value == 0
        result = '5'
      elsif value == 1
        if @aya.charset == 'CP932'
          result = 0
        elsif @aya.charset == 'UTF-8'
          result = 1
        else
          result = 2
        end
      elsif value == 2
        result = @aya.aya_dir
      else
        result = ''
      end
      return result
    end

    def GETSTRBYTES(namespace, argv)
      line = argv[0].to_s
      if argv.length > 1
        begin
          value = Integer(argv[1])
        rescue
          value = 0
        end
      else
        value = 0
      end
      if value == 0
        result = line.encode('CP932', 'ignore').length
      elsif value == 1
        result = line.encode('utf-8', 'ignore').length
      elsif value == 2
        result = line.encode(@aya.charset, 'ignore').length
      else
        result = -1
      end
      return result
    end

    def GETTICKCOUNT(namespace, argv)
      past = Time.now - @aya.get_boot_time()
      return (past * 1000.0).to_i
    end

    def GETTIME(namespace, argv)
      year_, month_, day_, hour_, minute_, second_, wday_, yday_, isdst_ = time.localtime()
      wday_ = (wday_ + 1) % 7
      return [year_, month_, day_, wday_, hour_, minute_, second_]
    end

    def GETTYPE(namespace, argv)
      if argv[0].is_a?(Fixnum)
        result = 1
      elsif argv[0].is_a?(Float)
        result = 2
      elsif argv[0].is_a?(String)
        result = 3
      elsif 0 ## FIXME: array
        result = 4
      else
        result = 0
      end
      return result
    end

    def HEXSTRTOI(namespace, argv)
      begin
        return argv[0].to_s.to_i(16)
      rescue
        return 0
      end
    end

    def IARRAY(namespace, argv)
      return [] # AyaVariable.new('', new_array=1) ## FIXME
    end

    def INSERT(namespace, argv)
      line = argv[0].to_s
      begin
        start = Integer(argv[1])
      rescue
        return ''
      end
      to_insert = argv[2].to_s
      if start < 0
        start = 0
      end
      return [line[0..start-1], to_insert, line[start..-1]].join('')
    end

    def ISFUNC(namespace, argv)
      if not argv[0].is_a?(String)
        return 0
      elsif @aya.dic.get_function(argv[0]) != nil
        return 1
      elsif @aya.get_system_functions().exists(argv[0])
        return 2
      else
        return 0
      end
    end

    def ISINTSTR(namespace, argv)
      begin
        Integer(argv[0].to_s)
        return 1
      rescue
        return 0
      end
    end

    def ISREALSTR(namespace, argv)
      begin
        Float(argv[0].to_s)
        return 1
      rescue
        return 0
      end
    end

    def ISVAR(namespace, argv)
      var = argv[0].to_s
      if var.start_with?('_')
        if namespace.exists(var)
          return 2
        else
          return 0
        end
      else
        if @aya.get_global_namespace().exists(var)
          return 1
        else
          return 0
        end
      end
    end

    def LETTONAME(namespace, argv)
      var = argv[0].to_s
      value = argv[1]
      if not var
        return nil
      end
      target_namespace = select_namespace(namespace, var)
      target_namespace.put(var, value)
      return nil
    end

    def LOADLIB(namespace, argv)
      dll = argv[0].to_s
      result = 0
      if not dll.empty?
        if @charsetlib == nil
          @charsetlib = @aya.charset
        end
        @aya.saori_library.set_charset(@charsetlib)
        result = @aya.saori_library.load(dll, @aya.aya_dir)
        if result == 0
          @errno = 17
        end
      end
      return result
    end

    def LOG(namespace, argv)
      begin
        argv[0].to_f
      rescue
        return -1
      end
      if argv[0].to_f == 0
        return 0
      end
      result = math.log(argv[0].to_f)
      return select_math_type(result)
    end

    def LOG10(namespace, argv)
      begin
        argv[0].to_f
      rescue
        return -1
      end
      if argv[0].to_f == 0
        return 0
      end
      result = math.log10(argv[0].to_f)
      return select_math_type(result)
    end

    def LSO(namespace, argv)
      #pass
    end

    def MKDIR(namespace, argv)
      dirname = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, dirname)
      result = 0
      head, tail = File.split(path)
      if not File.directory?(head)
        @errno = 283
      else
        begin
          Dir.mkdir(path, 0o755)
        rescue
          @errno = 284
        else
          result = 1
        end
      end
      return result
    end

    def POW(namespace, argv)
      begin
        result = math.pow(argv[0].to_f, argv[1].to_f)
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def RAND(namespace, argv)
      if not argv
        return Random.rand(0..99)
      else
        begin
          Integer(argv[0])
        rescue
          return -1
        end
        return Random.rand(0..argv[0].to_i-1)
      end
    end

    def RE_GETLEN(namespace, argv)
      #pass
    end

    def RE_GETPOS(namespace, argv)
      #pass
    end

    def RE_GETSTR(namespace, argv)
      #result_array = AyaVariable.new('', new_array=1)
      #result_array.put(@re_result)
      #return result_array
      return @re_result
    end

    def RE_GREP(namespace, argv)
      #pass
    end

    def RE_MATCH(namespace, argv)
      #pass
    end

    def RE_REPLACE(namespace, argv)
      #pass
    end

    def RE_SEARCH(namespace, argv)
      #pass
    end

    def RE_SPLIT(namespace, argv)
      line = argv[0].to_s
      re_split = re.compile(argv[1].to_s)
      if argv.length > 2
        begin
          max = argv[2]
        rescue
          return []
        else
          result = re_split.split(line, max)
        end
      else
        result = re_split.split(line)
      end
      @re_result = re_split.findall(line)
      #result_array = AyaVariable.new('', new_array=1)
      #result_array.put(result)
      #return result_array
      return result
    end

    def REPLACE(namespace, argv)
      line = argv[0].to_s
      old = argv[1].to_s
      new = argv[2].to_s
      return line.gsub(old, new)
    end

    def REQUESTLIB(namespace, argv)
      response = @aya.saori_library.request(argv[0], argv[1])
      header = response.splitlines()
      @saori_statuscode = ''
      @saori_header = []
      @saori_value = {}
      @saori_protocol = ''
      if header and not header.empty?
        line = header.shift
        line = line.strip()
        if line.include?(' ')
          @saori_protocol, @saori_statuscode = line.split(' ', 2)
          @saori_protocol.strip!
          @saori_statuscode.strip!
        end
        for line in header
          if not line.include?(':')
            next
          end
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          if key
            @saori_header << key
            @saori_value[key] = value
          end
        end
      end
      return response
    end

    def RMDIR(namespace, argv)
      dirname = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, dirname)
      result = 0
      if not File.directory?(path)
        @errno = 287
      else
        begin
          Dir.rmdir(path)
        rescue
          @errno = 288
        else
          result = 1
        end
      end
      return result
    end

    def ROUND(namespace, argv)
      begin
        value = math.floor(Float(argv[0]) + 0.5)
      rescue
        return -1
      end
      return value.to_i
    end

    def SAVEVAR(namespace, argv)
      @aya.get_global_namespace().save_database()
    end

    def SETDELIM(namespace, argv)
      name = argv[0].to_s
      separator = argv[1].to_s
      target_namespace = select_namespace(namespace, name)
      target_namespace.set_separator(name, separator)
      return nil
    end

    def SETLASTERROR(namespace, argv)
      begin
        value = Integer(argv[0])
      rescue
        return
      end
      @errno = value
    end

    def SIN(namespace, argv)
      begin
        result = math.sin(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def SPLIT(namespace, argv)
      line = argv[0].to_s
      result = line.split(argv[1].to_s, argv[2].to_i + 1)
      return result
    end

    def SPLITPATH(namespace, argv)
      line = argv[0].to_s
      drive, path = os.path.splitdrive(line)
      dirname, filename = os.path.split(path)
      basename, ext = os.path.splitext(filename)
      return [drive, dirname, basename, ext]
    end

    def SQRT(namespace, argv)
      begin
        arg = Float(argv[0])
      rescue
        return -1
      end
      if arg < 0.0
        return -1
      else
        result = math.sqrt(arg)
        return select_math_type(result)
      end
    end

    def STRFORM(namespace, argv)
      #pass
    end

    def STRLEN(namespace, argv)
      line = argv[0].to_s
      return line.length
    end

    def STRSTR(namespace, argv)
      line = argv[0].to_s
      to_find = argv[1].to_s
      begin
        start = Integer(argv[2])
      rescue
        return -1
      end
      result = line.index(to_find, start)
      return result
    end

    def SUBSTR(namespace, argv)
      line = argv[0].to_s
      begin
        start = Integer(argv[1])
        num = Integer(argv[2])
      rescue
        return ''
      end
      return line[start..start + num-1]
    end

    def TAN(namespace, argv)
      begin
        result = math.tan(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def TOBINSTR(namespace, argv)
      begin
        i = Integer(argv[0])
      rescue
        return ''
      end
      if i < 0
        i = abs(i)
        numsin = '-'
      else
        numsin = ''
      end
      line = ''
      while i != 0
        mod = i % 2
        i = (i / 2).to_i
        line = [mod.to_s, line].join('')
      end
      line = [numsin, line].join('')
      return line
    end

    def TOHEXSTR(namespace, argv)
      begin
        return argv[0].to_i.to_s(16)
      rescue
        return ''
      end
    end

    def TOINT(namespace, argv)
      token = argv[0].to_s
      begin
        value = Integer(token)
      rescue
        return 0
      else
        return value
      end
    end

    def TOLOWER(namespace, argv)
      return argv[0].to_s.downcase
    end

    def TOREAL(namespace, argv)
      token = argv[0].to_s
      begin
        value = Float(token)
      rescue
        return 0.0
      else
        return value
      end
    end

    def TOSTR(namespace, argv)
      return argv[0].to_s
    end

    def TOUPPER(namespace, argv)
      return argv[0].to_s.upcase
    end

    def UNLOADLIB(namespace, argv)
      if not argv[0].to_s.empty?
        @aya.saori_library.unload(argv[0].to_s)
      end
      return nil
    end

    def LOGGING(namespace, argv) ## FIXME
      if argv[0] == nil
        return nil
      end
      logfile = argv[0]
      line = ['> function ', argv[1].to_s, ' ： ', argv[2].to_s].join('')
      if argv[3] != nil
        line = [line, ' = '].join('')
        if argv[3].is_a?(Fixnum) or argv[3].is_a?(Float)
          line = [line, argv[3].to_s].join('')
        else
          line = [line, '"', argv[3].to_s, '"'].join('')
        end
      end
      line = [line, "\n"].join('')
      logfile.write(line)
      logfile.write("\n")
      return nil
    end

    def select_math_type(value)
      if math.floor(value) == value
        return value.to_i
      else
        return value
      end
    end

    def select_namespace(namespace, name)
      if name.start_with?('_')
        return namespace
      else
        return @aya.get_global_namespace()
      end
    end
  end


  class AyaNamespace

    def initialize(aya, parent=nil)
      @aya = aya
      @parent = parent
      @table = {}
    end

    def put(name, content, index=nil)
      if @parent != nil and @parent.exists(name)
        @parent.put(name, content, index)
      elsif index == nil
        if not exists(name)
          @table[name] = AyaVariable.new(name)
        end
        @table[name].put(content)
      elsif exists(name) and index >=0
        @table[name].put(content, index)
      else
        #pass # ERROR
      end
    end

    def get(name, index=nil)
      if @table.include?(name)
        return @table[name].get(index)
      elsif @parent != nil and @parent.exists(name)
        return @parent.get(name, index)
      else
        return nil
      end
    end

    def get_array(name)
      if @table.include?(name)
        return @table[name].get_array()
      elsif @parent != nil and @parent.exists(name)
        return @parent.get_array(name)
      else
        return []
      end
    end

    def get_separator(name)
      if @parent != nil and @parent.exists(name)
        return @parent.get_separator(name)
      elsif @table.include?(name)
        @table[name].get_separator()
      else
        return '' # ERROR
      end
    end

    def set_separator(name, separator)
      if @parent != nil and @parent.exists(name)
        @parent.set_separator(name, separator)
      elsif @table.include?(name)
        @table[name].set_separator(separator)
      else
        #pass # ERROR
      end
    end

    def get_size(name)
      if @table.include?(name)
        return @table[name].get_size()
      elsif @parent != nil and @parent.exists(name)
        return @parent.get_size(name)
      else
        return 0
      end
    end

    def remove(name) # only works with local table
      if @table.include?(name)
        @table.delete(name)
      end
    end

    def exists(name)
      result = (@table.include?(name) or \
                (@parent != nil and @parent.exists(name)))
      return result
    end
  end


  class AyaGlobalNamespace < AyaNamespace

    def load_database(aya)
      begin
        open(aya.dbpath, encoding=@aya.charset) do |f|
          line = f.readline()
          if not line.start_with?('# Format: v1.2')
            return 1
          end
          for line in f
            comma = line.find(',')
            if comma >= 0
              key = line[:comma]
            else
              next
            end
            value = line[comma + 1..-1].strip()
            comma = find_not_quoted(value, ',')
            if comma >= 0
              separator = value[comma + 1..-1].strip()
              separator = separator[1..-2]
              value = value[0..comma-1].strip()
              value = value[1..-2]
              put(key, value)
              @table[key].set_separator(separator)
            elsif value != 'None'
              if value.include?('.')
                put(key, Float(value))
              else
                put(key, Integer(value))
              end
            else
              #pass
            end
          end
        end
      rescue
        return 1
      end
      return 0
    end

    def save_database
      begin
        open(@aya.dbpath, 'w', :encoding => @aya.charset) do |f|
          f.write("# Format: v1.2\n")
          for key in @table.keys()
            line = @table[key].dump()
            if line != nil
              f.write([line, "\n"].join(''))
            end
          end
        end
      rescue #except IOError:
        Logging::Logging.debug('aya.py: cannot write database (ignored)')
        return
      end
    end
  end


  class AyaStatement
    attr_reader :tokens

    SPECIAL_CHARS = '=+-*/<>|&!:,_'

    def initialize(line)
      @n_tokens = 0
      @tokens = []
      @position_of_next_token = 0
      tokenize(line)
    end

    def tokenize(line) ## FIXME: '[', ']'
      token_startpoint = 0
      block_nest_level = 0
      length = line.length
      i = 0
      while i < length
        c = line[i]
        if c == '('
          block_nest_level += 1
          append_unless_empty(line[token_startpoint..i-1].strip())
          @tokens << '('
          i += 1
          token_startpoint = i
        elsif c == ')'
          block_nest_level -= 1
          append_unless_empty(line[token_startpoint..i-1].strip())
          @tokens << ')'
          i += 1
          token_startpoint = i
        elsif c == '['
          append_unless_empty(line[token_startpoint..i-1].strip())
          @tokens << '['
          i += 1
          token_startpoint = i
        elsif c == ']'
          append_unless_empty(line[token_startpoint..i-1].strip())
          @tokens << ']'
          i += 1
          token_startpoint = i
        elsif c == '"'
          position = line.index('"', i + 1)
          if not position or position < 0 ## FIXME
            raise SystemExit ## FIXME
          end
          i = position
          @tokens << line[token_startpoint..position]
          token_startpoint = position + 1
          i = position + 1
        elsif c == "'"
          position = line.index("'", i + 1)
          if not position or position < 0 ## FIXME
            raise SystemExit ## FIXME
          end
          i = position
          @tokens << line[token_startpoint..position]
          token_startpoint = position + 1
          i = position + 1
        elsif c == ' ' or c == '\t' or c == '　'
          append_unless_empty(line[token_startpoint..i-1].strip())
          i += 1
          token_startpoint = i
        elsif SPECIAL_CHARS.include?(c)
          ope_list = ['!_in_', '_in_',
                      '+:=', '-:=', '*:=', '/:=', '%:=',
                      ':=', '+=', '-=', '*=', '/=', '%=', '<=',
                      '>=', '==', '!=', '&&', '||', ',=', '++', '--',
                      ',', '=', '!', '+', '-', '/', '*', '%', '&']
          break_flag = false
          for ope in ope_list
            if line[i..-1].start_with?(ope) ## FIXME
              if i != 0
                append_unless_empty(line[token_startpoint..i-1].strip())
              end
              num = ope.length
              @tokens << line[i..i + num -1]
              i += num
              token_startpoint = i
              break_flag = true
              break
            end
          end
          if not break_flag
            i += 1
          end
        else
          i += 1
        end
      end
      append_unless_empty(line[token_startpoint..-1].strip())
      @n_tokens = @tokens.length
    end

    def append_unless_empty(token)
      if token and not token.empty?
        @tokens << token
      end
    end

    def has_more_tokens
      return (@position_of_next_token < @n_tokens)
    end

    def countTokens
      return @n_tokens
    end

    def next_token
      if not has_more_tokens()
        return nil
      end
      result = @tokens[@position_of_next_token]
      @position_of_next_token += 1
      return result
    end
  end


  class AyaVariable

    TYPE_STRING = 0
    TYPE_INT = 1
    TYPE_REAL = 2
    TYPE_ARRAY = 3
    TYPE_NEW_ARRAY = 4

    def initialize(name, new_array=false)
      @name = name
      @line = ''
      @separator = ','
      if new_array
        @type = TYPE_NEW_ARRAY
      else
        @type = nil
      end
      @array = []
    end

    def get_array
      return @array
    end

    def get_separator
      return @separator
    end

    def set_separator(separator)
      if @type != TYPE_STRING
        return
      end
      @separator = separator
      reset()
    end

    def reset
      if @type != TYPE_STRING
        return
      end
      @position = 0
      @is_empty = false
      @array = []
      while not @is_empty
        separator_position = @line.index(@separator, @position)
        if not separator_position
          token = @line[@position..-1]
          @is_empty = true
        else
          token = @line[@position..separator_position-1]
          @position = separator_position + @separator.length
        end
        @array << token
      end
    end

    def get_size
      return @array.length
    end

    def get(index=nil)
      if index == nil
        if @type == TYPE_STRING
          result = @line.to_s
        elsif @type == TYPE_INT
          result = @line.to_i
        elsif @type == TYPE_REAL
          result = @line.to_f
        elsif @type == TYPE_NEW_ARRAY
          result = @array ## FIXME(?)
        else
          result = ''
        end
        return result
      end
      if 0 <= index and index < @array.length
        value = @array[index]
        if @type == TYPE_STRING
          result = value.to_s
        elsif @type == TYPE_INT
          result = value.to_i
        elsif @type == TYPE_REAL
          result = value.to_f
        elsif @type == TYPE_ARRAY
          result = value
        elsif @type == TYPE_NEW_ARRAY
          result = value ## FIXME
        else
          result = nil # should not reach here
        end
      elsif index == nil
        if @type == TYPE_STRING
          result = @line.to_s
        elsif @type == TYPE_INT
          result = @line.to_i
        elsif @type == TYPE_REAL
          result = @line.to_f
        elsif @type == TYPE_NEW_ARRAY
          result = @array ## FIXME(?)
        else
          result = ''
        end
      else
        result = ''
      end
      return result
    end

    def put(value, index=nil)
      if index == nil
        @line = value.to_s
        if value.is_a?(String)
          @type = TYPE_STRING
        elsif value.is_a?(Fixnum)
          @type = TYPE_INT
        elsif value.is_a?(Float)
          @type = TYPE_REAL
        elsif value.is_a?(Array)
          @type = TYPE_NEW_ARRAY # CHECK
          @array = value
        end
        reset()
      elsif index < 0
        #pass
      else
        if @type == TYPE_STRING
          @line = ''
          for i in 0..@array.length-1
            if i == index
              @line = [@line, value.to_s].join('')
            else
              @line = [@line, @array[i]].join('')
            end
            if i != @array.length-1
              @line = [@line, @separator].join('')
            end
          end
          if index >= @array.length
            for i in @array.length..index
              if i == index
                @line = [@line, @separator,
                         value.to_s].join('')
              else
                @line = [@line, @separator,
                         ''].join('')
              end
            end
          end
          reset()
        elsif @type == TYPE_ARRAY
          if 0 <= index and index < @array.length
            @array[index] = value
          end
        elsif @type == TYPE_NEW_ARRAY
          if 0 <= index and index < @array.length
            @array[index] = value
          elsif index > 0 ## FIXME
            for _ in @array.length..index-2
              @array << '' # XXX
            end
            @array << value
            ##print(@array, index, value)
            Logging::Logging.info('!!! WARNING !!!')
            Logging::Logging.info('NOT YET IMPLEMENTED')
          else
            #pass # ERROR
          end
        else
          #pass # ERROR
        end
      end
    end

    def dump
      line = nil
      if @type == TYPE_STRING
        line = @name.to_s + ', "' + @line.to_s + '", "' + @separator.to_s + '"'
      elsif @type == TYPE_NEW_ARRAY
        #pass ## FIXME
      elsif @type != TYPE_ARRAY
        line = @name.to_s + ', ' + @line.to_s
      else
        #pass
      end
      return line
    end
  end


  class AyaArgument

    def initialize(line)
      @line = line.strip()
      @length = @line.length
      @current_position = 0
    end

    def has_more_tokens
      return (@current_position != -1 and \
              @current_position < @length)
    end

    def next_token
      if not has_more_tokens()
        return nil
      end
      startpoint = @current_position
      @current_position = position_of_next_token()
      if @current_position == -1
        token = @line[startpoint..-1]
      else
        token = @line[startpoint..@current_position-2]
      end
      return token.strip()
    end

    def position_of_next_token
      locked = true
      position = @current_position
      parenthesis_nest_level = 0
      while position < @length
        c = @line[position]
        if c == '"'
          if not locked
            return position
          end
          while position < @length-1
            position += 1
            if @line[position] == '"'
              break
            end
          end
        elsif c == '('
          parenthesis_nest_level += 1
        elsif c == ')'
          parenthesis_nest_level -= 1
        elsif c == ','
          if parenthesis_nest_level == 0
            locked = false
          end
        else
          if not locked
            return position
          end
        end
        position += 1
      end
      return -1
    end
  end


  class AyaSaoriLibrary

    def initialize(saori, top_dir)
      @saori_list = {}
      @saori = saori
      @current_charset = nil
      @charset = {}
    end

    def set_charset(charset)
      ##assert ['CP932', 'Shift_JIS', 'UTF-8'].include?(charset)
      @current_charset = charset
    end

    def load(name, top_dir)
      result = 0
      head, name = File.split(name.gsub("\\", '/')) # XXX: don't encode here
      top_dir = File.join(top_dir, head)
      if @saori and not @saori_list.include?(name)
        module_ = @saori.request(name)
        if module_
          @saori_list[name] = module_
        end
      end
      if @saori_list.include?(name)
        result = @saori_list[name].load(:dir => top_dir)
      end
      @charset[name] = @current_charset
      return result
    end

    def unload(name=nil)
      if name
        name = File.split(name.gsub("\\", '/'))[-1] # XXX: don't encode here
        if @saori_list.include?(name)
          @saori_list[name].unload()
          @saori_list.delete(name)
          @charset.delete(name)
        end
      else
        for key in @saori_list.keys()
          @saori_list[key].unload()
        end
      end
      return nil
    end

    def request(name, req)
      result = '' # FIXME
      name = File.split(name.gsub("\\", '/'))[-1] # XXX: don't encode here
      if name and @saori_list.include?(name)
        result = @saori_list[name].request(
          req.encode(@current_charset))
      end
      return str(result, @current_charset)
    end
  end
end
