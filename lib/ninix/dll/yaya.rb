# -*- coding: utf-8 -*-
#
#  yaya.rb - a (Real) YAYA loader for ninix
#  Copyright (C) 2004 by linjian
#  Copyright (C) 2004-2019 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#  Copyright (C) 2011 by henryhu
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

$_yaya = nil

module Yaya
  extend Fiddle::Importer
  begin
    dlload "libaya5.so"
    extern "long multi_load(char *, long)"
    extern "int multi_unload(long)"
    extern "char *multi_request(long, char *, long *)"
    
    $_yaya = self
  rescue
    $_yaya = nil
  end

  class Shiori

    def initialize(dll_name)
      @dll_name = dll_name
      @pathdic = []
      @reqdic = []
      @id = nil
    end

    def find(topdir, dll_name)
      result = 0
      unless $_yaya.nil?
        if File.file?(File.join(topdir, 'yaya.txt'))
          result = 205
        elsif not dll_name.nil? and \
             File.file?(File.join(topdir, [dll_name[0..-3], 'txt'].join('')))
          result = 105
        end
      end
      result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: a (Real) YAYA loader for ninix\n" \
        "        Copyright (C) 2004 by linjian\n" \
        "        Copyright (C) 2004-2019 by Shyouzou Sugitani\n" \
        "        Copyright (C) 2011 by henryhu")
    end

    def load(dir: nil)
      @dir = dir
      return 0 if $_yaya.nil?
      if @dir.end_with?(File::SEPARATOR)
        #topdir = @dir
      else
        #topdir = [@dir, File::SEPARATOR].join()
        @dir = [@dir, File::SEPARATOR].join()
      end
      path = Fiddle::Pointer.malloc(
        @dir.bytesize + 1,
        freefunc=nil # Yaya will free this pointer
      )
      path[0, @dir.bytesize] = @dir
      @id = $_yaya.multi_load(path, @dir.bytesize)
      1
    end

    def unload
      $_yaya.multi_unload(@id) unless $_yaya.nil?
      @id = nil
    end

    def request(req_string)
      return '' if $_yaya.nil? # FIXME
      request = Fiddle::Pointer.malloc(
        req_string.bytesize + 1,
        freefunc=nil # Yaya will free this pointer
      )
      request[0, req_string.bytesize] = req_string
      rlen =[req_string.bytesize].pack("l!")
      ret = $_yaya.multi_request(@id, request, rlen)
      rlen, = rlen.unpack("l!")
      unless ret.null?
        ret[0, rlen].to_s
      else
        ''
      end
    end
  end
end
