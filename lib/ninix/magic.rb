# -*- coding: utf-8 -*-
#
#  magic.rb - mime detector with libmagic
#
#  The MIT License (MIT)
#
#  Copyright (C) 2026 Tatakinov
#
#  Permission is hereby granted, free of charge, to any person obtaining
#  a copy of this software and associated documentation files
#  (the "Software"), to deal in the Software without restriction,
#  including without limitation the rights to use, copy, modify, merge,
#  publish, distribute, sublicense, and/or sell copies of the Software,
#  and to permit persons to whom the Software is furnished to do so,
#  subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included
#  in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
#  ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
#  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
#  THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 'fiddle/import'

module Magic
  $_magic = nil

  if ENV.include?('MAGIC_LIB')
    begin
      module Any
        extend Fiddle::Importer
        dlload ENV['MAGIC_LIB']
        extern 'void *magic_open(int)'
        extern 'void magic_close(void *)'
        extern 'char *magic_error(void *)'
        extern 'int magic_load(void *, char *)'
        extern 'char *magic_file(void *, char *)'
        $_magic = self
      end
    rescue
      # nop
    end
  else
    begin
      module Linux
        extend Fiddle::Importer
        dlload 'libmagic.so.1'
        extern 'void *magic_open(int)'
        extern 'void magic_close(void *)'
        extern 'char *magic_error(void *)'
        extern 'int magic_load(void *, char *)'
        extern 'char *magic_file(void *, char *)'
        $_magic = self
      end
    rescue
      # nop
    end

    begin
      module Mac
        extend Fiddle::Importer
        dlload 'libmagic.1.dylib'
        extern 'void *magic_open(int)'
        extern 'void magic_close(void *)'
        extern 'char *magic_error(void *)'
        extern 'int magic_load(void *, char *)'
        extern 'char *magic_file(void *, char *)'
        $_magic = self
      end
    rescue
      # nop
    end

    begin
      module Windows
        extend Fiddle::Importer
        dlload 'magic1.dll'
        extern 'void *magic_open(int)'
        extern 'void magic_close(void *)'
        extern 'char *magic_error(void *)'
        extern 'int magic_load(void *, char *)'
        extern 'char *magic_file(void *, char *)'
        $_magic = self
      end
    rescue
      # nop
    end
  end

  def self.guess_mime(path)
    return nil if $_magic.nil?
    return nil unless File.exist?(path)
    return nil if File.directory?(path)
    m = $_magic.magic_open(0x10)
    $_magic.magic_load(m, nil)
    mime = $_magic.magic_file(m, path)
    ret = mime.to_s unless mime.null?
    return ret
  end
end
