# -*- coding: utf-8 -*-
#
#  native.rb - a Real SHIORI loader for ninix
#  Copyright (C) 2025 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'open3'

require_relative '../logging'

module X86

  PROGRAM = (ENV.include?('X86_PROXY') and File.join(ENV['X86_PROXY'], 'ninix-proxy.exe') or 'ninix-proxy.exe')

  class Shiori

    def initialize(dll_name)
      @dll_name = dll_name
    end

    def find(topdir, dll_name)
      result = 0
      begin
        dll_path = File.join(topdir, dll_name)
        Open3.popen3(PROGRAM, dll_path) do |_write, read, _err, _th|
          result = 800 if read.read == 'true'
        end
      rescue
        # nop
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: a Real SHIORI loader for ninix\n" \
        "        Copyright (C) 2025 by Tatakinov")
    end

    def load(dir: nil)
      unless dir.end_with?(File::SEPARATOR)
        dir = [dir, File::SEPARATOR].join
      end
      dll_path = File.join(dir, @dll_name)
      dll_dir = File.dirname(dll_path)
      @write, @read, @err, @thread = Open3.popen3(PROGRAM, dll_path, dll_dir)
      return ret
    end

    def unload
      begin
        @write.write([0].pack('L'))
        @write.close
        @thread.join
      rescue
        # TODO error
      end
    end

    def request(req)
      req = [[req.bytesize].pack('L'), request.force_encoding(Encoding::BINARY)].join
      begin
        @write.write(req)
      rescue
        return ''
      end
      len = nil
      begin
        len = @read.read(4)&.unpack('L').first
      rescue
        return ''
      end
      if len.nil?
        # TODO error
        return
      end
      if len.zero?
        return ''
      end
      res = @ayu_read.read(len)
      return res
    end
  end
end
