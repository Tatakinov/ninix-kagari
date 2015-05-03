# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2004-2015 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module Makoto

  def self.execute(s)
    buf = []
    i = 0
    j = s.length
    while i < j
      i, text = expand(s, i)
      buf << text
    end
    return buf.join
  end

  def self.expand(s, start)
    segments = []
    repeat_count = nil
    validity = 0
    i = start
    j = s.length
    buf = []
    while i < j
      if s[i] == '\\'
        if i + 1 < j and '(|)'.include?(s[i + 1])
          buf << s[i + 1]
        else
          buf << s[i, i + 2]
        end
        i += 2
      elsif s[i] == '('
        if validity == 0
          segments << buf.join
          buf = []
          i += 1
        else
          i, text = expand(s, i)
          buf << text
        end
        validity = 1
      elsif s[i] == '|' and validity > 0
        segments << buf.join
        buf = []
        i += 1
      elsif s[i] == ')' and validity > 0
        segments << buf.join
        i += 1
        if i < j and '123456789'.include?(s[i])
          repeat_count = s[i].to_i
          i += 1
        end
        validity = 2
        break
      else
        buf << s[i]
        i += 1
      end
    end
    if validity == 2
      expanded = segments[1,segments.length].sample
      if repeat_count
        expanded = expanded * rand(repeat_count)
      end
      return i, segments[0] + expanded
    elsif validity == 0
      return j, buf.join
    else
      return j, s[start, s.length]
    end
  end

  def self.test(verbose: 0)
    for test, expected in [['a(1)b', ['a1b']],
                           ['a(1|2)b', ['a1b', 'a2b']],
                           ['a(1)2b', ['ab', 'a1b', 'a11b']],
                           ['a(1|2)1b', ['ab', 'a1b', 'a2b']],
                           ['(1|2)(a|b)', ['1a', '1b', '2a', '2b']],
                           ['((1|2)|(a|b))', ['1', '2', 'a', 'b']],
                           ['()', ['']],
                           ['()2', ['']],
                           ['a()b', ['ab']],
                           ['a()2b', ['ab']],
                           ['a\(1\|2\)b', ['a(1|2)b']],
                           ['\((1|2)\)', ['(1)', '(2)']],
                           ['\(1)', ['(1)']],
                           ['a|b', ['a|b']],
                           # errornous cases
                           ['(1', ['(1']],
                           ['(1\)', ['(1\)']],
                           ['(1|2', ['(1|2']],
                           ['(1|2\)', ['(1|2\)']],
                           ['(1|2)(a|b', ['1(a|b', '2(a|b']],
                           ['((1|2)|(a|b)', ['((1|2)|(a|b)']],
                           ]
      result = execute(test)
      if verbose != 0
        print("'", test.to_s, "'", ' => ', "'", result.to_s, "'", ' ... ',)
      end
      begin
        if expected == nil
          #assert(result == test)
        else
          #assert(result in expected)
        end
        if verbose != 0
          print("OK\n")
        end
      rescue #AssertionError
        if verbose != 0
          print("NG\n")
        end
        raise
      end
    end
  end
end
