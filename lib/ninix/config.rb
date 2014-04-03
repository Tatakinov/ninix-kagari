# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2003-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#


module NConfig

  class Config < Hash

    def get_with_type(name, conv, default=nil)
      value = self.get(name)
      if value is nil
        return default
      end
      ##assert conv is not None
      begin
        return conv(value)
      rescue
        return default # XXX
      end
    end

    def get(name, default=None)
      if name.class == Array
        keylist = name
      else
        keylist = [name]
      end
      for key in keylist
        if self.has_key?(key)
          return self[key]
        end
      end
      return default
    end

#    def __str__
#       return ''.join(
#           ['{0},{1}\n'.format(key, value) for key, value in self.items()])
#    end
  end

  def self.create_from_file(path)
    charset = 'CP932' # default
    f = File.open(path, 'rb')
    if f.read(3) == "\xEF\xBB\xBF"
      charset = 'BOM|UTF-8'
    else
      f.seek(0) # rewind
    end
    buf = []
    while line = f.gets
      if line.strip
        buf << line.strip
      end
    end
    return create_from_buffer(buf, charset)
  end

  def self.create_from_buffer(buf, charset='CP932')
    dic = Config.new
    for line in buf
      begin
        key, value = line.split(",", 2)
      rescue
        continue
      end
      key = key.strip
      if key == 'charset'
        value = value.strip
        if Encoding.name_list.include?(value)
          charset = value
        else
          #logging.error('Unsupported charset {0}'.format(value))
        end
      elsif ['refreshundeletemask', 'icon', 'cursor', 'shiori', 'makoto'].include?(key)
        dic[key] = value.strip().encode(charset)
      else
        dic[key] = value.encode(charset, :invalid => :replace).strip
      end
    end
    return dic
  end

  def self.null_config()
    return NConfig::Config.new()
  end

  class TEST

    def initialize(path)
      conf = NConfig::create_from_file(path)
      for key in conf.keys 
        print("Key:   ", key, "\n")
        print("VALUE: ", conf[key], "\n")
      end
    end
  end
end

$:.unshift(File.dirname(__FILE__))

NConfig::TEST.new(ARGV.shift)
