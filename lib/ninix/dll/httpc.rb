# -*- coding: utf-8 -*-
#
#  httpc.rb - a HTTPC compatible Saori module for ninix
#  Copyright (C) 2011-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "uri"
require "open-uri"

require "gtk3"

require_relative "../dll"


module Httpc

  class Saori < DLL::SAORI

    def initialize
      super()
      @__sakura = nil
      @__bg = {}
    end

    def finalize
      for timeout_id in @__bg.keys
        GLib::Source.remove(timeout_id)
      end
      return 1
    end

    def need_ghost_backdoor(sakura)
      @__sakura = sakura
    end

    def check_import
      if @__sakura != nil
        return 1
      else
        return 0
      end
    end

    def get(url, start: nil, end_: nil)
      url = URI.parse(url)
      if not ((url.scheme == 'http' or url.scheme == 'https') and
              #url.params == nil and
              url.query == nil and
              url.fragment == nil)
        return RESPONSE[400] # XXX
      end
      data = open(url) do |f|
        @charset = f.charset
        f.read()
      end
      if start != nil
        fail "assert" unless end_ != nil
        nc = 0
        ls = start.length
        le = end_.length
        result = []
        while true
          ns = data.index(start, nc)
          if ns == nil
            break
          end
          ns += ls
          ne = data.index(end_, ns)
          if ne == nil
            break
          end
          nc = (ne + le)
          result << data[ns..ne-1]
        end
      else
        result = [data]
      end
      return result
    end

    def execute(argument)
      if argument == nil
        return RESPONSE[400]
      end
      bg = nil
      @charset = nil
      process_tag = nil
      if argument.length >= 1
        if argument[0] == 'bg'
          if argument.length < 2
            # 'bgするならIDを指定していただけませんと。'
            return RESPONSE[400]
          end
          bg = argument[1]
          argument = argument[2..-1]
        end
      end
      if argument.length >= 1
        if ['sjis', 'utf-8', 'utf-16be', 'utf-16le'].include?(argument[0])
          @charset = argument[0]
          argument = argument[1..-1]
        elsif argument[0] == 'euc'
          @charset = 'EUC-JP'
          argument = argument[1..-1]
        elsif argument[0] == 'jis'
          @charset = 'ISO-2022-JP '
          argument = argument[1..-1]
        end
        if argument[0] == 'erase_tag'
          process_tag = lambda {} ## FIXME: not supported yet
          argument = argument[1..-1]
        elsif argument[0] == 'translate_tag'
          process_tag = lambda {} ## FIXME: not supported yet
          argument = argument[1..-1]
        end
      end
      if argument.empty?
        ##fail "assert" unless bg == nil and process_tag == nil
        return "SAORI/1.0 200 OK\r\nResult: " + @loaded.to_s + " \r\n\r\n"
      elsif argument.length > 3
        return RESPONSE[400]
      elsif argument.length == 2 # FIXME: not supported yet
        return "SAORI/1.0 200 OK\r\nResult: 0\r\n\r\n"
      else
        if bg != nil # needs multi-threading?
          timeout_id = GLib::Timeout.add(1000) { notify(bg, argument, process_tag) } # XXX
          @__bg[timeout_id] = bg
          return nil # "SAORI/1.0 204 No Content\r\n\r\n"
        else
          data = get(argument[0], :start => argument[1], :end_ => argument[2])
          if data.empty?
            return nil # "SAORI/1.0 204 No Content\r\n\r\n"
          end
          if data == RESPONSE[400] # XXX
            return data
          end
          result = "SAORI/1.0 200 OK\r\n" + "Result: " + data[0].to_s + "\r\n"
          for n in 0..data.length-1
            result = [result,
                      "Value" + n.to_s + ": " + data[n].to_s + "\r\n"].join("")
          end
          result += "\r\n"
          return result.encode('Shift_JIS', :invalid => :replace, :undef => :replace)
        end
      end
    end

    def notify(id, argument, process_tag)
      result = get(argument[0], :start => argument[1], :end_ => argument[2])
      if process_tag != nil
        #pass ## FIXME: not supported yet
      end
      @__sakura.notify_event('OnHttpcNotify', id, nil, *result)
    end
  end
end
