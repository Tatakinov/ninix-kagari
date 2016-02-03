# -*- coding: utf-8 -*-
#
#  kawari8.rb - a (Real) 華和梨 loader for ninix
#  Copyright (C) 2002, 2003 by ABE Hideaki <abe-xx@eos.dricas.com>
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
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

module Kawari8
  extend Fiddle::Importer
  begin
    dlload "libshiori.so" # "_kawari8.so"
    extern "int load(const char *, long)"
    extern "char *request(const char *, long *)"
    extern "int unload()"
    @@_kawari8 = self
  rescue
    @@_kawari8 = nil
  end

  def self.exist?
    if @@_kawari8 != nil
      return true
    else
      return false
    end
  end

  class Shiori

    ##saori_list = {}

    def initialize(dll_name)
      @dll_name = dll_name
      @handle = 0
      @req = []
    end

    ##def use_saori(saori)
    ##  @saori = saori
    ##end

    def find(topdir, dll_name)
      result = 0
      if Kawari8.exist? and File.file?(File.join(topdir, 'kawarirc.kis'))
        result = 205
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: Real Kawari8 loader for ninix\n" \
        "        Copyright (C) 2002, 2003 by ABE Hideaki\n" \
        "        Copyright (C) 2002-2016 by Shyouzou Sugitani\n" \
        "        Copyright (C) 2002, 2003 by MATSUMURA Namihiko")
    end

    def load(dir: nil)
      @dir = dir
      if Kawari8.exist?
        ##reload(_kawari8)
        if not @dir.end_with?(File::SEPARATOR)
          @dir = [@dir, File::SEPARATOR].join()
        end
        ##_kawari8.setcallback(self.saori_exist,
        ##                     Shiori.saori_load,
        ##                     Shiori.saori_unload,
        ##                     Shiori.saori_request)
        dir_ptr = Fiddle::Pointer.malloc(
          @dir.bytesize + 1,
          freefunc=nil # Kawari8 will free this pointer
        )
        dir_ptr[0, @dir.bytesize] = @dir
        result = Kawari8.load(dir_ptr, @dir.bytesize)
        @handle = result
        if result != 0
          return 1
        else
          return 0
        end
      else
        return 0
      end
    end

    def unload
      if Kawari8.exist?
        Kawari8.unload() # unload(@handle)
        ##for name in list(Shiori.saori_list.keys())
        ##  if not name.startswith(os.fsdecode(self.dir))
        ##    continue
        ##  end
        ##  if Shiori.saori_list[name][1]:
        ##      Shiori.saori_list[name][0].unload()
        ##  end
        ##  del Shiori.saori_list[name]
        ##  # XXX
        ##  _kawari8.setcallback(lambda *a: 0, # dummy
        ##                       Shiori.saori_load,
        ##                       Shiori.saori_unload,
        ##                       Shiori.saori_request)
        ##end
      end
    end

    def request(req_string)
      if Kawari8.exist?
        req_ptr = Fiddle::Pointer.malloc(
          req_string.bytesize + 1,
          freefunc=nil # Kawari8 will free this pointer
        )
        req_ptr[0, req_string.bytesize] = req_string
        req_len = [req_string.bytesize].pack("l!")
        result = Kawari8.request(req_ptr, req_len)
        req_len, = req_len.unpack("l!")
        return result[0, req_len].to_s
      else
        return '' # FIXME
      end
    end

    ##def saori_exist(self, saori):
    ##    module = self.saori.request(saori)
    ##    if module:
    ##        Shiori.saori_list[saori] = [module, 0]
    ##        return len(Shiori.saori_list)
    ##    else:
    ##        return 0

    ##@classmethod
    ##def saori_load(cls, saori, path):
    ##    result = 0
    ##    if saori in cls.saori_list and cls.saori_list[saori][1] == 0:
    ##        result = cls.saori_list[saori][0].load(path)
    ##        cls.saori_list[saori][1] = result
    ##    return result

    ##@classmethod
    ##def saori_unload(cls, saori):
    ##    result = 0
    ##    if saori in cls.saori_list and cls.saori_list[saori][1] != 0:
    ##        result = cls.saori_list[saori][0].unload()
    ##        cls.saori_list[saori][1] = 0
    ##    return result

    ##@classmethod
    ##def saori_request(cls, saori, req):
    ##    result = b'SAORI/1.0 500 Internal Server Error'
    ##    if saori in cls.saori_list:
    ##        if cls.saori_list[saori][1] == 0:
    ##            head, tail = os.path.split(os.fsencode(saori))
    ##            cls.saori_list[saori][1] = cls.saori_list[saori][0].load(head)
    ##        if cls.saori_list[saori][1]:
    ##            result = cls.saori_list[saori][0].request(req)
    ##    return result

  end
end
