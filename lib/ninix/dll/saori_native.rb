# -*- coding: utf-8 -*-
#
#  saori_cpuid.rb - a saori_cpuid compatible Saori module for ninix
#  Copyright (C) 2024 Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'fiddle'

require_relative '../dll'

module SaoriNative

  class Saori < DLL::SAORI
    def self.create(name)
      begin
        instance = self.new(name)
      rescue
        return nil
      end
      return instance
    end

    def initialize(name)
      @func = {}
      filename = File.basename(name, ".*")
      @handle = Fiddle::Handle.new(name)
      @func[:load] = Fiddle::Function.new(@handle[filename + '_saori_load'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
      @func[:request] = Fiddle::Function.new(@handle[filename + '_saori_request'], [Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @func[:unload] = Fiddle::Function.new(@handle[filename + '_saori_unload'], [Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
    end

    def load(dir: nil)
      unless dir.end_with?(File::SEPARATOR)
        dir = [dir, File::SEPARATOR].join()
      end
      path = Fiddle::Pointer.malloc(
        dir.bytesize + 1,
        freefunc=nil
      )
      path[0, dir.bytesize] = dir
      @id = @func[:load].call(path, dir.bytesize)
      1
    end

    def unload
      @func[:unload].call(@id)
      @handle.close
    end

    def request(req)
      request = Fiddle::Pointer.malloc(
        req.bytesize + 1,
        freefunc=nil
      )
      request[0, req.bytesize] = req
      rlen =[req.bytesize].pack("l!")
      result = @func[:request].call(@id, request, rlen)
      rlen, = rlen.unpack("l!")
      unless result.null?
        ret = result[0, rlen].to_s
        Fiddle.free(result)
        ret
      else
        ''
      end
    end
  end
end
