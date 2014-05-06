# -*- coding: utf-8 -*-
#
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

require "ninix/config"

module Alias

  def self.fatal(error)
    #logging.error('alias.py: {0}'.format(str(error)))
    return NConfig.null_config()
  end

  def self.create_from_file(path)
    f = File.open(path, 'rb')
    buf = []
    while line = f.gets
      if line.strip
        buf << line.strip
      end
    end
    return create_from_buffer(buf)
  end

  def self.create_from_buffer(buf)
    re_alias = Regexp.new("^(sakura|kero|char[0-9]+)\.surface\.alias$")
    dic = NConfig::Config.new
    i, j = 0, buf.length
    while i < j
      line = buf[i]
      i += 1
      if line.length == 0
        next
      end
      match = re_alias.match(line)
      if match
        name = line
        table = {}
        begin
          while 1
            if i < j
              line = buf[i]
              i += 1
            else
              raise ValueError('unexpedted end of file')
            end
            line = line.sub('\x81\x40', '').strip()
            if line.length == 0
              next
            elsif line == '{'
              break
            end
            raise ValueError('open brace not found')
          end
          while 1
            if i < j
              line = buf[i]
              i += 1
            else
              raise ValueError('unexpected end of file')
            end
            line = line.sub('\x81\x40', '').strip()
            if line.length == 0
              next
            elsif line == '}'
              break
            end
            line = line.split(',', 2)
            if line.length == 2
              key = line[0].strip
              values = line[1].strip
            else
              #raise ValueError('malformed line found')
            end
            if values and \
              values.start_with?('[') and values.end_with?(']')
              table[key] = []
              for value in values[1, values.length - 2].split(',')
                begin
                  value = str(int(value))
                rescue
                  #except ValueError:
                  #pass
                end
                table[key] << value
            #  else
            #    raise ValueError('malformed line found')
              end
            end
          end
        rescue# except ValueError as error
          return fatal(error)
        end
        dic[name] = table
      else
        line = line.split(',', 2)
        if line.length == 2
          key = line[0].strip
          value = line[1].strip
        else
          #return fatal('malformed line found')
        end
        if key == 'makoto'
          if value and \
            value.start_with('[') and value.end_with(']')
            value = value[1, value.length - 2].split(',')
          else
            value = [value]
          end
        end
        dic[key] = value
      end
    end
    return dic
  end

  class TEST

    def initialize(path)
      conf = Alias::create_from_file(path)
      print("ALIAS:   ", conf, "\n")
    end
  end
end

$:.unshift(File.dirname(__FILE__))

Alias::TEST.new(ARGV.shift)