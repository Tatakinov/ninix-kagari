# -*- coding: utf-8 -*-
#
#  satori_native.rb - a (Real) Satori SHIORI loader for ninix
#  Copyright (C) 2025 by Tatakinov
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

module Satori_native

  extend Fiddle::Importer
  begin
    dlload "libsatori.#{RbConfig::CONFIG['SOEXT']}"
    extern 'int satori_load(char *, long)'
    extern 'int satori_unload(int)'
    extern 'char *satori_request(int, char *, long *)'

    $_satori = self
  rescue => e
    p [:debug, e]
    $_satori = nil
  end

  def self.list_dict(top_dir)
    buf = []
    begin
      dir_list = Pathname(top_dir).children().map {|x| x.relative_path_from(Pathname(top_dir)).to_path }
    rescue #except OSError:
      dir_list = []
    end
    for filename in dir_list
      basename = File.basename(filename, '.*')
      ext = File.extname(filename)
      ext = ext.downcase
      if (filename.downcase.start_with?('dic') and \
          ['.txt', '.sat'].include?(ext)) or \
        ['replace.txt', 'replace_after.txt',
         'satori_conf.txt', 'satori_conf.sat'].include?(filename.downcase) # XXX
        buf << File.join(top_dir, filename)
      end
    end
    return buf
  end

  class Shiori

    def initialize(dll_name)
      @dll_name = dll_name
      @handle = nil
      @func = {}
    end

    def find(topdir, dll_name)
      result = 0
      unless $_satori.nil?
        unless Satori_native.list_dict(topdir).empty?
          result = 300
        end
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: a (Real) Satori loader for ninix\n" \
        "        Copyright (C) 2025 by Tatakinov")
    end

    def load(dir: nil)
      unless dir.end_with?(File::SEPARATOR)
        dir = [dir, File::SEPARATOR].join
      end
      buf = Fiddle::Pointer.malloc(dir.bytesize + 1, free = nil)
      buf[0, dir.bytesize] = dir
      @id = $_satori.satori_load(buf, dir.bytesize)
      if @id == 0
        return 0
      end
      return 1
    end

    def unload
      $_satori.satori_unload(@id)
    end

    def request(req)
      buf = Fiddle::Pointer.malloc(req.bytesize + 1, free = nil)
      buf[0, req.bytesize] = req
      len = [req.bytesize].pack('l!')
      result = $_satori.satori_request(@id, buf, len)
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
