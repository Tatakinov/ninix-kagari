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

  CP_ACP = 0
  GPTR = 0x40

  extend Fiddle::Importer
  begin
    dlload "kernel32.dll"
    extern "int SetDllDirectoryW(wchar_t *)"
    extern "void *GlobalAlloc(unsigned int, size_t)"
    extern "void *GlobalFree(void *)"
    extern "int WideCharToMultiByte(unsigned int, unsigned long, wchar_t *, int, char *, int, void *, void *)"

    $_kernel32 = self
  rescue
    $_kernel32 = nil
  end

  class Shiori

    def initialize(dll_name)
      @dll_name = dll_name
      @handle = nil
      @func = {}
    end

    def find(topdir, dll_name)
      result = 0
      unless $_kernel32.nil?
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
      unless dir.end_with?(File::SEPARATOR)
        dir = [dir, File::SEPARATOR].join
      end
      $_kernel32.SetDllDirectoryW(dir.encode('UTF-16LE'))
      @handle = Fiddle::Handle.new(File.join(dir, @dll_name))
      @func[:load] = Fiddle::Function.new(@handle['load'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
      @func[:request] = Fiddle::Function.new(@handle['request'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @func[:unload] = Fiddle::Function.new(@handle['unload'], [], Fiddle::TYPE_INT)
      null = Fiddle::Pointer[0]
      len = $_kernel32.WideCharToMultiByte(CP_ACP, 0, dir.encode('UTF-16LE'), dir.size, null, 0, null, null)
      buf = $_kernel32.GlobalAlloc(GPTR, len)
      len = $_kernel32.WideCharToMultiByte(CP_ACP, 0, dir.encode('UTF-16LE'), dir.size, buf, len, null, null)
      ret =  @func[:load].call(buf, len)
      $_kernel32.SetDllDirectoryW(null)
      return ret
    end

    def unload
      ret = @func[:unload].call()
      @func = {}
      @handle.close
    end

    def request(req)
      buf = $_kernel32.GlobalAlloc(GPTR, req.bytesize + 1)
      buf[0, req.bytesize] = req
      len = [req.bytesize].pack('l!')
      result = @func[:request].call(buf, len)
      len, = len.unpack('l!')
      ret = result[0, len].to_s
      $_kernel32.GlobalFree(result)
      return ret
    end
  end
end
