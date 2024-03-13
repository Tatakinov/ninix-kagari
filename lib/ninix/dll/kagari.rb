# -*- coding: utf-8 -*-
#
#  native.rb - a Real SHIORI loader for ninix
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "fiddle/import"

require_relative "../logging"

module Kagari

  extend Fiddle::Importer
  begin
    dlload 'kagari.so'
    extern 'int load(char *, long)'
    extern 'int unload(int)'
    extern 'char *request(int, char *, long *)'

    $_kagari = self
  rescue
    $_kagari = nil
  end

  class Shiori

    def initialize(dll_name)
      @dll_name = dll_name
      @handle = nil
      @func = {}
    end

    def find(topdir, dll_name)
      result = 0
      unless $_kagari.nil?
        if File.exist?(File.join(topdir, 'kagari.conf.lua'))
          result = 300
        end
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: a (Real) KAGARI loader for ninix\n" \
        "        Copyright (C) 2024 by Tatakinov")
    end

    def load(dir: nil)
      unless dir.end_with?(File::SEPARATOR)
        dir = [dir, File::SEPARATOR].join
      end
      buf = Fiddle::Pointer.malloc(dir.bytesize + 1, free = nil)
      buf[0, dir.bytesize] = dir
      @id = $_kagari.load(buf, dir.bytesize)
      if @id ==-1
        return 0
      end
      return 1
    end

    def unload
      $_kagari.unload(@id)
    end

    def request(req)
      buf = Fiddle::Pointer.malloc(req.bytesize + 1, free = nil)
      buf[0, req.bytesize] = req
      len = [req.bytesize].pack('l!')
      result = $_kagari.request(@id, buf, len)
      len, = len.unpack('l!')
      unless result.null?
        ret = result[0, len].to_s
        Fiddle.free(result)
        ret
      else
        ''
      end
    end
  end
end
