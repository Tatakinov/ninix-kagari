# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2004-2017 by Shyouzou Sugitani <shy@users.osdn.me>
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
    buf.join
  end

  def self.expand(s, start)
    segments = []
    repeat_count = nil
    validity = 0
    i = start
    j = s.length
    buf = []
    while i < j
      if s[i] == "\\"
        if i + 1 < j and '(|)'.include?(s[i + 1])
          buf << s[i + 1]
        else
          buf << s[i..i + 1]
        end
        i += 2
      elsif s[i] == '('
        if validity.zero?
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
    case validity
    when 2
      expanded = segments[1..segments.length-1].sample
      unless repeat_count.nil?
        expanded = (expanded * rand(repeat_count))
      end
      return i, segments[0] + expanded
    when 0
      return j, buf.join
    else
      return j, s[start..s.length-1]
    end
  end
end
