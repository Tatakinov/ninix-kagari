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

  class Item < GLib::Object
    type_register
    attr_accessor :time, :ghost_name, :script

    def initialize(time, ghost_name, script)
      super()
      @time = time
      @ghost_name = ghost_name
      @script = script
    end

=begin
    install_property(GLib::Param::String.new('time', 'time', 'Time', '', GLib::Param::READWRITE))
    install_property(GLib::Param::String.new('ghost_name', 'ghost_name', 'Ghost Name', '', GLib::Param::READWRITE))
    install_property(GLib::Param::String.new('script', 'script', 'Script', '', GLib::Param::READWRITE))
=end
  end

  class Window < Gtk::Window
    def initialize
      super
      # FIXME gettext
      set_default_size(640, 360)
      box = Gtk::Box.new(:vertical, 0)
      set_child(box)
      @scroll = Gtk::ScrolledWindow.new
      @scroll.set_policy(:automatic, :automatic)
      @scroll.set_vexpand(true)
      box.append(@scroll)
      @model = Gio::ListStore.new(Item.gtype)
      selection = Gtk::SingleSelection.new(@model)
      column_view = Gtk::ColumnView.new(selection)

      factory1 = Gtk::SignalListItemFactory.new
      factory1.signal_connect('setup') do |f, list_item|
        label = Gtk::Label.new
        label.halign = :start
        label.hexpand = true
        list_item.child = label
      end
      factory1.signal_connect('bind') do |f, list_item|
        label = list_item.child
        item = list_item.item
        label.text = item.time
      end
      column = Gtk::ColumnViewColumn.new('Time', factory1)
      column_view.append_column(column)

      factory2 = Gtk::SignalListItemFactory.new
      factory2.signal_connect('setup') do |f, list_item|
        label = Gtk::Label.new
        label.halign = :start
        label.hexpand = true
        list_item.child = label
      end
      factory2.signal_connect('bind') do |f, list_item|
        label = list_item.child
        item = list_item.item
        label.text = item.ghost_name
      end
      column = Gtk::ColumnViewColumn.new('Ghost Name', factory2)
      column_view.append_column(column)

      factory3 = Gtk::SignalListItemFactory.new
      factory3.signal_connect('setup') do |f, list_item|
        label = Gtk::Label.new
        label.halign = :start
        label.hexpand = true
        list_item.child = label
      end
      factory3.signal_connect('bind') do |f, list_item|
        label = list_item.child
        item = list_item.item
        label.text = item.script
      end
      column = Gtk::ColumnViewColumn.new('Script', factory3)
      column_view.append_column(column)

      @scroll.set_child(column_view)
      signal_connect('close-request') do |w, e|
        w.hide
      end
      box.show
    end

    def append_data(name, script)
      @model.insert(0, Item.new(Time.now.to_s, name, script))
    end
  end
end
