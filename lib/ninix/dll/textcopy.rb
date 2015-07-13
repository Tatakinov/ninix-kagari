# -*- coding: utf-8 -*-
#
#  textcopy.rb - a TEXTCOPY compatible Saori module for ninix
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"

require_relative "../dll"


module TextCopy

  class Saori < DLL::SAORI

    def initialize
      super()
      @clipboard = nil
    end

    def setup
      @clipboard = Gtk::Clipboard.get(Gdk::Selection::PRIMARY)
      return 1
    end

    def finalize
      @clipboard = nil
      return 1
    end

    def execute(argument)
      if not argument or @clipboard == nil
        return RESPONSE[400]
      end
      text = argument[0]
      @clipboard.set_text(text)
      if argument.length >= 2 and argument[1] != 0
        return ["SAORI/1.0 200 OK\r\n",
                "Result: ",
                argument[0].encode(@charset, :invalid => :replace),
                "\r\n\r\n"].join("")
      else
        return RESPONSE[204]
      end
    end
  end
end
