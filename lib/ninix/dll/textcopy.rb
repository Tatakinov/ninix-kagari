# -*- coding: utf-8 -*-
#
#  textcopy.rb - a TEXTCOPY compatible Saori module for ninix
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.osdn.me>
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


module Textcopy

  class Saori < DLL::SAORI

    def initialize
      super
      @clipboard = nil
    end

    def setup
      @clipboard = Gtk::Clipboard.get('PRIMARY')
      1
    end

    def finalize
      @clipboard = nil
      1
    end

    def execute(argument)
      return RESPONSE[400] if argument.nil? or argument.empty? or @clipboard.nil?
      text = argument[0]
      @clipboard.set_text(text)
      if argument.length >= 2 and not argument[1].zero?
        "SAORI/1.0 200 OK\r\n" \
        "Result: " \
        "#{text.encode(@charset, :invalid => :replace, :undef => :replace)}" \
        "\r\n\r\n"
      else
        RESPONSE[204]
      end
    end
  end
end
