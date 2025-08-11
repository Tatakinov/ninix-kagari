# -*- coding: utf-8 -*-
#
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'gettext'
require 'gtk4'

module ScriptLog
  include GetText

  bindtextdomain('ninix-kagari')

  class Window < Gtk::Window
    def initialize
      super
      set_default_size(640, 360)
      box = Gtk::Box.new(:vertical, 0)
      set_child(box)
      scroll = Gtk::ScrolledWindow.new
      scroll.set_policy(:automatic, :automatic)
      #box.pack_start(scroll, expand: true, fill: true, padding: 0)
      box.append(scroll)
      @model = Gtk::ListStore.new(String, String, String)
      tree = Gtk::TreeView.new(@model)
      tree.selection.set_mode(:single)
      # FIXME gettext
      column = Gtk::TreeViewColumn.new('Time', Gtk::CellRendererText.new, { text: 0 })
      tree.append_column(column)
      column = Gtk::TreeViewColumn.new('Ghost name', Gtk::CellRendererText.new, { text: 1 })
      tree.append_column(column)
      column = Gtk::TreeViewColumn.new('Script', Gtk::CellRendererText.new, { text: 2 })
      tree.append_column(column)
      scroll.set_child(tree)
      signal_connect('close-request') do |w, e|
        w.hide
      end
      box.show
    end

    def append_data(name, script)
      i = @model.prepend
      i[0] = Time.now.to_s
      i[1] = name
      i[2] = script
    end
  end
end
