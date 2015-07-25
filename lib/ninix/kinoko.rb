# -*- coding: utf-8 -*-
#
#  Copyright (C) 2004-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# - きのことサーフェスの間に他のウインドウが入ることができてしまうのを直す.
# - NAYUKI/2.0
# - 透明度の設定

require 'gettext'
require "gtk3"

require_relative "config"
require_relative "seriko"
require_relative "pix"
require_relative "logging"

module Kinoko

  class Menu
  include GetText

  bindtextdomain("ninix-aya")

    def initialize(accelgroup)
      @parent = nil
      ui_info = <<-EOS
        <ui>
          <popup name='popup'>
            <menuitem action='Settings'/>
            <menu action='Skin'>
            </menu>
            <separator/>
            <menuitem action='Exit'/>
          </popup>
        </ui>
      EOS
      @__menu_list = {
        'settings' => [['Settings', nil, _('Settings...(_O)'), nil,
                        '', lambda {|a, b| @parent.handle_request('NOTIFY', 'edit_preferences')}],
                       '/ui/popup/Settings'],
        'skin' => [['Skin', nil, _('Skin(_K)'), nil],
                   nil, '/ui/popup/Skin'],
        'exit' => [['Exit', nil, _('Exit(_Q)'), nil,
                    '', lambda {|a, b| @parent.handle_request('NOTIFY', 'close')}],
                   '/ui/popup/Exit'],
      }
      actions = Gtk::ActionGroup.new('Actions')
      entry = []
      for value in @__menu_list.values()
        entry << value[0]
      end
      actions.add_actions(entry)
      ui_manager = Gtk::UIManager.new()
      ui_manager.insert_action_group(actions, 0)
      ui_manager.add_ui(ui_info)
      @__popup_menu = ui_manager.get_widget('/ui/popup')
      for key in @__menu_list.keys
        path = @__menu_list[key][-1]
        @__menu_list[key][1] = ui_manager.get_widget(path)
      end
    end

    def set_responsible(parent)
      @parent = parent
    end

    def popup(button)
      skin_list = @parent.handle_request('GET', 'get_skin_list')
      set_skin_menu(skin_list)
      @__popup_menu.popup(nil, nil, button, Gtk.current_event_time())
    end

    def set_skin_menu(list) ## FIXME
      key = 'skin'
      if not list.empty?
        menu = Gtk::Menu.new
        for skin in list
          item = Gtk::MenuItem.new(skin['title'])
          item.signal_connect('activate', skin) do |a, k|
            @parent.handle_request('NOTIFY', 'select_skin', k)
          end
          menu.add(item)
          item.show()
        end
        @__menu_list[key][1].set_submenu(menu)
        menu.show()
        @__menu_list[key][1].show()
      else
        @__menu_list[key][1].hide()
      end
    end
  end

  class Nayuki

    def initialize()
    end
  end

  class Kinoko

    def initialize(skin_list)
      @skin_list = skin_list
      @skin = nil
    end

    def edit_preferences()
    end

    def finalize()
      @__running = false
      @target.detach_observer(self)
      if @skin != nil
        @skin.destroy()
      end
    end

    def observer_update(event, args)
      if @skin == nil
        return
      end
      if ['set position', 'set surface'].include?(event)
        @skin.set_position()
        @skin.show()
      elsif event == 'set scale'
        scale = @target.get_surface_scale()
        @skin.set_scale(scale)
      elsif event == 'hide'
        side = args
        if side == 0 # sakura side
          @skin.hide()
        end
      elsif event == 'iconified'
        @skin.hide()
      elsif event == 'deiconified'
        @skin.show()
      elsif event == 'finalize'
        finalize()
      elsif event == 'move surface'
        side, xoffset, yoffset = args
        if side == 0 # sakura side
          @skin.set_position(:xoffset => xoffset, :yoffset => yoffset)
        end
      elsif event == 'raise'
        side = args
        if side == 0 # sakura side
          @skin.set_position() ## FIXME
        end
      else
        Logging::Logging.debug('OBSERVER(kinoko): ignore - ' + event)
      end
    end

    def load_skin()
      scale = @target.get_surface_scale()
      @skin = Skin.new(@accelgroup)
      @skin.set_responsible(self)
      @skin.load(@data, scale)
    end

    def handle_request(event_type, event, *arglist)
      #assert ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
        'get_target_window' =>  lambda { return @target.get_target_window }, # XXX
        'get_kinoko_position' => lambda {|a| return @target.get_kinoko_position(a) }
      }
      if handlers.include?(event)
        result = handlers[event].call(*arglist)
      else
        if Kinoko.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = nil
        end
      end
      if event_type == 'GET'
        return result
      end
    end

    def load(data, target)
      @data = data
      @target = target
      @target.attach_observer(self)
      @accelgroup = Gtk::AccelGroup.new()
      load_skin()
      if @skin == nil
        return 0
      else
        send_event('OnKinokoObjectCreate')
      end
      @__running = true
      GLib::Timeout.add(10) { do_idle_tasks } # 10[ms]
      return 1
    end

    def do_idle_tasks()
      if @__running
        return true
      else
        return false
      end
    end

    def close()
      finalize()
      send_event('OnKinokoObjectDestroy')
    end

    def send_event(event)
      if not ['OnKinokoObjectCreate', 'OnKinokoObjectDestroy',
              'OnKinokoObjectChanging', 'OnKinokoObjectChanged',
              'OnKinokoObjectInstalled'].include?(event)
        ## 'OnBatteryLow', 'OnBatteryCritical',
        ## 'OnSysResourceLow', 'OnSysResourceCritical'
        return
      end
      args = [@data['title'],
              @data['ghost'],
              @data['category']]
      @target.notify_event(event, *args)
    end

    def get_skin_list()
      return @skin_list
    end

    def select_skin(args)
      send_event('OnKinokoObjectChanging')
      @skin.destroy()
      @data = args
      load_skin()
      if @skin == nil
        return 0
      else
        send_event('OnKinokoObjectChanged')
      end
      return 1
    end
  end

  class Skin

    def initialize(accelgroup)
      @frame_buffer = []
      @accelgroup = accelgroup
      @parent = nil
      @__menu = Menu.new(@accelgroup)
      @__menu.set_responsible(self)
    end

    def get_seriko
      return @seriko
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      #assert ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
      }
      if handlers.include?(event)
        result = handlers[event].call # no argument
      else
        if Skin.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = @parent.handle_request(event_type, event, *arglist)
        end
      end
      if event_type == 'GET'
        return result
      end
    end

    def load(data, scale)
      @data = data
      @__scale = scale
      @__shown = false
      @surface_id = 0 # dummy
      @window = Pix::TransparentWindow.new()
      ##@window.set_title(['surface.', name].join(''))
      @window.set_skip_taskbar_hint(true)
      @window.signal_connect('delete_event') do |w, e|
        delete(w, e)
      end
      @window.add_accel_group(@accelgroup) ## FIXME
      if @data['animation'] != nil
        path = File.join(@data['dir'], @data['animation'])
        actors = {'' => Seriko.get_actors(NConfig.create_from_file(path))}
      else
        base = File.basename(@data['base'], ".*")
        ext = File.extname(@data['base'])
        path = File.join(@data['dir'], base + 'a.txt')
        if File.exists?(path)
          actors = {'' =>  Seriko.get_actors(NConfig.create_from_file(path))}
        else
          actors = {'' =>  []}
        end
      end
      @seriko = Seriko::Controller.new(actors)
      @seriko.set_responsible(self) ## FIXME
      path = File.join(@data['dir'], @data['base'])
      begin
        @image_surface = Pix.create_surface_from_file(path)
        w = [8, (@image_surface.width * @__scale / 100).to_i].max
        h = [8, (@image_surface.height * @__scale / 100).to_i].max
      rescue ## FIXME
        @parent.handle_request('NOTIFY', 'close')
        return
      end
      @path = path
      @w, @h = w, h
      @darea = @window.darea
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK|
                        Gdk::EventMask::BUTTON_PRESS_MASK|
                        Gdk::EventMask::BUTTON_RELEASE_MASK|
                        Gdk::EventMask::POINTER_MOTION_MASK|
                        Gdk::EventMask::LEAVE_NOTIFY_MASK)
      @darea.signal_connect('button_press_event') do |w, e|
        button_press(w, e)
      end
      @darea.signal_connect('button_release_event') do |w, e|
        button_release(w, e)
      end
      @darea.signal_connect('motion_notify_event') do |w, e|
          motion_notify(w, e)
      end
      @darea.signal_connect('leave_notify_event') do |w, e|
        leave_notify(w, e)
      end
      @darea.signal_connect('draw') do |w, cr|
        redraw(w, cr)
      end
      @window.update_size(@w, @h)
      set_position()
      target_window = @parent.handle_request('GET', 'get_target_window')
      if @data['ontop']
        @window.set_transient_for(target_window)
      else
        target_window.set_transient_for(@window)
      end
      show()
      @seriko.reset(self, '') # XXX
      @seriko.start(self)
      @seriko.invoke_kinoko(self)
    end

    def get_surface_id ## FIXME
      return @surface_id
    end

    def get_preference(name) # dummy
      if name == 'animation_quality'
        return 1.0
      else
        return nil
      end
    end

    def show()
      if not @__shown
        @window.show_all()
        @__shown = true
      end
    end

    def hide()
      if @__shown
        @window.hide_all()
        @__shown = false
      end
    end

    def append_actor(frame, actor)
      @seriko.append_actor(frame, actor)
    end

    def set_position(xoffset: 0, yoffset: 0)
      base_x, base_y = @parent.handle_request('GET', 'get_kinoko_position', @data['baseposition'])
      a, b = [[0.5, 1], [0.5, 0], [0, 0.5], [1, 0.5], [0, 1],
              [1, 1], [0, 0], [1, 0], [0.5, 0.5]][@data['baseadjust']]
      offsetx = (@data['offsetx'] * @__scale / 100).to_i
      offsety = (@data['offsety'] * @__scale / 100).to_i
      @x = base_x - (@w * a).to_i + offsetx + xoffset
      @y = base_y - (@h * b).to_i + offsety + yoffset
      @window.move(@x, @y)
    end

    def set_scale(scale)
      @__scale = scale
      reset_surface()
      set_position()
    end

    def get_surface() ## FIXME
      return nil
    end

    def redraw(widget, cr)
      @window.set_surface(cr, @image_surface, @__scale)
      @window.set_shape(cr)
    end

    def get_image_surface(surface_id)
      path = File.join(@data['dir'],
                       'surface'+ surface_id.to_s + '.png')
      if File.exists?(path)
        surface = Pix.create_surface_from_file(path)
      else
        surface = nil
      end
      return surface
    end

    def create_image_surface(surface_id)
      if surface_id != nil and surface_id != ''
        surface = get_image_surface(surface_id)
      else
        surface = Pix.create_surface_from_file(@path)
      end
      return surface
    end

    def update_frame_buffer()
      new_surface = create_image_surface(@seriko.get_base_id)
      #assert new_surface != nil
      # draw overlays
      for surface_id, x, y, method in @seriko.iter_overlays()
        begin
          overlay_surface = get_image_surface(surface_id)
        rescue
          next
        end
        # overlay surface
        cr = Cairo::Context.new(new_surface)
        cr.set_source(overlay_surface, x, y)
        cr.mask(overlay_surface, x, y)
      end
      #@darea.queue_draw_area(0, 0, w, h)
      @image_surface = new_surface
      @darea.queue_draw()
    end

    def terminate()
      @seriko.terminate(self)
    end

    def add_overlay(actor, surface_id, x, y, method)
      @seriko.add_overlay(self, actor, surface_id, x, y, method)
    end

    def remove_overlay(actor)
      @seriko.remove_overlay(actor)
    end

    def move_surface(xoffset, yoffset)
      @window.move(@x + xoffset, @y + yoffset)
    end

    def reset_surface() ## FIXME
      @seriko.reset(self, '') # XXX
      path = File.join(@data['dir'], @data['base'])
      w, h = Pix.get_png_size(path)
      w = [8, (w * @__scale / 100).to_i].max
      h = [8, (h * @__scale / 100).to_i].max
      @w, @h = w, h # XXX
      @window.update_size(w, h)
      @window.queue_resize()
      @seriko.start(self)
      @seriko.invoke_kinoko(self)
    end

    def set_surface(surface_id, restart: 1) ## FIXME
      path = File.join(@data['dir'], 'surface' + surface_id.to_s + '.png')
      if File.exists?(path)
        @path = path
      else
        #path = nil
        @path = File.join(@data['dir'], @data['base'])
      end
    end

    def invoke(actor_id, update: 0)
      @seriko.invoke(self, actor_id, :update => update)
    end

    def delete()
      @parent.handle_request('NOTIFY', 'close')
    end

    def destroy()
      @seriko.destroy()
      @window.destroy()
    end

    def button_press(widget, event) ## FIXME
      @x_root = event.x_root
      @y_root = event.y_root
      if event.event_type == Gdk::EventType::BUTTON_PRESS
        click = 1
      else
        click = 2
      end
      button = event.button
      if button == 3 and click == 1
        @__menu.popup(button)
      end
      return true
    end

    def button_release(widget, event) ## FIXME
    end

    def motion_notify(widget, event) ## FIXME
    end

    def leave_notify(widget, event) ## FIXME
    end
  end
end
