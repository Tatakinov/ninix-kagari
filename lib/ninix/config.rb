# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2003-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require_relative "logging"

module NConfig

  class Config < Hash

    def get(name, default: nil)
      keylist = (name.is_a?(Array) ? name : [name])
      key = keylist.find {|x| keys.include?(x) }
      key.nil? ? default : self[key]
    end
  end

  def self.create_from_file(path)
    charset = 'CP932' # default
    f = File.open(path, 'rb')
    if f.read(3).bytes == [239, 187, 191] # "\xEF\xBB\xBF"
      f.close
      f = File.open(path, 'rb:BOM|UTF-8')
      charset = 'UTF-8'
    else
      f.seek(0) # rewind
    end
    buf = []
    while line = f.gets
      buf << line.strip unless line.strip.empty?
    end
    f.close
    return create_from_buffer(buf, :charset => charset)
  end

  def self.create_from_buffer(buf, charset: 'CP932')
    dic = Config.new
    for line in buf
      line = line.force_encoding(charset).encode(
        "UTF-8", :invalid => :replace, :undef => :replace)
      key, value = line.split(",", 2)
      next if key.nil? or value.nil?
      key.strip!
      case key
      when 'charset'
        value.strip!
        if Encoding.name_list.include?(value)
          charset = value
        else
          Logging::Logging.error('Unsupported charset ' + value)
        end
      when 'refreshundeletemask', 'icon', 'cursor', 'shiori', 'makoto'
        dic[key] = value
      else
        dic[key] = value.strip
      end
    end
    return dic
  end

  def self.null_config()
    NConfig::Config.new()
  end
end
