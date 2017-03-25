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

require_relative "config"
require_relative "logging"

module Alias

  def self.fatal(error)
    Logging::Logging.error('alias.rb: ' + error.to_s)
    NConfig.null_config
  end

  def self.create_from_file(path)
    buf = []
    File::open(path, 'rb') {|f|
      while line = f.gets
        line = line.strip
        buf << line unless line.empty?
      end
    }
    create_from_buffer(buf)
  end

  def self.create_from_buffer(buf)
    re_alias = Regexp.new('\A(sakura|kero|char[0-9]+)\.surface\.alias\z')
    dic = NConfig::Config.new
    i, j = 0, buf.length
    while i < j
      line = buf[i]
      i += 1
      next if line.length.zero?
      match = re_alias.match(line)
      unless match.nil?
        name = line
        table = {}
        begin
          while true
            if i < j
              line = buf[i]
              i += 1
            else
              fail ValueError('unexpedted end of file')
            end
            line = line.gsub(0x81.chr + 0x40.chr, "").strip()
            next if line.length.zero?
            break if line == '{'
            fail ValueError('open brace not found')
          end
          while true
            if i < j
              line = buf[i]
              i += 1
            else
              fail ValueError('unexpected end of file')
            end
            line = line.gsub(0x81.chr + 0x40.chr, "").strip()
            next if line.length.zero?
            break if line == '}'
            line = line.split(',', 2)
            if line.length == 2
              key = line[0].strip
              values = line[1].strip
            else
              fail 'malformed line found'
            end
            if !values.empty? and \
              values.start_with?('[') and values.end_with?(']')
              table[key] = []
              for value in values[1, values.length - 2].split(',', 0)
                begin
                  value = Integer(value).to_s
                rescue
                  #pass
                end
                table[key] << value
              end
            else
              fail 'malformed line found'
            end
          end
        rescue => e
          return fatal(e.message)
        end
        dic[name] = table
      else
        line = line.split(',', 2)
        if line.length == 2
          key = line[0].strip
          value = line[1].strip
        else
          return fatal('malformed line found')
        end
        if key == 'makoto'
          if !value.empty? and \
            value.start_with('[') and value.end_with(']')
            value = value[1, value.length - 2].split(',', 0)
          else
            value = [value]
          end
        end
        dic[key] = value
      end
    end
    dic
  end
end
