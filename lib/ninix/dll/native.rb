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

require "fiddle"
require "fiddle/import"

require_relative "../logging"

module Native

  extend Fiddle::Importer
  begin
    dlload "kernel32.dll"
    include Fiddle::Win32Types
    extern "int SetDllDirectory(LPCSTR)"
    extern "PVOID GlobalAlloc(UINT, size_t)"
    extern "PVOID GlobalFree(PVOID)"
    
    $_native = self
  rescue
    $_native = nil
  end

  class Shiori

    def initialize(dll_name)
      @dll_name = dll_name
      @handle = nil
      @func = {}
    end

    def find(topdir, dll_name)
      result = 0
      # FIXME
      if $_native.nil?
        begin
          handle = Fiddle::Handle.new(File.join(topdir, dll_name))
          handle.close
          result = 1000
        rescue
          result = 0
        end
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: a Real SHIORI loader for ninix\n" \
        "        Copyright (C) 2024 by Tatakinov")
    end

    def load(dir: nil)
      # FIXME
      return 0 unless $_native.nil?
      unless dir.end_with?(File::SEPARATOR)
        dir = [dir, File::SEPARATOR].join
      end
      @handle = Fiddle::Handle.new(File.join(dir, @dll_name))
      @func[:load] = Fiddle::Function.new(@handle['load'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
      @func[:request] = Fiddle::Function.new(@handle['request'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @func[:unload] = Fiddle::Function.new(@handle['unload'], [], Fiddle::TYPE_INT)
      buf = Fiddle::Pointer.malloc(dir.bytesize + 1, freefunc = nil)
      buf[0, dir.bytesize] = dir
      return @func[:load].call(buf, dir.bytesize)
    end

    def unload
      ret = @func[:unload].call()
      @func = {}
      @handle.close
    end

    def request(req)
      buf = Fiddle::Pointer.malloc(req.bytesize + 1, freefunc = nil)
      buf[0, req.bytesize] = req
      len = [req.bytesize].pack('l!')
      result = @func[:request].call(buf, len)
      len, = len.unpack('l!')
      ret = result[0, len].to_s
      Fiddle.free(result)
      return ret
    end
  end
end
