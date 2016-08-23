# -*- coding: utf-8 -*-
#
#  satori.rb - a "里々" compatible Shiori module for ninix
#  Copyright (C) 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003, 2004 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# - φエスケープ： 特殊記号の無効化, replaceの無効化など
# - イベントを単語群で定義できるように
# - 文と単語群の重複回避
# - ≫
# - コミュニケート
# - 内部呼び出し: 単語の追加, sync
# - ＄トーク中のなでられ反応
# - ＄BalloonOffset0, ＄BalloonOffset1
# - マルチキャラクタ


require "pathname"

require_relative "../home"
require_relative "../logging"


module Satori

  NODE_TEXT       = 1
  NODE_REF        = 2
  NODE_SIDE       = 3
  NODE_ASSIGNMENT = 4
  NODE_JUMP       = 5
  NODE_SEARCH     = 6
  NODE_CHOICE     = 7
  NODE_CALL       = 8
  NODE_SAORI      = 9
  NODE_OR_EXPR    = 20
  NODE_AND_EXPR   = 21
  NODE_COMP_EXPR  = 22
  NODE_ADD_EXPR   = 23
  NODE_MUL_EXPR   = 24
  NODE_POW_EXPR   = 25
  NODE_UNARY_EXPR = 26

  def self.encrypt(s)
    buf = []
    t = s.length
    p = ((t + 1) / 2).to_i
    for n in 0..p-1
      buf << s[n]
      if s[p..-1].length > n
        buf << s[-n - 1]
      end
    end
    return buf
  end

  def self.decrypt(s)
    buf = []
    t = s.length
    for n in 0.step(t-1, 2)
      buf << s[n..-1][0..0] # XXX
    end
    if (t % 2).zero?
      p = 1
    else
      p = 2
    end
    for n in p.step(t-1, 2)
      buf << s[-n..-1][0..0] # XXX
    end
    return buf.join('')
  end

  def self.list_dict(top_dir)
    buf = []
    begin
      dir_list = Pathname(top_dir).children().map {|x| x.relative_path_from(Pathname(top_dir)).to_path }
    rescue #except OSError:
      dir_list = []
    end
    for filename in dir_list
      basename = File.basename(filename, '.*')
      ext = File.extname(filename)
      ext = ext.downcase
      if (filename.downcase.start_with?('dic') and \
          ['.txt', '.sat'].include?(ext)) or \
        ['replace.txt', 'replace_after.txt',
         'satori_conf.txt', 'satori_conf.sat'].include?(filename.downcase) # XXX
        buf << File.join(top_dir, filename)
      end
    end
    return buf
  end


  class Filter

    def initialize(rules)
      @rules = []
      for pat, rep in rules
        @rules << [pat, rep]
      end
    end

    def apply(text)
      for pat, rep in @rules
        text = text.gsub(pat, rep)
      end
      return text
    end
  end

  ###   PARSER   ###

  def self.read_tab_file(path, encrypted: false)
    lineno = 0
    buf = []
    open(path, 'rb') do |f|
      for line in f
        lineno += 1
        if line.end_with?("\r\n")
          line = line[0..-3]
        elsif line.end_with?("\r") or line.end_with?("\n")
          line = line[0..-2]
        end
        if encrypted
          line = Satori.decrypt(Satori.decrypt(line))
        end
        begin
          line = line.force_encoding('CP932').encode('utf-8', :invalid => :replace, :undef => :replace)
        rescue => e #except UnicodeError as e:
          Logging::Logging.debug('satori.py: ' + e.to_s + ' in ' + path.to_s + ' (line ' + lineno.to_s + ')')
          next
        end
        begin
          old, new = line.split("\t", 2)
        rescue #except ValueError:
          Logging::Logging.debug('satori.py: invalid line in ' + path.to_s + ' (line ' + lineno.to_s + ')')
          next
        end
        unless old.nil? or new.nil?
          buf << [old, new]
        end
      end
    end
    return buf
  end


  class Parser
    attr_reader :anchor_filter, :talk, :word

    def initialize
      @talk = {}
      @word = {}
      @variable = []
      @parenthesis = 0
      @replace_filter = Filter.new([])
      @anchor_list = []
      @anchor_filter = Filter.new(@anchor_list)
      @is_anchor = false
      @saori = []
      @separator = ["\1", ',', '，', '、', '､']
      @count = {'Talk' =>        0,
                'NoNameTalk' =>  0,
                'EventTalk' =>   0,
                'OtherTalk' =>   0,
                'Words' =>       0,
                'Word' =>        0,
                'Variable' =>    0,
                'Anchor' =>      0,
                'Parenthesis' => 0,
                'Parentheres' => 0, ## XXX
                'Line' =>        0,}
    end

    def set_saori(saori_list)
      @saori = saori_list
    end

    def get_count(name)
      if @count.include?(name)
        return @count[name]
      else
        return 0
      end
    end

    def load_replace_file(path)
      @replace_filter = Filter.new(Satori.read_tab_file(path))
    end

    def get_dict
      return @talk, @word
    end

    def read(path)
      basename = File.basename(path, '.*')
      ext = File.extname(path)
      ext = ext.downcase
      if ext == '.sat'
        encrypted = true
      else
        encrypted = false
      end
      filename = File.basename(path)
      if filename.downcase.start_with?('dicanchor') # XXX
        @is_anchor = true
      else
        @is_anchor = false
      end
      open(path, 'rb') do |f|
        read_file(f, :path => path, :encrypted => encrypted)
      end
      if @is_anchor
        @anchor_filter = Filter.new(@anchor_list)
      end
    end

    def read_file(f, path: nil, encrypted: false)
      lineno = 0
      linelist = []
      line_buffer = nil # XXX
      phi_escape = {} # key = lineno: [position]
      parser = nil # XXX
      for line in f
        if line_buffer.nil?
          lineno += 1
          phi_escape[lineno] = []
        end
        if line.end_with?("\r\n")
          line = line[0..-3]
        elsif line.end_with?("\r") or line.end_with?("\n")
          line = line[0..-2]
        end
        if encrypted
          line = Satori.decrypt(Satori.decrypt(line))
        end
        begin
          line = line.force_encoding('CP932').encode('utf-8', :invalid => :replace, :undef => :replace)
        rescue => e #except UnicodeError as e:
          if path.nil?
            Logging::Logging.debug('satori.py: ' + e.to_s + ' (line ' + lineno.to_s + ')')
          else
            Logging::Logging.debug('satori.py: ' + e.to_s + ' in ' + path.to_s + ' (line ' + lineno.to_s + ')')
          end
          next
        end
        unless line_buffer.nil?
          line = [line_buffer, line].join('')
          line_buffer = nil
        end
        pos = 0
        while line[pos..-1].count('φ') >0
          pos = line.index('φ', pos)
          if pos == (line.length - 1)
            line_buffer = line[0..-2]
            break
          else
            phi_escape[lineno] << pos
            if pos.zero?
              line = line[1..-1]
            else
              line = [line[0..pos-1], line[pos + 1..-1]].join('')
            end
          end
        end
        next unless line_buffer.nil?
        pos = 0
        while line[pos..-1].count('＃') > 0
          pos = line.index('＃', pos)
          unless phi_escape[lineno].include?(pos) ## FIXME
            if pos.zero?
              line = ""
            else
              line = line[0..pos-1]
            end
            break
          end
        end
        if line.nil? or line.empty?
          next
        end
        if line.start_with?('＊') and not phi_escape[lineno].include?(0)
          unless linelist.empty?
            method(parser).call(linelist, phi_escape)
          end
          parser = 'parse_talk'
          linelist = [lineno, line]
        elsif line.start_with?('＠') and not phi_escape[lineno].include?(0)
          unless linelist.empty?
            method(parser).call(linelist, phi_escape)
          end
          parser = 'parse_word_group'
          linelist = [lineno, line]
        elsif not linelist.empty?
          # apply replace.txt
          line = @replace_filter.apply(line) ## FIXME: phi_escape
          linelist << line
        end
      end
#        for no in phi_escape:
#            if phi_escape[no]:
#                print('PHI:', no, phi_escape[no])
#            end
#        end
      unless linelist.empty?
        method(parser).call(linelist, phi_escape)
      end
      @count['Line'] = @count['Line'] + lineno
      talk = 0
      eventtalk = 0
      for key in @talk.keys
        value = @talk[key]
        number = value.length
        talk += number
        if key.start_with?('On')
          eventtalk += number
        end
      end
      @count['Talk'] = talk
      @count['EventTalk'] = eventtalk
      if @talk.include?('')
        @count['NoNameTalk'] = @talk[''].length
      end
      @count['OtherTalk'] = (@count['Talk'] \
                             - @count['NoNameTalk'] \
                             - @count['EventTalk'])
      @count['Words'] = @word.length
      word = 0
      for value in @word.values()
        word += value.length
      end
      @count['Word'] = word
      @count['Anchor'] = @anchor_list.length
      @count['Variable'] = @variable.length
      @count['Parenthesis'] = @parenthesis
      @count['Parentheres'] = @parenthesis
    end

    def parse_talk(linelist, phi_escape)
      lineno = linelist[0]
      buf = []
      line = linelist[1]
      fail "assert" unless line.start_with?('＊')
      name = line[1..-1]
      while linelist.length > 3 and not linelist[-1]
        linelist.delete_at(-1)
      end
      prev = ''
      num_open = 0
      num_close = 0
      for n in 2..linelist.length-1
        line = linelist[n]
        num_open += line.count('（') ### FIXME: φ
        num_close += line.count('）') ### FIXME: φ
        if num_open > 0 and num_open != num_close
          if n == (linelist.length - 1)
            Logging::Logging.debug(
              'satori.py: syntax error (unbalanced parens)')
          else
            prev = [prev, linelist[n]].join('')
            next
          end
        else
          num_open = 0
          num_close = 0
        end
        line = [prev, linelist[n]].join('')
        prev = ''
        current_lineno = (lineno + n - 2)
        if not line.empty? and line[0] == '＄' and not phi_escape[current_lineno].include?(0)
          node = parse_assignment(line)
          unless node.nil?
            buf << node
          end
        elsif not line.empty? and line[0] == '＞' and not phi_escape[current_lineno].include?(0)
          node = parse_jump(line)
          unless node.nil?
            buf << node
          end
        elsif not line.empty? and line[0] == '≫' and not phi_escape[current_lineno].include?(0)
          node = parse_search(line)
          unless node.nil?
            buf << node
          end
        elsif not line.empty? and line[0] == '＿' and not phi_escape[current_lineno].include?(0)
          node = parse_choice(line)
          unless node.nil?
            buf << node
          end
        else
          nodelist = parse_talk_word(line)
          unless nodelist.nil?
            buf.concat(nodelist)
          end
        end
      end
      unless buf.empty?
        if @talk.include?(name)
          talk_list = @talk[name]
        else
          talk_list = @talk[name] = []
        end
        talk_list << buf
        if @is_anchor
          @anchor_list << [name, "\\_a[" + name.to_s + ']' + name.to_s + "\\_a"]
        end
      end
    end

    def parse_word_group(linelist, phi_escape)
      lineno = linelist[0]
      buf = []
      line = linelist[1]
      fail "assert" unless line.start_with?('＠')
      name = line[1..-1]
      prev = ''
      num_open = 0
      num_close = 0
      for n in 2..linelist.length-1
        line = linelist[n]
        num_open += line.count('（') ### FIXME: φ
        num_close += line.count('）') ### FIXME: φ
        if num_open > 0 and num_open != num_close
          if n == (linelist.length - 1)
            Logging::Logging.debug(
              'satori.py: syntax error (unbalanced parens)')
          else
            prev = [prev, linelist[n]].join('')
            next
          end
        else
          num_open = 0
          num_close = 0
        end
        line = [prev, linelist[n]].join('')
        prev = ''
        next if line.empty?
        word = parse_word(line)
        unless word.nil?
          buf << word
        end
      end
      unless buf.empty?
        if @word.include?(name)
          word_list = @word[name]
        else
          word_list = @word[name] = []
        end
        word_list.concat(buf)
      end
    end

    def parse_assignment(line)
      fail "assert" unless line[0] == '＄'
      break_flag = false
      for n in 1..line.length-1
        if ["\t", ' ', '　', '＝'].include?(line[n]) ### FIXME: φ
          break_flag = true
          break
        end
      end
      unless break_flag
        Logging::Logging.debug('satori.py: syntax error (expected a tab or equal)')
        return nil
      end
      name_str = line[1..n-1] #.join('') # XXX
      name = parse_word(line[1..n-1])
      if line[n] == '＝' ### FIXME: φ
        n += 1
        value = parse_expression(line[n..-1])
      else
        sep = line[n]
        while n < line.length and line[n] == sep
          n += 1
        end
        value = parse_word(line[n..-1])
      end
      if name_str == '引数区切り削除'
        sep = line[n..-1] #.join('') # XXX
        if @separator.include?(sep)
          @separator.delete(sep)
        end
        return nil
      elsif name_str == '引数区切り追加'
        sep = line[n..-1] #.join('') # XXX
        unless @separator.include?(sep)
          @separator << sep
        end
        return nil
      end
      unless @variable.include?(name)
        @variable << name
      end
      return [NODE_ASSIGNMENT, name, value]
    end

    def parse_jump(line)
      fail "assert" unless line[0] == '＞'
      break_flag = false
      for n in 1..line.length-1
        if line[n] == "\t" ### FIXME: φ
          break_flag = true
          break
        end
      end
      unless break_flag
        n = line.length
      end
      target = parse_word(line[1..n-1])
      while n < line.length and line[n] == "\t" ### FIXME: φ
        n += 1
      end
      if n < line.length
        condition = parse_expression(line[n..-1])
      else
        condition = nil
      end
      return [NODE_JUMP, target, condition]
    end

    def parse_search(line)
      return [NODE_SEARCH]
    end

    def parse_choice(line)
      fail "assert" unless line[0] == '＿'
      break_flag = false
      for n in 1..line.length-1
        if line[n] == "\t" ### FIXME: φ
          break_flag = true
          break
        end
      end
      unless break_flag
        n = line.length
      end
      label = parse_word(line[1..n-1])
      while n < line.length and line[n] == "\t" ### FIXME: φ
        n += 1
      end
      if n < line.length
        id_ = parse_word(line[n..-1])
      else
        id_ = nil
      end
      return [NODE_CHOICE, label, id_]
    end

    def parse_talk_word(line)
      buf = parse_word(line)
      buf << [NODE_TEXT, ["\\n"]]
      return buf
    end

    def parse_word(line)
      buffer_ = []
      text = []
      while not line.nil? and not line.empty?
        if line[0] == '：' ### FIXME: φ
          unless text.empty?
            buffer_ << [NODE_TEXT, text]
            text = []
          end
          buffer_ << [NODE_SIDE, [line[0]]]
          line = line[1..-1]
        elsif line[0] == '（' ### FIXME: φ
          @parenthesis += 1
          unless text.empty?
            buffer_ << [NODE_TEXT, text]
            text = []
          end
          line = parse_parenthesis(line, buffer_)
        else
          text << line[0]
          line = line[1..-1]
        end
      end
      unless text.empty?
        buffer_ << [NODE_TEXT, text]
      end
      return buffer_
    end

    def find_close(text, position)
      nest = 0
      current = position
      while text[current..-1].count('）') > 0
        pos_new = text.index('）', current)
        break if pos_new.zero?
        nest = text[position..pos_new-1].count('（') - text[position..pos_new-1].count('）')
        if nest > 0
          current = (pos_new + 1)
        else
          current = pos_new
          break
        end
      end
      return current
    end

    def split_(text, sep)
      buf = []
      pos_end = -1
      while true
        position = text.index('（', pos_end + 1)
        if position.nil? or position == -1
          ll = text[pos_end + 1..-1].split(sep, -1)
          if buf.length > 0
            last = buf.pop()
            buf << [last, ll[0]].join('')
            unless ll[1..-1].nil?
              buf.concat(ll[1..-1])
            end
          else
            buf.concat(ll)
          end
          break
        else
          if position.zero?
            ll = [""]
          else
            ll = text[pos_end + 1..position-1].split(sep, -1)
          end
          pos_end = find_close(text, position + 1)
          last = ll.pop()
          ll << [last, text[position..pos_end]].join('')
          if buf.length > 0
            last = buf.pop()
            buf << [last, ll[0]].join('')
            unless ll[1..-1].nil?
              buf.concat(ll[1..-1])
            end
          else
            buf.concat(ll)
          end
        end
      end
      buf = buf.map {|x| x.strip() }
      return buf
    end

    def parse_parenthesis(line, buf)
      text_ = []
      fail "assert" unless line[0] == '（'
      line = line[1..-1] ## FIXME
      depth = 1
      count = 1
      while not line.nil? and not line.empty?
        if line[0] == '）' ### FIXME: φ
          depth -= 1
          if text_.length != count # （）
            text_ << ''
          end
          if depth.zero?
            line = line[1..-1]
            break
          end
          text_ << line[0]
          line = line[1..-1]
        elsif line[0] == '（' ### FIXME: φ
          depth += 1
          count += 1
          text_ << line[0]
          line = line[1..-1]
        else
          text_ << line[0]
          line = line[1..-1]
        end
      end
      unless text_.empty?
        sep = nil
        pos = text_.length
        for c in @separator ### FIXME: φ
          next if text_.count(c).zero?
          if text_.index(c) < pos
            pos = text_.index(c)
            sep = c
          end
        end
        unless sep.nil?
          list_ = split_(text_.join(''), sep) ## FIXME
        else
          list_ = [text_.join('')]
        end
        if ['単語の追加', 'sync', 'loop', 'call',
            'set', 'remember', 'nop', '合成単語群',
            'when', 'times', 'while', 'for'].include?(list_[0]) or list_[0].end_with?('の数')
          function = list_[0]
          args = []
          if list_.length > 1
            for i in 1..list_.length-1
              args << parse_expression(list_[i])
            end
          end
          buf << [NODE_CALL, function, args]
          return line
        elsif @saori.include?(list_[0])
          function = list_[0]
          args = []
          if list_.length > 1
            for i in 1..list_.length
              # XXX: parse as text
              args << parse_word(list_[i])
            end
          end
          buf << [NODE_SAORI, function, args]
          return line
        else
          if list_.length > 1 # XXX
            nodelist = [[NODE_TEXT, ['（']]]
            nodelist.concat(parse_word(text_))
            nodelist << [NODE_TEXT, ['）']]
            buf << [NODE_REF, nodelist]
            return line
          else
            nodelist = [[NODE_TEXT, ['（']]]
            nodelist.concat(parse_word(text_))
            nodelist << [NODE_TEXT, ['）']]
            buf << [NODE_REF, nodelist]
            return line
          end
        end
      end
      buf << [NODE_TEXT, ['']] # XXX
      return line
    end

    def parse_expression(line)
      default = [[NODE_TEXT, line[0..-1]]]
      begin
        line, buf = get_or_expr(line)
      rescue #except ValueError as e:
        return default
      end
      return default unless line.nil? or line.empty?
      return buf
    end

    def get_or_expr(line)
      line, and_expr = get_and_expr(line)
      buf = [NODE_OR_EXPR, and_expr]
      while not line.nil? and not line.empty? and ['|', '｜'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        if not line.nil? and not line.empty? and ['|', '｜'].include?(line[0]) ### FIXME: φ
          line = line[1..-1]
        else
          fail ValueError('broken OR operator')
        end
        line, and_expr = get_and_expr(line)
        buf << and_expr
      end
      if buf.length == 2
        return line, buf[1]
      end
      return line, [buf]
    end

    def get_and_expr(line)
      line, comp_expr = get_comp_expr(line)
      buf = [NODE_AND_EXPR, comp_expr]
      while not lin.nil? and not line.empty? and ['&', '＆'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        if not line.nil? and not line.empty? and ['&', '＆'].include?(line[0]) ### FIXME: φ
          line = line[1..-1]
        else
          fail ValueError('broken AND operator')
        end
        line, comp_expr = get_comp_expr(line)
        buf << comp_expr
      end
      if buf.length == 2
        return line, buf[1]
      end
      return line, [buf]
    end

    def get_comp_expr(line)
      line, buf = get_add_expr(line)
      if not line.nil? and not line.empty? and ['<', '＜'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        op = '<'
        if not line.nil? and not line.empty? and ['=', '＝'].include?(line[0]) ### FIXME: φ
          line = line[1..-1]
          op = '<='
        end
        line, add_expr = get_add_expr(line)
        return line, [[NODE_COMP_EXPR, buf, op, add_expr]]
      elsif not line.nil? and not line.empty? and ['>', '＞'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        op = '>'
        if not line.nil? and not line.empty? and ['=', '＝'].include?(line[0]) ### FIXME: φ
          line = line[1..-1]
          op = '>='
        end
        line, add_expr = get_add_expr(line)
        return line, [[NODE_COMP_EXPR, buf, op, add_expr]]
      elsif not line.nil? and not line.empty? and ['=', '＝'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        if not line.nil? and not line.empty? and ['=', '＝'].include?(line[0]) ### FIXME: φ
          line = line[1..-1]
        else
          fail ValueError('broken EQUAL operator')
        end
        line, add_expr = get_add_expr(line)
        return line, [[NODE_COMP_EXPR, buf, '==', add_expr]]
      elsif not line.nil? and not line.empty? and ['!', '！'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        if not line.nil? and not line.empty? and ['=', '＝'].include?(line[0]) ### FIXME: φ
          line = line[1..-1]
        else
          fail ValueError('broken NOT EQUAL operator')
        end
        line, add_expr = get_add_expr(line)
        return line, [[NODE_COMP_EXPR, buf, '!=', add_expr]]
      end
      return line, buf
    end

    def get_add_expr(line)
      line, mul_expr = get_mul_expr(line)
      buf = [NODE_ADD_EXPR, mul_expr]
      while not line.nil? and not line.empty? and ['+', '＋', '-', '−', '－'].include?(line[0]) ### FIXME: φ
        if ['+', '＋'].include?(line[0])
          buf << '+'
        else
          buf << '-'
        end
        line = line[1..-1]
        line, mul_expr = get_mul_expr(line)
        buf << mul_expr
      end
      if buf.length == 2
        return line, buf[1]
      end
      return line, [buf]
    end

    def get_mul_expr(line)
      line, pow_expr = get_pow_expr(line)
      buf = [NODE_MUL_EXPR, pow_expr]
      while not line.nil? and not line.empty? and \
           ['*', '＊', '×', '/', '／', '÷', '%', '％'].include?(line[0]) ### FIXME: φ
        if ['*', '＊', '×'].include?(line[0])
          buf << '*'
        elsif ['/', '／', '÷'].include?(line[0])
          buf << '/'
        else
          buf << '%'
        end
        line = line[1..-1]
        line, pow_expr = get_pow_expr(line)
        buf << pow_expr
      end
      if buf.length == 2
        return line, buf[1]
      end
      return line, [buf]
    end

    def get_pow_expr(line)
      line, unary_expr = get_unary_expr(line)
      buf = [NODE_POW_EXPR, unary_expr]
      while not line.nil? and not line.empty? and ['^', '＾'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        line, unary_expr = get_unary_expr(line)
        buf << unary_expr
      end
      if buf.length == 2
        return line, buf[1]
      end
      return line, [buf]
    end

    def get_unary_expr(line)
      if not line.nil? and not line.empty? and ['-', '−', '－'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        line, unary_expr = get_unary_expr(line)
        return line, [[NODE_UNARY_EXPR, '-', unary_expr]]
      end
      if not line.nil? and not line.empty? and ['!', '！'].include?(line[0]) ### FIXME: φ
        line = line[1..-1]
        line, unary_expr = get_unary_expr(line)
        return line, [[NODE_UNARY_EXPR, '!', unary_expr]]
      end
      if not line.nil? and not line.empty? and line[0] == '(' ### FIXME: φ
        line = line[1..-1]
        line, buf = get_or_expr(line)
        if not line.nil? and not line.empty? and line[0] == ')' ### FIXME: φ
          line = line[1..-1]
        else
          fail ValueError('expected a close paren')
        end
        return line, buf
      end
      return get_factor(line)
    end

    Operators = [
        '|', '｜', '&', '＆', '<', '＜', '>', '＞', '=', '＝', '!', '！',
        '+', '＋', '-', '−', '－', '*', '＊', '×', '/', '／', '÷', '%', '％',
        '^', '＾', '(', ')']

    def get_factor(line)
      buf = []
      while not line.nil? and not line.empty? and not Operators.include?(line[0])
        if not line.nil? and not line.empty? and line[0] == '（' ### FIXME: φ
          line = parse_parenthesis(line, buf)
          next
        end
        text = []
        while not line.nil? and not line.empty? and not Operators.include?(line[0]) and line[0] != '（' ### FIXME: φ
          text << line[0]
          line = line[1..-1]
        end
        unless text.empty?
          buf << [NODE_TEXT, text]
        end
      end
      if buf.empty?
        fail ValueError('expected a constant')
      end
      return line, buf
    end

    def print_nodelist(node_list, depth: 0)
      for node in node_list
        indent = ('  ' * depth)
        case node[0]
        when NODE_TEXT
          temp = node[1].map {|x| x.encode('utf-8', :invalid => :replace, :undef => :replace) }.join('')
          print([indent, 'NODE_TEXT "' + temp + '"'].join(''), "\n")
        when NODE_REF
          print([indent, 'NODE_REF'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
        when NODE_CALL
          print([indent, 'NODE_CALL'].join(''), "\n")
          for i in 0..node[2].length-1
            print_nodelist(node[2][i], :depth => depth + 1)
          end
        when NODE_SAORI
          print([indent, 'NODE_SAORI'].join(''), "\n")
          for i in 0..node[2].length-1
            print_nodelist(node[2][i], :depth => depth + 1)
          end
        when NODE_SIDE
          print([indent, 'NODE_SIDE'].join(''), "\n")
        when NODE_ASSIGNMENT
          print([indent, 'NODE_ASSIGNMENT'].join(''), "\n")
          print([indent, 'variable'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          print([indent, 'value'].join(''), "\n")
          print_nodelist(node[2], :depth => depth + 1)
        when NODE_JUMP
          print([indent, 'NODE_JUMP'].join(''), "\n")
          print([indent, 'name'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          unless node[2].nil?
            print([indent, 'condition'].join(''), "\n")
            print_nodelist(node[2], :depth => depth + 1)
          end
        when NODE_SEARCH
          print([indent, 'NODE_SEARCH'].join(''), "\n")
        when NODE_CHOICE
          print([indent, 'NODE_CHOICE'].join(''), "\n")
          print([indent, 'label'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          unless node[2].nil?
            print([indent, 'id'].join(''), "\n")
            print_nodelist(node[2], :depth => depth + 1)
          end
        when NODE_OR_EXPR
          print([indent, 'NODE_OR_EXPR'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          for i in 2..node.length-1
            print([indent, 'op ||'].join(''), "\n")
            print_nodelist(node[i], :depth => depth + 1)
          end
        when NODE_AND_EXPR
          print([indent, 'NODE_ADD_EXPR'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          for i in 2..node.length-1
            print([indent, 'op &&'].join(''), "\n")
            print_nodelist(node[i], :depth => depth + 1)
          end
        when NODE_COMP_EXPR
          print([indent, 'NODE_COMP_EXPR'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          print([indent, 'op'].join(''), node[2], "\n")
          print_nodelist(node[3], :depth => depth + 1)
        when NODE_ADD_EXPR
          print([indent, 'NODE_ADD_EXPR'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          for i in 2.step(node.length-1, 2)
            print([indent, 'op'].join(''), node[i], "\n")
            print_nodelist(node[i + 1], :depth => depth + 1)
          end
        when NODE_MUL_EXPR
          print([indent, 'NODE_MUL_EXPR'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          for i in 2.step(node.length-1, 2)
            print([indent, 'op'].join(''), node[i], "\n")
            print_nodelist(node[i + 1], :depth => depth + 1)
          end
        when NODE_POW_EXPR
          print([indent, 'NODE_POW_EXPR'].join(''), "\n")
          print_nodelist(node[1], :depth => depth + 1)
          for i in 2..node.length-1
            print([indent, 'op ^'].join(''), "\n")
            print_nodelist(node[i], :depth => depth + 1)
          end
        when NODE_UNARY_EXPR
          print([indent, 'NODE_UNARY_EXPR'].join(''), "\n")
          print([indent, 'op'].join(''), node[1], "\n")
          print_nodelist(node[2], :depth => depth + 1)
        else
          fail RuntimeError('should not reach here')
        end
      end
    end
  end

# expression := or_expr
# or_expr    := and_expr ( op_op and_expr )*
# or_op      := "｜｜"
# and_expr   := comp_expr ( and_op comp_expr )*
# and_op     := "＆＆"
# comp_expr  := add_expr ( comp_op add_expr )?
# comp_op    := "＜" | "＞" | "＜＝" | "＞＝" | "＝＝" | "！＝"
# add_expr   := mul_expr ( add_op mul_expr )*
# add_op     := "＋" | "−"
# mul_expr   := pow_expr ( mul_op pow_expr )*
# mul_op     := "×" | "÷" | "＊" | "／" | "％"
# pow_expr   := unary_expr ( pow_op unary_expr )*
# pow_op     := "＾"
# unary_expr := unary_op unary_expr | "(" or_expr ")" | factor
# unary_op   := "−" | "！"
# factor     := ( constant | reference )*


  ###   INTERPRETER   ###

  class SATORI

    DBNAME = 'satori_savedata.txt'
    EDBNAME = 'satori_savedata.sat'

    def initialize(satori_dir: nil)
      satori_init(:satori_dir => satori_dir)
    end

    def satori_init(satori_dir: nil)
      @satori_dir = satori_dir
      @dbpath = File.join(satori_dir, DBNAME)
      @saori_function = {}
      @parser = Parser.new()
      reset()
    end

    def reset
      @word = {}
      @talk = {}
      @variable = {}
      @replace_filter = Filter.new([])
      @reset_surface = true
      @mouse_move_count = {}
      @mouse_wheel_count = {}
      @touch_threshold = 60
      @touch_timeout = 2
      @current_surface = [0, 10]
      @default_surface = [0, 10]
      @add_to_surface = [0, 0]
      @newline = "\\n[half]"
      @newline_script = ''
      @save_interval = 0
      @save_timer = 0
      @url_list = {}
      @boot_script = nil
      @script_history = ([nil] * 64)
      @wait_percent = 100
      @random_talk = -1
      @reserved_talk = {}
      @silent_time = 0
      @choice_id = nil
      @choice_label = nil
      @choice_number = nil
      @timer = {}
      @time_start = nil
      @runtime = 0 # accumulative
      @runcount = 1 # accumulative
      @folder_change = false
      @saori_value = {}
    end

    def load
      buf = []
      for path in Satori.list_dict(@satori_dir)
        filename = File.basename(path)
        case filename
        when 'replace.txt'
          @parser.load_replace_file(path)
        when 'replace_after.txt'
          load_replace_file(path)
        when 'satori_conf.txt', 'satori_conf.sat'
          load_config_file(path)
        else
          buf << path
        end
      end
      for path in buf
        @parser.read(path)
      end
      @talk, @word = @parser.get_dict()
      load_database()
      @time_start = Time.new
      get_event_response('OnSatoriLoad')
      @boot_script = get_event_response('OnSatoriBoot')
    end

    def load_config_file(path)
      parser = Parser.new()
      parser.read(path)
      talk, word = parser.get_dict()
      for nodelist in (talk.include?('初期化') ? talk['初期化'] : [])
        expand(nodelist)
      end
    end

    def load_replace_file(path)
      @replace_filter = Filter.new(Satori.read_tab_file(path))
    end

    def load_database
      if @variable['セーブデータ暗号化'] == '有効'
        encrypted = true
        @dbpath = File.join(@satori_dir, EDBNAME)
      else
        encrypted = false
        @dbpath = File.join(@satori_dir, DBNAME)
      end
      begin
        database = Satori.read_tab_file(@dbpath, :encrypted => encrypted)
      rescue #except IOError:
        database = []
      end
      for name, value in database
        if name.start_with?('b\'') or name.start_with?('b"')
          next # XXX: 文字コード変換に問題のあったバージョン対策
        end
        assign(name, value)
      end
    end

    def save_database
      if @variable['セーブデータ暗号化'] == '有効'
        encrypted = true
        @dbpath = File.join(@satori_dir, EDBNAME)
      else
        encrypted = false
        @dbpath = File.join(@satori_dir, DBNAME)
      end
      begin
        open(@dbpath, 'wb') do |f|
          for name in @variable.keys
            value = @variable[name]
            if ['前回終了時サーフェス0',
                '前回終了時サーフェス1',
                'デフォルトサーフェス0',
                'デフォルトサーフェス1'].include?(name)
              next
            end
            line = (name.to_s + "\t" + value.to_s)
            line = line.encode('CP932', :invalid => :replace, :undef => :replace)
            if encrypted
              line = Satori.encrypt(Satori.encrypt(line)).join('')
            end
            f.write(line)
            f.write("\r\n")
          end
          for side in [0, 1]
            name = ('デフォルトサーフェス' + side.to_s)
            value = to_zenkaku(@default_surface[side].to_s)
            line = (name.to_s + "\t" + value.to_s)
            line = line.encode('CP932', :invalid => :replace, :undef => :replace)
            if encrypted
              line = Satori.encrypt(Satori.encrypt(line)).join('')
            end
            f.write(line)
            f.write("\r\n")
          end
          for side in [0, 1]
            name = ('前回終了時サーフェス' + side.to_s)
            value = to_zenkaku(@current_surface[side].to_s)
            line = (name.to_s + "\t" + value.to_s)
            line = line.encode('CP932', :invalid => :replace, :undef => :replace)
            if encrypted
              line = Satori.encrypt(Satori.encrypt(line)).join('')
            end
            f.write(line)
            f.write("\r\n")
          end
          name = '起動回数'
          value = to_zenkaku(@runcount.to_s)
          line = (name.to_s + "\t" + value.to_s)
          line = line.encode('CP932', :invalid => :replace, :undef => :replace)
          if encrypted
            line = Satori.encrypt(Satori.encrypt(line)).join('')
          end
          f.write(line)
          f.write("\r\n")
          for name in @timer.keys
            value = to_zenkaku(@timer[name])
            line = (name.to_s + "\t" + value.to_s)
            line = line.encode('CP932', :invalid => :replace, :undef => :replace)
            if encrypted
              line = Satori.encrypt(Satori.encrypt(line)).join('')
            end
            f.write(line)
            f.write("\r\n")
          end
          for name in @reserved_talk.keys
            value = to_zenkaku(@reserved_talk[name])
            line = (['次から', value, '回目のトーク'].join('') + "\t" + name.to_s)
            line = line.encode('CP932', :invalid => :replace, :undef => :replace)
            if encrypted
              line = Satori.encrypt(Satori.encrypt(line)).join('')
            end
            f.write(line)
            f.write("\r\n")
          end
        end
      rescue #except IOError:
        Logging::Logging.debug('satori.py: cannot write ' + @dbpath.to_s)
        return
      end
    end

    def finalize
      get_event_response('OnSatoriUnload')
      accumulative_runtime = (@runtime + get_runtime())
      assign('単純累計秒', to_zenkaku(accumulative_runtime))
      save_database()
    end

    # SHIORI/1.0 API
    def getaistringrandom
      get_script('')
    end

    def getaistringfromtargetword(word)
      ''
    end

    def getdms
      ''
    end

    def getword(word_type)
      ''
    end

    # SHIORI/2.2 API
    EVENT_MAP = {
      'OnFirstBoot' =>         '初回',
      'OnBoot' =>              '起動',
      'OnClose' =>             '終了',
      'OnGhostChanging' =>     '他のゴーストへ変更',
      'OnGhostChanged' =>      '他のゴーストから変更',
      'OnVanishSelecting' =>   '消滅指示',
      'OnVanishCancel' =>      '消滅撤回',
      'OnVanishSelected' =>    '消滅決定',
      'OnVanishButtonHold' =>  '消滅中断',
    }

    def get_event_response(event,
                           ref0: nil, ref1: nil, ref2: nil, ref3: nil,
                           ref4: nil, ref5: nil, ref6: nil, ref7: nil)
      @event = event
      @reference = [ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7]
      tail = '\e'
      case event
      when 'OnUpdateReady'
        begin
          ref0 = (Integer(ref0) + 1).to_s
          @reference[0] = ref0
        rescue
          #pass
        end
      when 'OnMouseMove'
        key = [ref3, ref4] # side, part
        count, timestamp = (@mouse_move_count.include?(key) ? @mouse_move_count[key] : [0, 0])
        if (Time.now - timestamp).to_i > @touch_timeout
          count = 0
        end
        count += 1
        if count >= @touch_threshold
          event = (ref3.to_s + ref4.to_s + 'なでられ')
          count = 0
        end
        @mouse_move_count[key] = [count, Time.now]
      when 'OnMouseWheel'
        key = [ref3, ref4] # side, part
        count, timestamp = (@mouse_wheel_count.include?(key) ? @mouse_wheel_count[key] : [0, 0])
        if (Time.now - timestamp).to_i > 2
          count = 0
        end
        count += 1
        if count >= 2
          event = (ref3.to_s + ref4.to_s + 'ころころ')
          count = 0
        end
        @mouse_wheel_count[key] = [count, Time.now]
      when 'OnSecondChange'
        @silent_time += 1
        if @save_interval > 0
          @save_timer -= 1
          if @save_timer <= 0
            save_database()
            @save_timer = @save_interval
          end
        end
        if ref3 != '0' # cantalk
          # check random talk timer
          if @random_talk.zero?
            reset_random_talk_interval()
          elsif @random_talk > 0
            @random_talk -= 1
            if @random_talk.zero?
              event = get_reserved_talk()
              unless event.nil?
                @reference[0] = to_zenkaku(1)
              else
                @reference[0] = to_zenkaku(0)
              end
              @reference[1] = event
              script = get_script('OnTalk')
              unless script.nil?
                @script_history.shift
                @script_history. << script
                return script
              end
              @reference[0] = ref0
              @reference[1] = ref1
            end
          end
        end
        # check user-defined timers
        for name in @timer.keys()
          count = @timer[name] - 1
          if count > 0
            @timer[name] = count
          elsif ref3 != '0' # cantalk
            @timer.delete(name)
            event = name[0..-7]
            break
          end
        end
      when 'OnSurfaceChange'
        @current_surface[0] = ref0
        @current_surface[1] = ref1
      when 'OnChoiceSelect'
        @choice_id = ref0
        @choice_label = ref1
        @choice_number = ref2
        unless @talk.include?('OnChoiceSelect')
          event = ref0
        end
      when 'OnChoiceEnter'
        @choice_id = ref1
        @choice_label = ref0
        @choice_number = ref2
      when 'OnAnchorSelect'
        if @talk.include?(ref0)
          event = ref0
        end
      when 'sakura.recommendsites', 'sakura.portalsites', 'kero.recommendsites'
        return get_url_list(event)
      when 'OnRecommandedSiteChoice'
        script = get_url_script(ref0, ref1)
        unless script.nil?
          @script_history.shift
          @script_history << script
        end
        return script
      when *EVENT_MAP
        if ['OnBoot', 'OnGhostChanged'].include?(event)
          unless @boot_script.nil?
            script = @boot_script
            @boot_script = nil
            @script_history.shift
            @script_history << script
            return script
          end
        end
        if ['OnClose', 'OnGhostChanging'].include?(event)
          if event == 'OnClose'
            tail = '\-\e'
          end
          script = get_script('OnSatoriClose', :tail => tail)
          unless script.nil?
            @script_history.shift
            @script_history << script
            return script
          end
        end
        unless @talk.include?(event)
          event = EVENT_MAP[event]
        end
      end
      script = get_script(event, :tail => tail)
      unless script.nil?
        @script_history.shift
        @script_history << script
      end
      return script
    end

    # SHIORI/2.4 API
    def teach(word)
      name = @variable['教わること']
      unless name.nil?
        @variable[name] = word
        script = get_script([name, 'を教えてもらった'].join(''))
        @script_history.shift
        @script_history << script
        return script
      end
      return nil
    end

    # SHIORI/2.5 API
    def getstring(name)
      word = @word[name]
      return expand(word.sample) unless word.nil?
      return nil
    end

    # internal
    def get_reserved_talk
      reserved = nil
      for key in @reserved_talk.keys
        @reserved_talk[key] -= 1
        if @reserved_talk[key] <= 0
          reserved = key
        end
      end
      unless reserved.nil?
        @reserved_talk.delete(reserved)
      else
        reserved = ''
      end
      return reserved
    end

    Re_reservation = Regexp.new('\A次から(([[:digit:]])+)(〜(([[:digit:]])+))?回目のトーク')

    def assign(name, value)
      if name.end_with?('タイマ')
        if @talk.include?(name[0..-4])
          add_timer(name, value)
        end
      elsif name == '全タイマ解除'
        if value == '実行'
          delete_all_timers()
        end
      elsif name == '辞書リロード'
        if value == '実行'
          reload()
        end
      elsif name == '手動セーブ'
        if value == '実行'
          save_database()
        end
      elsif not Re_reservation.match(name).nil?
        return nil if value.nil? or value.empty?
        match = Re_reservation.match(name)
        number = to_integer(match[1])
        number = Array(number..to_integer(match[4])).sample unless match[4].nil?
        while true
          break_flag = false
          for key in @reserved_talk.keys
            if self.reserved_talk[key] == number
              number += 1
              break_flag = true
              break
            end
          end
          break unless break_flag
        end
        @reserved_talk[value] = number
      elsif name == '次のトーク'
        return nil if value.nil? or value.empty?
        number = 1
        while true
          break_flag = false
          for key in @reserved_talk.keys
            if self.reserved_talk[key] == number
              number += 1
              break_flag = true
              break
            end
          end
          break unless break_flag
        end
        @reserved_talk[value] = number
      elsif name == 'トーク予約のキャンセル'
        if value == '＊'
          @reserved_talk = {}
        elsif @reserved_talk.include?(value)
          @reserved_talk.delete(value)
        end
      elsif name == '起動回数'
        @runcount = (to_integer(value) + 1)
      elsif value.nil? or value.empty?
        if @variable.include?(name)
          @variable.delete(name)
        end
      else
        @variable[name] = value
        if ['喋り間隔', '喋り間隔誤差'].include?(name)
          reset_random_talk_interval()
        elsif name == '教わること'
          return '\![open,teachbox]'
        elsif name == '会話時サーフェス戻し'
          if value == '有効'
            @reset_surface = true
          elsif value == '無効'
            @reset_surface = false
          end
        elsif name == 'デフォルトサーフェス0'
          value = to_integer(value)
          @default_surface[0] = value unless value.nil?
        elsif name == 'デフォルトサーフェス1'
          value = to_integer(value)
          @default_surface[1] = value unless value.nil?
        elsif name == 'サーフェス加算値0'
          value = to_integer(value)
          unless value.nil?
            @default_surface[0] = value
            @add_to_surface[0] = value
          end
        elsif name == 'サーフェス加算値1'
          value = to_integer(value)
          unless value.nil?
            @default_surface[1] = value
            @add_to_surface[1] = value
          end
        elsif name == '単純累計秒'
          @runtime = to_integer(value)
        elsif name == 'なでられ反応回数'
          @touch_threshold = to_integer(value)
        elsif name == 'なでられ持続秒数'
          @touch_timeout = to_integer(value)
        elsif name == 'スコープ切り換え時'
          @newline = value
        elsif name == 'さくらスクリプトによるスコープ切り換え時'
          @newline_script = value
        elsif name == '自動挿入ウェイトの倍率'
          if value.end_with?('%')
            value = value[0..-2]
          elsif value.end_with?('％')
            value = value[0..-2]
          end
          value = to_integer(value)
          if not value.nil? and value >= 0 and value <= 1000
            @wait_percent = value
          end
        elsif name == '自動セーブ間隔'
          @save_interval = to_integer(value)
          @save_timer = @save_interval
        elsif name == '辞書フォルダ'
          @folder_change = true
        end
      end
      return nil
    end

    def change_folder
      value = @variable['辞書フォルダ']
      dir_list = value.split(',', -1)
      @parser = Parser.new()
      @parser.set_saori(@saori_function.keys())
      for path in Satori.list_dict(@satori_dir)
        filename = File.basename(path)
        if filename == 'replace.txt'
          @parser.load_replace_file(path)
        elsif filename == 'replace_after.txt'
          load_replace_file(path)
        end
      end
      buf = []
      for dir_ in dir_list
        dir_ = Home.get_normalized_path(dir_)
        dict_dir = File.join(@satori_dir, dir_)
        unless File.directory?(dict_dir)
          Logging::Logging.debug('satori.py: cannot read ' + dict_dir.to_s)
          next
        end
        for path in Satori.list_dict(dict_dir)
          filename = File.basename(path)
          if filename == 'replace.txt' ## XXX
            @parser.load_replace_file(path)
          elsif filename == 'replace_after.txt' ## XXX
            load_replace_file(path)
          elsif ['satori_conf.txt', 'satori_conf.sat'].include?(filename)
            #pass
          else
            buf << path
          end
        end
      end
      for path in buf
        @parser.read(path)
      end
      @talk, @word = @parser.get_dict()
    end

    def reload
      finalize()
      reset()
      load()
    end

    def reset_random_talk_interval
      interval = get_integer('喋り間隔', :error => 'ignore')
      if interval.nil? or interval.zero?
        @random_talk = -1
        return
      end
      rate = get_integer('喋り間隔誤差', :error => 'ignore')
      if rate.nil?
        rate = 0.1
      else
        rate = ([[rate, 1].max, 100].min / 100.0)
      end
      diff = (interval * rate).to_i
      @random_talk = Array(interval - diff..interval + diff).sample
    end

    def add_timer(name, value)
      count = to_integer(value)
      if count.nil? or count.zero?
        if @timer.include?(name)
          @timer.delete(name)
        end
      else
        @timer[name] = count
      end
    end

    def delete_all_timers
      @timer = {}
    end

    def get_script(name, head: '\1', tail: '\e')
      if @reset_surface
        @current_reset_surface = [true, true]
      else
        @current_reset_surface = [false, false]
      end
      script = get(name, :default => nil)
      if not script.nil? and not script.empty? and script != "\\n"
        ##Logging::Logging.debug('make("' + script.encode('utf-8', :invalid => :replace, :undef => :replace) + '")')
        return make([head, script, tail].join(''))
      end
      return nil
    end

    def get_url_list(name)
      @url_list[name] = []
      list_ = @talk[name]
      return nil if list_.nil?
      url_list = ''
      for i in (list_.length-1).step(-1, -1)
        nodelist = list_[i]
        title = ''
        j = 0
        while j < nodelist.length
          node = nodelist[j]
          j += 1
          if node[0] == NODE_TEXT
            if node[1] == ["\\n"]
              break
            else
              title = [title, node[1].join('')].join('')
            end
          else
            #pass
          end
        end
        next if title.empty?
        if title == '-'
          unless url_list.empty?
            url_list = [url_list, 2.chr].join('')
          end
          url_list = [url_list, title, 1.chr].join('')
          next
        end
        url = ''
        while j < nodelist.length
          node = nodelist[j]
          j += 1
          if node[0] == NODE_TEXT
            if node[1] == ["\\n"]
              break
            else
              url = [url, node[1].join('')].join('')
            end
          else
            #pass
          end
        end
        next if url.empty?
        bannar = ''
        while j < nodelist.length
          node = nodelist[j]
          j += 1
          if node[0] == NODE_TEXT
            if node[1] == ["\\n"]
              break
            else
              bannar = [bannar, node[1].join('')].join('')
            end
          else
            #pass
          end
        end
        if nodelist[j..-1]
          script = nodelist[j..-1]
        else
          script = nil
        end
        @url_list[name] << [title, url, bannar, script]
        unless url_list.empty?
          url_list = [url_list, 2.chr].join('')
        end
        url_list = [url_list, title, 1.chr, url, 1.chr, bannar].join('')
      end
      if url_list.empty?
        url_list = nil
      end
      return url_list
    end

    def get_url_script(title, url)
      script = nil
      if @reset_surface
        @current_reset_surface = [true, true]
      else
        @current_reset_surface = [false, false]
      end
      for key in @url_list.keys
        for item in @url_list[key]
          if item[0] == title and item[1] == url
            unless item[3].nil?
              script = expand(item[3])
              if not script.nil? and not script.empty? and script != "\\n"
                script = make(['\1', script, '\e'].join(''))
                break
              end
            end
          end
        end
      end
      return script
    end

    Redundant_tags = [
        [Regexp.new('(\\\\[01hu])+(\\\\[01hu])'),   2], #lambda {|m| m[2] }],
        [Regexp.new('(\\n)+(\\e|$)'),           2], #lambda {|m| m[2] }],
        [Regexp.new('(\\e)+'),                  1], #lambda {|m| m[1] }],
        ]
    Re_newline = Regexp.new('((\\n)*)(\\e)')
    Re_0 = Regexp.new('\\\\[0h]')
    Re_1 = Regexp.new('\\\\[1u]')
    Re_wait_after = Regexp.new('\A、|。|，|．')
    Re_wait_before = Regexp.new('\A\\\\[01hunce]')
    Re_tag = Regexp.new('\A\\\\[ehunjcxtqzy*v0123456789fmia!&+\-\-\-]|' \
                        '\\\\[sb][0-9]?|\\w[0-9]|\\_[wqslvVbe+cumna]|' \
                        '\\__[ct]|\\URL')

    def make(script)
      return nil if script.nil?
      # make anchor
      buf = []
      i = 0
      while true
        match = Re_tag.match(script, i)
        if not match.nil? and match.begin(0) == i
          start = match.begin(0)
          end_ = match.end(0)
          if start > 0
            buf << @parser.anchor_filter.apply(script[i..start-1])
          end
          buf << script[start..end_-1]
          i = end_
        else
          buf << @parser.anchor_filter.apply(script[i..-1])
          break
        end
      end
      script = buf.join('')
      # apply replace_after.txt
      script = @replace_filter.apply(script)
      # remove redundant tags
      for pattern, replace in Redundant_tags
        #script, count = pattern.subn(replace, script)
        match = pattern.match(script)
        script = script.sub(pattern, match[replace]) unless match.nil?
      end
      # remove redundant newline tags
      match = Re_newline.match(script)
      unless match.nil?
        tag = match[3]
        if tag == '\e'
          if match.begin(0).zero?
            script = script[match.end(0)..-1]
          else
            script = [script[0..match.begin(0)-1],
                      tag, script[match.end(0)..-1]].join('')
          end
        else
          fail RuntimeError('should not reach here')
        end
      end
      # insert newline
      i = 1
      while true
        match = Re_0.match(script, i)
        unless match.nil?
          end_ = match.end(0)
          match = Re_0.match(script, end_)
          unless match.nil?
            start = match.begin(0)
            if start < @newline.length or \
              script[start - @newline.length..start-1] != @newline
              script = (script[0..match.end(0)-1] + @newline_script + script[match.end(0)..-1])
            end
          else
            break
          end
          i = end_
        else
          break
        end
      end
      i = 1
      while true
        match = Re_1.match(script, i)
        unless match.nil?
          end_ = match.end(0)
          match = Re_1.match(script, end_)
          unless match.nil?
            start = match.begin(0)
            if start < @newline.length or \
              script[start - @newline.length..start-1] != @newline
              script = (script[0..match.end(0)-1] + @newline_script + script[match.end(0)..-1])
            end
          else
            break
          end
          i = end_
        else
          break
        end
      end
      # insert waits
      buf = []
      n = 0
      i, j = 0, script.length
      while i < j
        match = Re_wait_after.match(script, i)
        if not match.nil? and match.begin(0).zero? # FIXME
          buf << match[0]
          buf.concat(make_wait(n))
          n = 0
          i = match.end(0)
          next
        end
        match = Re_wait_before.match(script, i)
        if not match.nil? and match.begin(0).zero? # FIXME
          buf.concat(make_wait(n))
          buf << match[0]
          n = 0
          i = match.end(0)
          next
        end
        if script[i] == '['
          pos = script.index(']', i)
          if pos > i
            buf << script[i..pos]
            i = (pos + 1)
            next
          end
        end
        match = Re_tag.match(script, i)
        if not match.nil? and match.begin(0).zero? # FIXME
          buf << script[i..match.end(0)-1]
          i = match.end(0)
        else
          buf << script[i]
          n += 3
          i += 1
        end
      end
      return buf.join('')
    end

    def make_wait(ms)
      buf = []
      n = ((ms + 25) * @wait_percent / 100 / 50).to_i
      while n > 0
        buf << '\w' + [n, 9].min.to_s
        n -= 9
      end
      return buf
    end

    def get(name, default: '')
      result = @talk[name]
      return default if result.nil?
      return expand(result.sample)
    end

    def expand(nodelist, caller_history: nil, side: 1)
      return '' if nodelist.nil?
      buf = []
      history = []
      talk = false
      newline = [nil, nil]
      for node in nodelist
        case node[0]
        when NODE_REF
          unless caller_history.nil?
            value = get_reference(node[1], caller_history, side)
          else
            value = get_reference(node[1], history, side)
          end
          unless value.nil? or value.empty?
            talk = true
            buf << value
            history << value
            unless caller_history.nil?
              caller_history << value
            end
          end
        when NODE_CALL
          function = node[1]
          args = node[2]
          value = call_function(
            function, args,
            (not caller_history.nil?) ? caller_history : history,
            side)
          unless value.nil? or value.empty?
            talk = true
            buf << value
            history << value
            unless caller_history.nil?
              caller_history << value
            end
          end
        when NODE_SAORI
          if @variable['SAORI引数の計算'] == '無効'
            expand_only = true
          else
            expand_only = false
          end
          unless caller_history.nil?
            value = call_saori(
              node[1],
              calc_args(node[2], caller_history, :expand_only => expand_only),
              caller_history, side)
          else
            value = call_saori(
              node[1],
              calc_args(node[2], history, :expand_only => expand_only),
              history, side)
          end
          unless value.nil? or value.empty?
            talk = true
            buf << value
            history << value
            unless caller_history.nil?
              caller_history << value
            end
          end
        when NODE_TEXT
          buf.concat([node[1]])
          talk = true
        when NODE_SIDE
          if talk
            newline[side] = @newline
          else
            newline[side] = nil
          end
          talk = false
          if side.zero?
            side = 1
          else
            side = 0
          end
          buf << "\\" + side.to_s
          if @current_reset_surface[side]
            buf << '\s[' + @default_surface[side].to_s + ']'
            @current_reset_surface[side] = false
          end
          unless newline[side].nil?
            buf << newline[side].to_s
          end
        when NODE_ASSIGNMENT
          value = expand(node[2])
          result = assign(expand(node[1]), value)
          unless result.nil?
            buf << result
          end
        when NODE_JUMP
          if node[2].nil? or \
            not ['０', '0'].include?(expand(node[2]))
            target = expand(node[1])
            if target == 'OnTalk'
              @reference[1] = get_reserved_talk()
              if @reference[1]
                @reference[0] = to_zenkaku(1)
              else
                @reference[0] = to_zenkaku(0)
              end
            end
            script = get(target, :default => nil)
            if not script.nil? and not script.empty? and script != "\\n"
              buf << ['\1', script].join('')
              break
            end
          end
        when NODE_SEARCH ## FIXME
          buf << ''
        when NODE_CHOICE
          label = expand(node[1])
          if node[2].nil?
            id_ = label
          else
            id_ = expand(node[2])
          end
          buf << '\q[' + label + ',' + id_ + ']\n'
          talk = true
        when NODE_OR_EXPR
          break_flag = false
          for i in 1..node.length-1
            unless ['０', '0'].include?(expand(node[i]))
              buf << '１'
              break_flag = true
              break
            end
          end
          unless break_flag
            buf << '０'
          end
        when NODE_AND_EXPR
          break_flag = false
          for i in 1..node.length-1
            if ['０', '0'].include?(expand(node[i]))
              buf << '０'
              break_flag = true
              break
            end
          end
          unless break_flag
            buf << '１'
          end
        when NODE_COMP_EXPR
          operand1 = expand(node[1])
          operand2 = expand(node[3])
          n1 = to_integer(operand1)
          n2 = to_integer(operand2)
          if not (n1.nil? or n2.nil?)
            operand1 = n1
            operand2 = n2
          elsif n1.nil? and n2.nil? and \
               ['<', '>', '<=', '>='].include?(node[2])
            operand1 = operand1.length
            operand2 = operand2.length
          end
          case node[2]
          when '=='
            buf << to_zenkaku(operand1 == operand2 ? 1 : 0)
          when '!='
            buf << to_zenkaku(operand1 != operand2 ? 1 : 0)
          when '<'
            buf << to_zenkaku(operand1 < operand2 ? 1 : 0)
          when '>'
            buf << to_zenkaku(operand1 > operand2 ? 1 : 0)
          when '<='
            buf << to_zenkaku(operand1 <= operand2 ? 1 : 0)
          when '>='
            buf << to_zenkaku(operand1 >= operand2 ? 1 : 0)
          else
            fail RuntimeError('should not reach here')
          end
        when NODE_ADD_EXPR
          value_str = expand(node[1])
          value = to_integer(value_str)
          for i in 2.step(node.length-1, 2)
            operand_str = expand(node[i + 1])
            operand = to_integer(operand_str)
            if node[i] == '-'
              if value.nil? or operand.nil?
                value_str = value_str.gsub(operand_str, '')
                value = nil
              else
                value -= operand
                value_str = to_zenkaku(value)
              end
              next
            end
            value = 0 if value.nil?
            operand = 0 if operand.nil?
            if node[i] == '+'
              value += operand
            else
              fail RuntimeError('should not reach here')
            end
          end
          if value.nil?
            buf << value_str
          else
            buf << to_zenkaku(value)
          end
        when NODE_MUL_EXPR
          value_str = expand(node[1])
          value = to_integer(value_str)
          for i in 2.step(node.length-1, 2)
            operand_str = expand(node[i + 1])
            operand = to_integer(operand_str)
            if node[i] == '*'
              if value.nil? and operand.nil?
                value_str = ''
                value = nil
              elsif value.nil?
                value_str *= operand
                value = nil
              elsif operand.nil?
                value_str *= operand_str
                value = nil
              else
                value *= operand
              end
              next
            end
            value = 0 if value.nil?
            operand = 0 if operand.nil?
            if node[i] == '/'
              value = (value / operand).to_i
            elsif node[i] == '%'
              value = (value % operand)
            else
              fail RuntimeError('should not reach here')
            end
          end
          if value.nil?
            buf << value_str
          else
            buf << to_zenkaku(value)
          end
        when NODE_POW_EXPR
          value = to_integer(expand(node[1]))
          value = 0 if value.nil?
          for i in 2..node.length-1
            operand = to_integer(expand(node[i]))
            operand = 0 if operand.nil?
            value **= operand
          end
          buf << to_zenkaku(value)
        when NODE_UNARY_EXPR
          value = expand(node[2])
          if node[1] == '-'
            value = to_integer(value)
            value = 0 if value.nil?
            value = -value
          elsif node[1] == '!'
            value = (['０', '0'].include?(value) ? 1 : 0)
          else
            fail RuntimeError('should not reach here')
          end
          buf << to_zenkaku(value)
        else
          fail RuntimeError('should not reach here')
        end
      end
      return buf.join('').strip()
    end

    Re_random = Regexp.new('\A乱数((－|−|＋|[-+])?([[:digit:]])+)～((－|−|＋|[-+])?([[:digit:]])+)')
    Re_is_empty = Regexp.new('\A(変数|文|単語群)「(.*)」の存在')
    Re_n_reserved = Regexp.new('\A次から(([[:digit:]])+)回目のトーク')
    Re_is_reserved = Regexp.new('\Aトーク「(.*)」の予約有無')

    def get_reference(nodelist, history, side)
      key = expand(nodelist[1..-2], :caller_history => history)
      if not key.nil? and ['Ｒ', 'R'].include?(key[0])
        n = to_integer(key[1..-1])
        if not n.nil? and 0 <= n and n < @reference.length ## FIXME
          return '' if @reference[n].nil?
          return @reference[n].to_s
        end
      elsif key and ['Ｓ', 'S'].include?(key[0])
        n = to_integer(key[1..-1])
        unless n.nil?
          if @saori_value.include?(key)
            return '' if @saori_value[key].nil?
            return @saori_value[key].to_s
          else
            return ''
          end
        end
      elsif not key.nil? and ['Ｈ', 'H'].include?(key[0])
        ##Logging::Logging.debug(['["', history.join('", "'), '"]'].join(''))
        n = to_integer(key[1..-1])
        if not n.nil? and 1 <= n and n < history.length + 1 ## FIXME
          return history[n-1]
        end
      end
      n = to_integer(key)
      unless n.nil?
        return '\s[' + (n + @add_to_surface[side]).to_s + ']'
      end
      if @word.include?(key)
        return expand(@word[key].sample, :caller_history => history,
                      :side => side)
      elsif @talk.include?(key)
        @reference = [nil] * 8
        return expand(@talk[key].sample, :side => 1)
      elsif @variable.include?(key)
        return @variable[key]
      elsif @timer.include?(key)
        return to_zenkaku(@timer[key])
      elsif is_reserved(key)
        return get_reserved(key)
      elsif not Re_random.match(key).nil?
        match = Re_random.match(key)
        i = to_integer(match[1])
        j = to_integer(match[4])
        if i < j
          return to_zenkaku(Array(i..j).sample)
        else
          return to_zenkaku(Array(j..i).sample)
        end
      elsif not Re_n_reserved.match(key).nil?
        match = Re_n_reserved.match(key)
        number = to_integer(match[1])
        for key in @reserved_talk.keys
          if @reserved_talk[key] == number
            return key
          end
        end
        return ''
      elsif not Re_is_reserved.match(key).nil?
        match = Re_is_reserved.match(key)
        name = match[1]
        if @reserved_talk.include?(name)
          return to_zenkaku(1)
        else
          return to_zenkaku(0)
        end
      elsif not Re_is_empty.match(key).nil?
        match = Re_is_empty.match(key)
        type_ = match[1]
        name = match[2]
        case type_
        when '変数'
          if @variable.include?(name)
            return to_zenkaku(1)
          else
            return to_zenkaku(0)
          end
        when '文'
          if @talk.include?(name)
            return to_zenkaku(1)
          else
            return to_zenkaku(0)
          end
        when '単語群'
          if @word.include?(name)
            return to_zenkaku(1)
          else
            return to_zenkaku(0)
          end
        end
      end
      return '（' + key.to_s + '）'
    end

    def calc_args(args, history, expand_only: false)
      buf = []
      for i in 0..args.length-1
        value = expand(args[i], :caller_history => history)
        line = value ## FIXME
        if expand_only or line.empty?
          buf << value
        elsif ['－', '-', '−',  '+', '＋'].include?(line[0]) and line.length == 1 # XXX
          buf << value
        elsif NUMBER.include?(line[0])
          begin ## FIXME
            line, expr = @parser.get_add_expr(line)
            result = to_integer(expand(expr, :caller_history => history)).to_s
            if result.nil?
              buf << value
            else
              buf << result
            end
          rescue
            buf << value
          end
        else
          buf << value
        end
      end
      return buf
    end

    def call_function(name, args, history, side)
      if name == '単語の追加'
        #pass ## FIXME
      elsif name == 'call'
        ref = expand(args[0], :caller_history => history)
        args = args[1..-1]
        for i in 0..args.length-1
          name = ['Ａ', to_zenkaku(i)].join('')
          @variable[name] = expand(args[i], :caller_history => history)
        end
        result = get_reference([[NODE_TEXT, '（'], [NODE_TEXT, ref],
                                [NODE_TEXT, '）']], history, side)
        for i in 0..args.length-1
          name = ['Ａ', to_zenkaku(i)].join('')
          @variable.delete(name)
        end
        return result
      elsif name == 'remember'
        number = to_integer(expand(args[0], :caller_history => history))
        if number > 0 and number <= 64 and @script_history[-number]
          return @script_history[-number] 
        else
          return ''
        end
      elsif name == 'loop'
        ref = expand(args[0], :caller_history => history)
        if args.length < 2
          return ''
        elsif args.length == 2
          start = 1
          end_ = to_integer(expand(args[1], :caller_history => history)) + 1
          step = 1
        elsif args.length == 3
          start = to_integer(expand(args[1], :caller_history => history))
          end_ = to_integer(expand(args[2], :caller_history => history)) + 1
          step = 1
        elsif args.length >= 4
          start = to_integer(expand(args[1], :caller_history => history))
          end_ = to_integer(expand(args[2], :caller_history => history))
          step = to_integer(expand(args[3], :caller_history => history))
          if step > 0
            end_ = (end_ + 1)
          elsif step < 0
            end_ = (end_ - 1)
          else
            return '' # infinite loop
          end
        end
        name = [ref, 'カウンタ'].join('')
        buf = []
        for i in start.step(end_-1, step)
          @variable[name] = to_zenkaku(i)
          buf << get_reference([[NODE_TEXT, '（'],
                                [NODE_TEXT, ref],
                                [NODE_TEXT, '）']],
                               history, side)
        end
        return buf.join('')
      elsif name == 'sync' ## FIXME
        #pass
      elsif name == 'set'
        if args.nil?
          name = ''
        else
          name = expand(args[0], :caller_history => history)
        end
        if args.length < 2
          value = ''
        else
          value = expand(args[1], :caller_history => history)
        end
        unless name.empty?
          if value.empty?
            if @variable.include?(name)
              @variable.delete(name)
            end
          else
            @variable[name] = value
          end
        end
        return ''
      elsif name == 'nop'
        for i in 0..args.length-1
          expand(args[i], :caller_history => history)
        end
        #pass
      elsif name == '合成単語群' ## FIXME: not tested
        words = []
        for i in 0..args.length-1 ## FIXME
          name = expand(args[i], :caller_history => history)
          word = @word[name]
          words.concat(word) unless word.nil?
        end
        unless words.empty?
          return expand(words.sample)
        end
      elsif name.end_with?('の数')
        if ['R', 'Ｒ'].include?(name[0])
          return @reference.length
        elsif ['A', 'Ａ'].include?(name[0]) # len(args)
          #pass ## FIXME
        elsif ['S', 'Ｓ'].include?(name[0])
          ##return @saori_value.length
          #pass ## FIXME
        #elif ['H', 'Ｈ'].include?(name[0])
          #return history.length
        #elif ['C', 'Ｃ'].include?(name[0])
          #return count.length
        else ## FIXME
          #pass
        end
      elsif name == 'when'
        fail "assert" unless args.length > 1
        condition = expand(args[0], :caller_history => history)
        if ['０', '0'].include?(condition)
          if args.length > 2
            return expand(args[2], :caller_history => history)
          else
            return ''
          end
        else
          return expand(args[1], :caller_history => history)
        end
      elsif name == 'times' ## FIXME
        print('TIMES: ', args.length, " ", args)
        #pass
      elsif name == 'while' ## FIXME
        print('WHILE :', args.length, " ", args)
        #pass
      elsif name == 'for' ## FIXME
        print('FOR :', args.length, " ", args)
        #pass
      else
        fail RuntimeError('should not reach here')
      end
      return ''
    end

    def call_saori(name, args, history, side)
      return ''
    end

    def get_runtime
      return (Time.new - @time_start).to_i
    end

    def get_integer(name, error: 'strict')
      value = @variable[name]
      return nil if value.nil?
      return to_integer(value, :error => error)
    end

    NUMBER = {
      '０' => '0', '0' => '0',
      '１' => '1', '1' => '1',
      '２' => '2', '2' => '2',
      '３' => '3', '3' => '3',
      '４' => '4', '4' => '4',
      '５' => '5', '5' => '5',
      '６' => '6', '6' => '6',
      '７' => '7', '7' => '7',
      '８' => '8', '8' => '8',
      '９' => '9', '9' => '9',
      '＋' => '+', '+' => '+',
      '−' => '-', '-' => '-', '－' => '-',
    }

    def to_integer(line, error: 'strict')
      buf = []
      for char in line.chars
        if NUMBER.include?(char)
          buf << NUMBER[char]
        else
          if ['．', '.'].include?(char) # XXX
            buf << '.'
          elsif error == 'strict'
            return nil
          end
        end
      end
      begin
        return Integer(buf.join(''))
      rescue #except ValueError:
        if buf.include?('.') # XXX
          return Integer(Float(buf.join('')))
        end
        return nil
      end
    end

    def is_number(line)
      return (not to_integer(line).nil?)
    end

    ZENKAKU = {
      '0' => '０', '1' => '１', '2' => '２', '3' => '３', '4' => '４',
      '5' => '５', '6' => '６', '7' => '７', '8' => '８', '9' => '９',
      '+' => '＋', '-' => '−',
    }

    def to_zenkaku(s)
      buf = s.to_s.chars
      for i in 0..buf.length-1
        if ZENKAKU.include?(buf[i])
          buf[i] = ZENKAKU[buf[i]]
        end
      end
      return buf.join('')
    end

    RESERVED = [
      '現在年', '現在月', '現在日', '現在曜日',
      '現在時', '現在分', '現在秒',
      '起動時', '起動分', '起動秒',
      '累計時', '累計分', '累計秒',
      'ＯＳ起動時', 'ＯＳ起動分', 'ＯＳ起動秒',
      '単純起動分', '単純起動秒',
      '単純累計分', '単純累計秒',
      '単純ＯＳ起動分', '単純ＯＳ起動秒',
      '最終トークからの経過秒',
      'サーフェス0', 'サーフェス1',
      '選択ＩＤ', '選択ラベル', '選択番号',
      '予約トーク数',
      '起動回数',
      'Sender', 'Event', 'Charset',
      'Reference0', 'Reference1', 'Reference2', 'Reference3',
      'Reference4', 'Reference5', 'Reference6', 'Reference7',
      'countTalk', 'countNoNameTalk', 'countEventTalk', 'countOtherTalk',
      'countWords', 'countWord', 'countVariable', 'countAnchor',
      'countParenthesis', 'countParentheres', 'countLine',
    ]

    def is_reserved(s)
      return RESERVED.include?(s)
    end

    DAYOFWEEK = ['月', '火', '水', '木', '金', '土', '日']

    def get_reserved(s)
      now = Time.now
      case s
      when '現在年'
        return to_zenkaku(now.year)
      when '現在月'
        return to_zenkaku(now.month)
      when '現在日'
        return to_zenkaku(now.day)
      when '現在時'
        return to_zenkaku(now.hour)
      when '現在分'
        return to_zenkaku(now.min)
      when '現在秒'
        return to_zenkaku(now.sec)
      when '現在曜日'
        return DAYOFWEEK[now.wday]
      end
      runtime = get_runtime()
      case s
      when '起動時'
        return to_zenkaku((runtime / 3600).to_i)
      when '起動分'
        return to_zenkaku((runtime / 60).to_i % 60)
      when '起動秒'
        return to_zenkaku(runtime % 60)
      when '単純起動分'
        return to_zenkaku((runtime / 60).to_i)
      when '単純起動秒'
        return to_zenkaku(runtime)
      end
      accumulative_runtime = @runtime + get_runtime()
      case s
      when '累計時'
        return to_zenkaku((accumulative_runtime / 3600).to_i)
      when '累計分'
        return to_zenkaku((accumulative_runtime / 60).to_i % 60)
      when '累計秒'
        return to_zenkaku(accumulative_runtime % 60)
      when '単純累計分'
        return to_zenkaku((accumulative_runtime / 60).to_i)
      when '単純累計秒'
        return to_zenkaku(accumulative_runtime)
      when '起動回数'
        return to_zenkaku(@runcount)
      when '最終トークからの経過秒'
        return to_zenkaku(@silent_time)
      when 'サーフェス0'
        return @current_surface[0].to_i
      when 'サーフェス1'
        return @current_surface[1].to_i
      when '選択ＩＤ'
        return '' if self.choice_id.nil?
        return @choice_id
      when '選択ラベル'
        return '' if @choice_label.nil?
        return @choice_label
      when '選択番号'
        return '' if @choice_number.nil?
        return to_zenkaku(@choice_number)
      when '予約トーク数'
        return to_zenkaku(@reserved_talk.length)
      when 'Sender'
        return 'ninix'
      when 'Event'
        return @event
      when 'Charset'
        return 'UTF-8'
      when /\AReference/
        n = s[9..-1].to_i
        return '' if @reference[n].nil?
        return @reference[n].to_s
      when /\Acount/
        return to_zenkaku(@parser.get_count(s[5..-1]))
      end
      return '？'.encode('utf-8', :invalid => :replace, :undef => :replace)
    end
  end


  class Shiori < SATORI

    def initialize(dll_name)
      @dll_name = dll_name
      @saori = nil
      @saori_function = {}
    end

    def use_saori(saori)
      @saori = saori
    end

    def load(dir: nil)
      satori_init(:satori_dir => dir)
      @saori_library = SatoriSaoriLibrary.new(@saori, self)
      super()
      return 1
    end

    def load_config_file(path)
      parser = Parser.new()
      parser.read(path)
      talk, word = parser.get_dict()
      for nodelist in (talk.include?('初期化') ? talk['初期化'] : [])
        expand(nodelist)
      end
      @saori_function = {}
      for nodelist in (word.include?('SAORI') ? word['SAORI'] : [])
        if nodelist[0][0] == NODE_TEXT
          list_ = nodelist[0][1].join('').split(',', -1)
          if list_.length >= 2 and not list_[0].nil? and not list_[1].nil?
            head, tail = File.split(list_[1])
            saori_dir = File.join(@satori_dir, head)
            result = @saori_library.load(list_[1], saori_dir)
            unless result.zero?
              @saori_function[list_[0]] = list_[1..-1]
            else
              @saori_function[list_[0]] = nil
              ##Logging::Logging.error('satori.py: cannot load ' + list_[1].to_s)
            end
          end
        end
      end
      @parser.set_saori(@saori_function.keys())
    end

    def reload
      finalize()
      reset()
      load(@satori_dir)
    end

    def unload
      finalize
      @saori_library.unload()
    end

    def find(top_dir, dll_name)
      result = 0
      unless Satori.list_dict(top_dir).empty?
        result = 100
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: SATORI compatible module for ninix\n" \
        "        Copyright (C) 2002 by Tamito KAJIYAMA\n" \
        "        Copyright (C) 2002, 2003 by MATSUMURA Namihiko\n" \
        "        Copyright (C) 2002-2016 by Shyouzou Sugitani\n" \
        "        Copyright (C) 2003, 2004 by Shun-ichi TAHARA")
    end

    def request(req_string)
      if @folder_change
        change_folder()
        @folder_change = false
      end
      header = req_string.encode('UTF-8', :invalid => :replace, :undef => :replace).split(/\r?\n/, 0)
      req_header = {}
      line = header.shift
      unless line.nil?
        line = line.strip()
        req_list = line.split(nil, -1)
        if req_list.length >= 2
          command = req_list[0].strip()
          protocol = req_list[1].strip()
        end
        for line in header
          line = line.strip()
          next if line.empty?
          next unless line.include?(':')
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          begin
            value = Integer(value)
          rescue
            value = value.to_s
          end
          req_header[key] = value
        end
      end
      result = ''
      to = nil
      if req_header.include?('ID')
        if req_header['ID'] == 'dms'
          result = getdms()
        elsif req_header['ID'] == 'OnAITalk'
          result = getaistringrandom()
        elsif ["\\ms", "\\mz", "\\ml", "\\mc", "\\mh", \
               "\\mt", "\\me", "\\mp", "\\m?"].include?(req_header['ID'])
          result = getword(req_header['ID'])
        elsif req_header['ID'] == 'otherghostname' ## FIXME
          ##otherghost = []
          ##for n in 0..127
          ##  if req_header.include?(['Reference', n.to_s].join(''))
          ##    otherghost << req_header[['Reference',
          ##                              n.to_s].join('')].join(''))
          ##  end
          ##end
          ##result = self.otherghostname(otherghost)
          #pass
        elsif req_header['ID'] == 'OnTeach'
          if req_header.include?('Reference0')
            teach(req_header['Reference0'])
          end
        else
          result = getstring(req_header['ID'])
          if result.nil?
            ref = []
            for n in 0..7
              if req_header.include?(['Reference', n.to_s].join(''))
                ref << req_header[
                  ['Reference', n.to_s].join('')]
              else
                ref << nil
              end
            end
            ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7 = ref
            result = get_event_response(
              req_header['ID'],
              :ref0 => ref0, :ref1 => ref1, :ref2 => ref2, :ref3 => ref3,
              :ref4 => ref4, :ref5 => ref5, :ref6 => ref6, :ref7 => ref7)
          end
        end
        if result.nil?
          result = ''
        end
        to = nil ##communicate_to() ## FIXME
      end
      unless result.empty?
        @silent_time = 0
      end
      result = ("SHIORI/3.0 200 OK\r\n" \
                "Sender: Satori\r\n" \
                "Charset: UTF-8\r\n" \
                "Value: " + result.to_s + "\r\n")
      unless to.nil?
        result = [result, "Reference0: " + to.to_s + "\r\n"].join('')
      end
      result = [result, "\r\n"].join('')
      return result.encode('UTF-8', :invalid => :replace, :undef => :replace)
    end

    def call_saori(name, args, history, side)
      if not @saori_function.include?(name) or \
        @saori_function[name].nil?
        return ''
      end
      saori_statuscode = ''
      saori_header = []
      saori_value = {}
      saori_protocol = ''
      req = ("EXECUTE SAORI/1.0\r\n" \
             "Sender: Satori\r\n" \
             "SecurityLevel: local\r\n" \
             "Charset: Shift_JIS\r\n") ## XXX
      default_args = @saori_function[name][1..-1]
      n = default_args.length
      for i in 0..default_args.length-1
        req = [req, "Argument" + i.to_s + ": " + default_args[i].to_s + "\r\n"].join('')
      end
      for i in 0..args.length-1
        argument = args[i]
        unless argument.nil?
          req = [req,
                 "Argument#{(i + n)}: #{argument}\r\n"].join('')
        end
      end
      req = [req, "\r\n"].join('')
      response = @saori_library.request(
        @saori_function[name][0],
        req.encode('CP932', :invalid => :replace, :undef => :replace))
      header = response.split(/\r?\n/, 0)
      unless header.empty?
        line = header.shift
        line = line.force_encoding('CP932').encode("UTF-8", :invalid => :replace, :undef => :replace).strip()
        if line.include?(' ')
          saori_protocol, saori_statuscode = line.split(' ', 2)
          saori_protocol.strip!
          saori_statuscode.strip!
        end
        for line in header
          line = line.force_encoding('CP932').encode("UTF-8", :invalid => :replace, :undef => :replace).strip()
          next if line.empty?
          next unless line.include?(':')
          key, value = line.split(':', 2)
          key = key.strip()
          unless key.empty?
            saori_header << key
            saori_value[key] = value.strip()
          end
        end
      end
      for key in saori_value.keys
        next unless key.start_with?('Value')
        begin
          i = Integer(key[5..-1])
        rescue
          next
        end
        name = ['Ｓ', to_zenkaku(i)].join('')
        @saori_value[name] = saori_value[key] # overwrite
      end
      if saori_value.include?('Result')
        return saori_value['Result']
      else
        return ''
      end
    end
  end


  class SatoriSaoriLibrary

    def initialize(saori, satori)
      @saori_list = {}
      @saori = saori
      @satori = satori
    end

    def load(name, top_dir)
      result = 0
      if @saori and not @saori_list.include?(name)
        module_ = @saori.request(name)
        unless module_.nil?
          @saori_list[name] = module_
        end
      end
      if @saori_list.include?(name)
        result = @saori_list[name].load(:dir => top_dir)
      end
      return result
    end

    def unload
      for key in @saori_list.keys()
        @saori_list[key].unload()
      end
      return nil
    end

    def request(name, req)
      result = '' # FIXME
      if not name.nil? and @saori_list.include?(name)
        result = @saori_list[name].request(req)
      end
      return result
    end
  end
end
