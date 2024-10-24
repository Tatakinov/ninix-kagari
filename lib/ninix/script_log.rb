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
require 'gtk3'

module ScriptLog
  include GetText

  bindtextdomain('ninix-kagari')

  class Window < Gtk::Window
    def initialize
      super('Script Log')
      self.set_default_size(640, 360)
      box = Gtk::Box.new(:vertical, 0)
      self.add(box)
      scroll = Gtk::ScrolledWindow.new
      scroll.set_policy(:automatic, :automatic)
      box.pack_start(scroll, expand: true, fill: true, padding: 0)
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
      scroll.add(tree)
      self.signal_connect('delete_event') do |w|
        w.hide
      end
      box.show_all
    end

    def append_data(name, script)
      i = @model.append
      i[0] = Time.now.to_s
      i[1] = name
      i[2] = script
    end
  end
end
