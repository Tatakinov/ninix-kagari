# -*- coding: utf-8 -*-
#
#  ssu.rb - a ssu compatible Saori module for ninix
#  Copyright (C) 2003-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# - if, switch等の引数計算(calcを使用)

require_relative "../dll"
require_relative "../logging"


module Ssu

  class Saori < DLL::SAORI

    def initialize
      super()
      @function = {'is_empty' =>      ['ssu_is_empty',      [0, 1]],
                   'is_digit' =>      ['ssu_is_digit',      [1]],
                   'is_alpha' =>      ['ssu_is_alpha',      [1]],
                   'iflist' =>        ['ssu_iflist',        [nil]],
                   'length' =>        ['ssu_length',        [1]],
                   'zen2han' =>       ['ssu_zen2han',       [1]],
                   'han2zen' =>       ['ssu_han2zen',       [1]],
                   'kata2hira,' =>    ['ssu_kata2hira',     [1]],
                   'hira2kata' =>     ['ssu_hira2kata',     [1]],
                   'sprintf' =>       ['ssu_sprintf',       [nil]],
                   'calc' =>          ['ssu_calc',          [1]],
                   'calc_float' =>    ['ssu_calc_float',    [1]],
                   'compare_tail' =>  ['ssu_compare_tail',  [2]],
                   'compare_head' =>  ['ssu_compare_head',  [2]],
                   'compare' =>       ['ssu_compare',       [2]],
                   'count' =>         ['ssu_count',         [2]],
                   'erase_first' =>   ['ssu_erase_first',   [2]],
                   'erase' =>         ['ssu_erase',         [2]],
                   'replace' =>       ['ssu_replace',       [3]],
                   'replace_first' => ['ssu_replace_first', [3]],
                   'split' =>         ['ssu_split',         [1, 2, 3]],
                   'substr' =>        ['ssu_substr',        [2, 3]],
                   'nswitch' =>       ['ssu_nswitch',       [nil]],
                   'switch' =>        ['ssu_switch',        [nil]],
                   'if' =>            ['ssu_if',            [2, 3]],
                   'unless' =>        ['ssu_unless',        [2, 3]],}
    end

    def request(req)
      req_type, argument, charset = evaluate_request(req)
      if req_type == nil
        result = RESPONSE[400]
      elsif req_type == 'GET Version'
        result = RESPONSE[204]
      elsif req_type == 'EXECUTE'
        result = execute(argument, charset)
      else
        result = RESPONSE[400]
      end
      return result
    end

    def execute(args, charset)
      if args == nil or args.empty?
        return RESPONSE[400]
      end
      if not @function.include?(args[0])
        return RESPONSE[400]
      end
      name = args[0]
      args = args[1..-1]
      if @function[name][1] == [nil]
        #pass
      elsif not @function[name][1].include?(args.length)
        return RESPONSE[400]
      end
      @value = []
      result = method(@function[name][0]).call(args)
      if result != nil and not result.to_s.empty?
        s = ("SAORI/1.0 200 OK\r\nResult: " + result.to_s + "\r\n")
        if not @value.empty?
          for i in 0..@value.length-1
            s = [s, "Value" + i.to_s + ": " + @value[i].to_s + "\r\n"].join("")
          end
        end
        s = [s, "Charset: " + charset.to_s + "\r\n"].join("")
        s = [s, "\r\n"].join("")
        return s.encode(charset, :invalid => :replace, :undef => :replace)
      else
        return RESPONSE[204]
      end
    end

    def ssu_is_empty(args)
      if args.empty? or args[0].empty?
        return 1
      else
        return 0
      end
    end

    def ssu_is_digit(args)
      s = args[0]
      for i in 0..s.length-1
        if s[i] =~ /[[:digit:]]/
          next
        else
          return 0
        end
      end
      return 1
    end

    def ssu_is_alpha(args)
      s = args[0]
      for i in 0..s.length-1
        if s[i] =~ /[[:alpha:]]/ # /(?a:[[:alpha:]])/
          next
        else
          return 0
        end
      end
      return 1
    end

    def ssu_length(args)
      s = args[0]
      return s.length
    end

    def ssu_substr(args)
      s = args[0]
      if ssu_is_digit([args[1]]) == 1
        start = ssu_zen2han([args[1]]).to_i
        if start > s.length
          return ''
        end
      else
        return ''
      end
      if args.length == 2
        end_ = s.length
      elsif args.length == 3 and ssu_is_digit([args[2]]) == 1
        end_ = (start + ssu_zen2han([args[2]]).to_i)
      else
        return ''
      end
      return s[start..end_-1]
    end

    def ssu_sprintf(args)
      return sprintf(args[0], *args[1..-1])
    end

    ZEN = {'０' => '0', '１' => '1', '２' => '2', '３' => '3', '４' => '4',
           '５' => '5', '６' => '6', '７' => '7', '８' => '8', '９' => '9',
           '．' => '.', '＋' => '+', '−' => '-',}
    HAN = {'0' => '０', '1' => '１', '2' => '２', '3' => '３', '4' => '４',
           '5' => '５', '6' => '６', '7' => '７', '8' => '８', '9' => '９',
           '.' => '．', '+' => '＋', '-' => "FF0D".to_i(16).chr('UTF-8'),}

    def ssu_zen2han(args)
      s = args[0]
      buf = ''
      for i in 0..s.length-1
        c = s[i]
        if ZEN.include?(c)
          buf = [buf, ZEN[c]].join("")
        else
          buf = [buf, s[i]].join("")
        end
      end
      return buf
    end

    def ssu_han2zen(args)
      s = args[0]
      buf = ''
      for i in 0..s.length-1
        c = s[i]
        if HAN.include?(c)
          buf = [buf, HAN[c]].join("")
        else
          buf = [buf, s[i]].join("")
        end
      end
      return buf
    end

    RE_CONDITION = Regexp.new('(>=|<=|>|<|==|!=|＞＝|＜＝|＞|＜|！＝|＝＝)')

    def eval_condition(left, ope, right)
      if ssu_is_digit([left]) == 1 and \
        ssu_is_digit([right]) == 1
        left = ssu_zen2han([left]).to_f
        right = ssu_zen2han([right]).to_f
      elsif ['>', '＞', '>=', '＞＝', '<', '＜', '<=', '＜＝'].include?(ope)
        left = left.length
        right = right.length
      end
      result = false
      if ['>', '＞'].include?(ope)
        result = (left > right)
      elsif ['>=', '＞＝'].include?(ope)
        result = (left >= right)
      elsif ['<', '＜'].include?(ope)
        result = (left < right)
      elsif ['<=', '＜＝'].include?(ope)
        result = (left <= right)
      elsif ['==', '＝＝'].include?(ope)
        result = (left == right)
      elsif ['!=', '！＝'].include?(ope)
        result = (left != right)
      else
        #pass # 'should not reach here'
      end
      return result
    end

    def ssu_if(args)
      condition = args[0]
      match = RE_CONDITION.match(condition)
      if match != nil
        left = match.pre_match
        ope = match[0]
        right = match.post_match
        result = eval_condition(left, ope, right)
        if result
          return args[1]
        end
      end
      if args.length == 3
        return args[2]
      else
        return ''
      end
    end

    def ssu_unless(args)
      condition = args[0]
      match = RE_CONDITION.match(condition)
      if match != nil
        left = match.pre_match
        ope = match[0]
        right = match.post_match
        result = eval_condition(left, ope, right)
        if not result
          return args[1]
        end
      end
      if args.length == 3
        return args[2]
      else
        return ''
      end
    end

    def ssu_iflist(args)
      left = args[0]
      i = 1
      while true
        if args[i..-1].length < 2
          break
        end
        ope_right = args[i]
        match = RE_CONDITION.match(ope_right) # FIXME: 左辺に演算子を入れた場合にも動作するようにする
        if match != nil
          if not match.pre_match.strip.empty?
            next
          end
          ope = match[0]
          right = match.post_match
          result = eval_condition(left, ope, right)
          if result
            return args[i + 1]
          end
        end
        i += 2
      end
      return ''
    end

    def ssu_nswitch(args)
      num = args[0]
      if ssu_is_digit([num]) == 1
        num = ssu_zen2han([num]).to_i
        if 0 < num and num < args.length
          return args[num]
        end
      end
      return ''
    end

    def ssu_count(args)
      return args[0].scan(args[1]).size
    end

    def ssu_compare(args)
      if args[0] == args[1]
        return 1
      else
        return 0
      end
    end

    def ssu_compare_head(args)
      s0 = args[0]
      s1 = args[1]
      if s1.start_with?(s0)
        return 1
      else
        return 0
      end
    end

    def ssu_compare_tail(args)
      s0 = args[0]
      s1 = args[1]
      if s1.end_with?(s0)
        return 1
      else
        return 0
      end
    end

    def ssu_erase(args)
      return args[0].gsub(args[1], '')
    end

    def ssu_erase_first(args)
      tmp = args[0].partition(args[1])
      return tmp[0] + tmp[2]
    end

    def ssu_replace(args)
      return args[0].gsub(args[1], args[2])
    end

    def ssu_replace_first(args)
      tmp = args[0].partition(args[1])
      if tmp[1].empty?
        return tmp[0]
      else
        return tmp[0] + args[2] + tmp[2]
      end
    end

    def ssu_split(args) ## FIXME: 空要素分割
      s0 = args[0]
      if args.length >= 2
        s1 = args[1]
      else
        s1 = ' ' ## FIXME
      end
      if args.length == 3
        num = args[2]
        if ssu_is_digit([num]) == 1
          num = ssu_zen2han([num]).to_i
        end
        value_list = s0.split(s1, num + 1)
      else
        value_list = s0.split(s1, -1)
      end
      @value = value_list
      return value_list.length
    end

    def ssu_switch(args)
      left = args[0]
      i = 1
      while true
        if args[i..-1].length < 2
          break
        end
        right = args[i]
        if left == right # FIXME: 左辺、右辺が数値でなくともエラーにならない
          return args[i + 1]
        end
        i += 2
      end
      return ''
    end

    def ssu_kata2hira(args) ## FIXME: not supported yet
      return ''
    end

    def ssu_hira2kata(args) ## FIXME: not supported yet
      return ''
    end

    def ssu_calc(args) ## FIXME: not supported yet
      return 0
    end

    def ssu_calc_float(args) ## FIXME: not supported yet
      return 0
    end

    def evaluate_request(req)
      req_type = nil
      argument = []
      charset = 'CP932' # default
      header = req.lines
      line = header.shift
      if line == nil
        return req_type, argument, charset
      end
      line = line.force_encoding(charset).strip()
      if line.empty?
        return req_type, argument, charset
      end
      for request in ['EXECUTE', 'GET Version']
        if line.start_with?(request)
          req_type = request
          break
        end
      end
      for line in header
        line = line.force_encoding(charset).strip()
        if line.empty?
          next
        end
        if not line.include?(':')
          next
        end
        key, value = line.split(':', 2)
        key.strip!
        value.strip!
        if key == 'Charset'
          charset = value
          begin
            codecs.lookup(charset)
          rescue
            Logging::Logging.warning('Unsupported charset ' + charset.to_s)
          end
        end
        if key.start_with?('Argument') ## FIXME
          argument << value
        else
          next
        end
      end
      return req_type, argument, charset
    end
  end
end
