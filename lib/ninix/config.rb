# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2003-2019 by Shyouzou Sugitani <shy@users.osdn.me>
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
    has_bom = File.open(path) {|f| f.read(3) } == "\xEF\xBB\xBF"
    charset = has_bom ? 'UTF-8' : 'CP932'
    buf = []
    File.open(path, has_bom ? 'rb:BOM|UTF-8' : 'rb') {|f|
      while line = f.gets
        line = line.strip
        buf << line unless line.empty?
      end
    }
    return create_from_buffer(buf, :charset => charset)
  end

  def self.create_from_buffer(buf, charset: 'CP932')
    dic = Config.new
    buf.each do |line|
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
    NConfig::Config.new
  end
end
