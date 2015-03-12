# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2004-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#  Copyright (C) 2003-2005 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'gettext'
require "gtk3"

require "ninix/home"

module Prefs

  RANGE_SCALE = [100, 90, 80, 70, 60, 50, 40, 30, 200, 300, 1000]
  RANGE_SCRIPT_SPEED = [-1, 0, 1, 2, 3, 4, 5, 6, 8] # -1: no wait

  # default settings
  DEFAULT_BALLOON_FONTS = 'Sans'

  def self.get_default_surface_scale()
    return RANGE_SCALE[0]
  end

  def self.get_default_script_speed()
    return RANGE_SCRIPT_SPEED[RANGE_SCRIPT_SPEED.length / 2]
  end

  class Preferences

    include GetText

    bindtextdomain("ninix-aya")

    def initialize(filename)
      @dic = {}
      @filename = filename
      @__stack = {}
    end

    def get(name, default)
      if @dic.include?(name)
        return @dic[name]
      else
        return default
      end
    end

    def include?(name)
      if @dic.include?(key) or @__stack.include?(key)
        return true
      else
        return false
      end
    end

    def set(key, item)
      if @dic.include?(key) and not @__stack.include?(key)
        @__stack[key] = @dic[key]
      end
    end

    def commit
      @__stack = {}
    end

    def revert
      update(@__stack)
      @__stack = {}
    end

    def update(stack)
      for key in stack
        @dic[key] = stack[key]
      end
    end

    def load
      @dic = {}
      begin
        f = open(@filename)
        while(line = f.gets)
          prefs = line.chomp.split(': ')
          key = prefs[0]
          value = prefs[1]
          @dic[key] = value
        end
      rescue #except IOError:
        return
      end
    end

    def save
      begin
        Dir.mkdir(File.dirname(@filename), 0755)
      rescue #except OSError:
        #pass
      end
      f = open(@filename, 'w')
      keys = @dic.keys.sort
      for key in keys
        if @__stack.include?(key)
          value = @__stack[key]
        else
          value = @dic[key]
        end
        f.write([key, ": ", value, "\n"].join(''))
      end
    end
  end

  class PreferenceDialog

    include GetText

    bindtextdomain("ninix-aya")

    def initialize
      @parent = nil
      @dialog = Gtk::Dialog.new()
      @dialog.signal_connect('delete_event') do |i, *a|
        return true
      end
      @dialog.set_title('Preferences')
      @dialog.set_default_size(-1, 600)
      @notebook = Gtk::Notebook.new()
      @notebook.set_tab_pos(Gtk::PositionType::TOP)
      content_area = @dialog.content_area
      content_area.add(@notebook)
      @notebook.show()
      @notebook.append_page(make_page_surface_n_balloon(),
                            Gtk::Label.new(_('Surface&Balloon')))
      @notebook.append_page(make_page_misc(),
                            Gtk::Label.new(_('Misc')))
      @notebook.append_page(make_page_debug(),
                            Gtk::Label.new(_('Debug')))
      @dialog.add_button(Gtk::Stock::OK, Gtk::ResponseType::OK)
      @dialog.add_button(Gtk::Stock::APPLY, Gtk::ResponseType::APPLY)
      @dialog.add_button(Gtk::Stock::CANCEL, Gtk::ResponseType::CANCEL)
      @dialog.signal_connect('response') do |i, *a|
        response(i, *a)
      end
    end

    def set_responsible(parent)
      @parent = parent
    end

    def load
      filename = Home.get_preferences()
      @__prefs = Preferences.new(filename)
      @__prefs.load()
      reset()
      update() # XXX
      @parent.handle_request('NOTIFY', 'notify_preference_changed')
    end

    def save
      @__prefs.save
    end

    def reset ### FIXME ###
      @fontchooser.set_font_name(get('balloon_fonts', DEFAULT_BALLOON_FONTS))
      set_default_balloon(get('default_balloon'))
      @ignore_button.set_active(
                                !!get('ignore_default', 0))
      scale = get('surface_scale', Prefs.get_default_surface_scale())
      if not RANGE_SCALE.include?(scale)
        @surface_scale_combo.set_active(RANGE_SCALE.index(Prefs.get_default_surface_scale()))
      else
        @surface_scale_combo.set_active(RANGE_SCALE.index(scale))
      end
      script_speed = get('script_speed', Prefs.get_default_script_speed())
      if not RANGE_SCRIPT_SPEED.include?(script_speed)
        @script_speed_combo.set_active(
                                       RANGE_SCRIPT_SPEED.index(Prefs.get_default_script_speed()))
      else
        @script_speed_combo.set_active(RANGE_SCRIPT_SPEED.index(script_speed))
      end
      @balloon_scaling_button.set_active(!!get('balloon_scaling'))
      @allowembryo_button.set_active(!!get('allowembryo'))
      @check_collision_button.set_active(!!get('check_collision', 0))
      @check_collision_name_button.set_active(!!get('check_collision_name', 0))
      @use_pna_button.set_active(!!get('use_pna', 1))
      @sink_after_talk_button.set_active(!!get('sink_after_talk'))
      @raise_before_talk_button.set_active(!!get('raise_before_talk'))
      @animation_quality_adjustment.set_value(get('animation_quality', 1.0))
    end

    def get(name, default=nil)
      #assert name in self.PREFS_TYPE
      if ['sakura_name', # XXX: backward compat
          'sakura_dir', 'default_balloon', 'balloon_fonts'].include?(name)
        value = @__prefs.get(name, default)
      elsif ['ignore_default', 'script_speed', 'surface_scale',
             'balloon_scaling', 'allowembryo', 'check_collision',
             'check_collision_name', 'use_pna', 'sink_after_talk',
             'raise_before_talk'].include?(name)
        value = @__prefs.get(name, default).to_i
      elsif ['animation_quality'].include?(name)
        value = @__prefs.get(name, default).to_f
      else # should not reach here
        value = @__prefs.get(name, default)
      end
      return value
    end

    def set_current_sakura(directory)
      key = 'sakura_name' # obsolete
      if @__prefs.include?(key)
        del @__prefs[key]
      end
      key = 'sakura_dir'
      if @__prefs.include?(key)
        del @__prefs[key]
      end
      @__prefs[key] = directory
    end

    def edit_preferences
      show()
    end

    def update(commit=false) ## FIXME
      @__prefs.set('allowembryo', (@allowembryo_button.active? ? 1 : 0).to_s)
      @__prefs.set('balloon_fonts', @fontchooser.font_name)
      selected = @balloon_treeview.selection.selected
      if selected
        model, listiter = selected
        directory = model.get_value(listiter, 1)
        @__prefs.set('default_balloon', directory)
      end
      @__prefs.set('ignore_default', (@ignore_button.active? ? 1 : 0).to_s)
      @__prefs.set('surface_scale', RANGE_SCALE[@surface_scale_combo.active].to_i.to_s)
      @__prefs.set('script_speed', RANGE_SCRIPT_SPEED[@script_speed_combo.active].to_i.to_s)
      @__prefs.set('balloon_scaling', (@balloon_scaling_button.active? ? 1 : 0).to_s)
      @__prefs.set('check_collision', (@check_collision_button.active? ? 1 : 0).to_s)
      @__prefs.set('check_collision_name', (@check_collision_name_button.active? ? 1 : 0).to_s)
      @__prefs.set('use_pna', (@use_pna_button.active? ? 1 : 0).to_s)
      @__prefs.set('sink_after_talk', (@sink_after_talk_button.active? ? 1: 0).to_s)
      @__prefs.set('raise_before_talk', (@raise_before_talk_button.active? ? 1 : 0).to_s)
      @__prefs.set('animation_quality', @animation_quality_adjustment.value.to_f.to_s)
      if commit
        @__prefs.commit()
      end
    end

    def ok
      hide()
      update(commit=true)
      @parent.handle_request('NOTIFY', 'notify_preference_changed')
    end

    def apply
      update()
      @parent.handle_request('NOTIFY', 'notify_preference_changed')
    end

    def cancel
      hide()
      @__prefs.revert()
      reset()
      @parent.handle_request('NOTIFY', 'notify_preference_changed')
    end

    def show
      @dialog.show()
    end

    def response(widget, response)
      if response == Gtk::ResponseType::OK
        ok()
      elsif response == Gtk::ResponseType::CANCEL
        cancel()
      elsif response == Gtk::ResponseType::APPLY
        apply
      elsif response == Gtk::ResponseType::DELETE_EVENT
        cancel()
      else # should not reach here
        # pass
      end
      return true
    end

    def hide
      @dialog.hide()
    end

    def make_page_surface_n_balloon
      page = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      page.set_border_width(5)
      page.show()
      frame = Gtk::Frame.new(label=_('Surface Scaling'))
      page.pack_start(frame, false, true, 0)
      frame.show()
      box = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      box.set_border_width(5)
      frame.add(box)
      box.show()
      hbox = Gtk::Box.new(orientation=Gtk::Orientation::HORIZONTAL, spacing=5)
      box.pack_start(hbox, false, true, 0)
      hbox.show()
      label = Gtk::Label.new(label=_('Default Setting'))
      hbox.pack_start(label, false, true, 0)
      label.show()
      @surface_scale_combo = Gtk::ComboBoxText.new()
      for value in RANGE_SCALE
        @surface_scale_combo.append_text(sprintf("%4d", value))
      end
      hbox.pack_start(@surface_scale_combo, false, true ,0)
      @surface_scale_combo.show()
      button = Gtk::CheckButton.new(_('Scale Balloon'))
      @balloon_scaling_button = button
      box.pack_start(button, false, true, 0)
      button.show()
      frame = Gtk::Frame.new(label=_('Default Balloon'))
      page.pack_start(frame, true, true, 0)
      frame.show()
      box = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      box.set_border_width(5)
      frame.add(box)
      box.show()
      scrolled = Gtk::ScrolledWindow.new()
      scrolled.set_vexpand(true)
      scrolled.set_policy(Gtk::PolicyType::NEVER, Gtk::PolicyType::ALWAYS)
      scrolled.set_shadow_type(Gtk::ShadowType::ETCHED_IN)
      box.pack_start(scrolled, true, true, 0)
      scrolled.show()
      treeview = Gtk::TreeView.new(nil)
      column = Gtk::TreeViewColumn.new(_('Balloon Name'),
                                       Gtk::CellRendererText.new())#, text=0)
      treeview.append_column(column)
      treeview.selection.set_mode(Gtk::SelectionMode::SINGLE)
      @balloon_treeview = treeview
      scrolled.add(treeview)
      treeview.show()
      button = Gtk::CheckButton.new(_('Always Use This Balloon'))
      @ignore_button = button
      box.pack_start(button, false, true, 0)
      button.show()
      frame = Gtk::Frame.new(label=_('Font(s) for balloons'))
      page.pack_start(frame, false, true, 0)
      frame.show()
      box = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      box.set_border_width(5)
      frame.add(box)
      box.show()
      @fontchooser = Gtk::FontButton.new()
      @fontchooser.set_show_size(false)        
      box.add(@fontchooser)
      @fontchooser.show()
      frame = Gtk::Frame.new(label=_('Translucency'))
      page.pack_start(frame, false, true, 0)
      frame.show()
      box = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      box.set_border_width(5)
      frame.add(box)
      box.show()
      button = Gtk::CheckButton.new(_('Use PNA file'))
      @use_pna_button = button
      box.pack_start(button, false, true, 0)
      button.show()
      frame = Gtk::Frame.new(label=_('Animation'))
      page.pack_start(frame, false, true,0 )
      frame.show()
      box = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      box.set_border_width(5)
      frame.add(box)
      box.show()
      hbox = Gtk::Box.new(orientation=Gtk::Orientation::HORIZONTAL, spacing=5)
      box.add(hbox)
      hbox.show()
      label = Gtk::Label.new(label=_('Quality'))
      hbox.pack_start(label, false, true, 0)
      label.show()
      @animation_quality_adjustment = Gtk::Adjustment.new(1.0, 0.4, 1.0, 0.1, 0.1, 0)
      button = Gtk::SpinButton.new(adjustment=@animation_quality_adjustment,
                                   climb_rate=0.2, digits=1)
      hbox.pack_start(button, false, true, 0)
      button.show()
      hbox.show()
      return page
    end

    def make_page_misc
      page = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      page.set_border_width(5)
      page.show()
      frame = Gtk::Frame.new(label=_('SSTP Setting'))
      page.pack_start(frame, false, true, 0)
      frame.show()
      button = Gtk::CheckButton.new(_('Allowembryo'))
      @allowembryo_button = button
      frame.add(button)
      button.show()
      frame = Gtk::Frame.new(label=_('Script Wait'))
      page.pack_start(frame, false, true, 0)
      frame.show()
      hbox = Gtk::Box.new(orientation=Gtk::Orientation::HORIZONTAL, spacing=5)
      frame.add(hbox)
      hbox.show()
      label = Gtk::Label.new(label=_('Default Setting'))
      hbox.pack_start(label, false, true, 0)
      label.show()
      @script_speed_combo = Gtk::ComboBoxText.new()
      for index in 0..(RANGE_SCRIPT_SPEED.length - 1)
        if index == 0
          label = _('None')
        elsif index == 1
          label = ['1 (', _('Fast'), ')'].join('')
        elsif index == RANGE_SCRIPT_SPEED.length - 1
          label = [index.to_s, ' (', _('Slow'), ')'].join('')
        else
          label = index.to_s
        end
        @script_speed_combo.append_text(label)
      end
      hbox.pack_start(@script_speed_combo, false, true, 0)
      @script_speed_combo.show()
      frame = Gtk::Frame.new(label=_('Raise & Lower'))
      page.pack_start(frame, false, true, 0)
      frame.show()
      box = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      box.set_border_width(5)
      frame.add(box)
      box.show()
      button = Gtk::CheckButton.new(_('Sink after Talk'))
      @sink_after_talk_button = button
      box.pack_start(button, false, true, 0)
      button.show()
      button = Gtk::CheckButton.new(_('Raise before Talk'))
      @raise_before_talk_button = button
      box.pack_start(button, false, true, 0)
      button.show()
      return page
    end

    def make_page_debug
      page = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      page.set_border_width(5)
      page.show()
      frame = Gtk::Frame.new(label=_('Surface Debugging'))
      page.pack_start(frame, false, true, 0)
      frame.show()
      box = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL, spacing=5)
      box.set_border_width(5)
      frame.add(box)
      box.show()
      button = Gtk::CheckButton.new(_('Display Collision Area'))
      @check_collision_button = button
      box.pack_start(button, false, true, 0)
      button.show()
      button = Gtk::CheckButton.new(_('Display Collision Area Name'))
      @check_collision_name_button = button
      box.pack_start(button, false, true, 0)
      button.show()
      return page
    end

    def set_default_balloon(directory)
      model = Gtk::ListStore.new(String, String)
      for name, directory in @parent.handle_request('GET', 'get_balloon_list')
        listiter = model.append()
        model.set_value(listiter, 0, name)
        model.set_value(listiter, 1, directory)
      end
      @balloon_treeview.set_model(model)
      listiter = model.iter_first
      selected = false
      while listiter != nil
        value = model.get_value(listiter, 1)
        if value == directory or directory == nil
          @balloon_treeview.get_selection().select_iter(listiter)
          selected = true
          break
        end
        listiter = model.iter_next(listiter) 
      end
      if not selected
        listiter = model.iter_first
        #assert listiter != nil
        @balloon_treeview.selection.select_iter(listiter)
      end
    end
  end

  class TEST

    def initialize
      @dialog = PreferenceDialog.new()
      @dialog.set_responsible(self)
      @dialog.load()
      @dialog.show()
#      @dialog.save()
      Gtk.main
    end

    def handle_request(type, event, *a) # dummy
      return []
    end
  end
end

Prefs::TEST.new