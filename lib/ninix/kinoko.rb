# -*- coding: utf-8 -*-
#
#  Copyright (C) 2004-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
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

require "ninix/config"
require "ninix/seriko"
require "ninix/pix"

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
                        '', lambda {|a, b| return @parent.handle_request('NOTIFY', 'edit_preferences')}],
                       '/ui/popup/Settings'],
        'skin' => [['Skin', nil, _('Skin(_K)'), nil],
                   nil, '/ui/popup/Skin'],
        'exit' => [['Exit', nil, _('Exit(_Q)'), nil,
                    '', lambda {|a, b| return @parent.handle_request('NOTIFY', 'close')}],
                   '/ui/popup/Exit'],
      }
      @__skin_list = nil
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
      if list
        menu = Gtk.Menu()
        for skin in list
          item = Gtk.MenuItem(skin['title'])
          item.signal_connect(
                       'activate',
                       lambda {|a, k| return @parent.handle_request('NOTIFY', 'select_skin', k)},
                       [skin])
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
      self.target.detach_observer(self)
      if self.skin != nil
        self.skin.destroy()
      end
    end

    def observer_update(event, args)
      if self.skin == nil
        return
      end
      if ['set position', 'set surface'].include?(event)
        self.skin.set_position()
        self.skin.show()
      elsif event == 'set scale'
        scale = self.target.get_surface_scale()
        self.skin.set_scale(scale)
      elsif event == 'hide'
        side = args
        if side == 0 # sakura side
          self.skin.hide()
        end
      elsif event == 'iconified'
        self.skin.hide()
      elsif event == 'deiconified'
        self.skin.show()
      elsif event == 'finalize'
        self.finalize()
      elsif event == 'move surface'
        side, xoffset, yoffset = args
        if side == 0 # sakura side
          self.skin.set_position(xoffset, yoffset)
        end
      elsif event == 'raise'
        side = args
        if side == 0 # sakura side
          self.skin.set_position() ## FIXME
        end
      else
        ##logging.debug('OBSERVER(kinoko): ignore - {0}'.format(event))
      end
    end

    def load_skin()
      scale = @target.get_surface_scale()
      @skin = Skin.new(@accelgroup)
      @skin.set_responsible(@target)
      @skin.load(@data, scale)
      print("SKIN: ", @skin, "\n")
    end

    def handle_request(event_type, event, *arglist, **argdict)
      #assert ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
        'get_target_window' =>  lambda {|a| return self.target.surface.window[0].window}, # XXX
        'get_kinoko_position' => self.target.get_kinoko_position,
      }
      handler = handlers.get(event,
                             getattr(self, event,
                                     lambda {|a| return nil})) ## FIXME
      result = handler(*arglist, **argdict)
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
        self.send_event('OnKinokoObjectCreate')
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
      self.finalize()
      self.send_event('OnKinokoObjectDestroy')
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
      self.send_event('OnKinokoObjectChanging')
      self.skin.destroy()
      self.data = args
      self.load_skin()
      if self.skin == nil
        return 0
      else
        self.send_event('OnKinokoObjectChanged')
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

    def handle_request(event_type, event, *arglist, **argdict)
      #assert ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
      }
#      handler = handlers.get(event, getattr(self, event, nil))
#      if handler == nil
      if not handlers.include?(event)
        result = @parent.handle_request(event_type, event, *arglist, **argdict)
      else
#        result = handler(*arglist, **argdict)
        ## FIXME
        result = class_eval(event) #( *arglist, **argdict)
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
      ##self.window.set_title(''.join(('surface.', name)))
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
      print("ACTORS: ", actors, "\n")
      @seriko = Seriko::Controler.new(actors)
      @seriko.set_responsible(self) ## FIXME
      path = File.join(@data['dir'], @data['base'])
      print("PATH: ", path, "\n")
      begin
        @image_surface = Pix.create_surface_from_file(path)
        w = [8, (@image_surface.width * @__scale / 100).to_i].max
        h = [8, (@image_surface.height * @__scale / 100).to_i].max
      rescue #except: ## FIXME
        @parent.handle_request('NOTIFY', 'close')
        return
      end
      print("SURFACE: ", w, " , ", h, "\n")
      @path = path
      @w, @h = w, h
      @darea = @window.darea # @window.get_child()
      @darea.set_events(Gdk::Event::EXPOSURE_MASK|
                        Gdk::Event::BUTTON_PRESS_MASK|
                        Gdk::Event::BUTTON_RELEASE_MASK|
                        Gdk::Event::POINTER_MOTION_MASK|
                        Gdk::Event::LEAVE_NOTIFY_MASK)
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

    def set_position(xoffset=0, yoffset=0)
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
      scale = @__scale
      cr.scale(scale / 100.0, scale / 100.0)
      cr.set_source(@image_surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint()
      print("REDRAW: ", cr, "\n")
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
      print("UPDATE FRAME: ", @seriko.get_base_id, "\n")
      new_surface = create_image_surface(@seriko.get_base_id)
      #assert new_surface != nil
      # draw overlays
      for surface_id, x, y, method in @seriko.iter_overlays()
        print("OVERLAY: ", surface_id, x, y, method, "\n")
        if 1#begin
          overlay_surface = get_image_surface(surface_id)
        else#rescue #except:
          continue
        end
        # overlay surface
        cr = Cairo::Context.new(new_surface)
        cr.set_source(overlay_surface, x, y)
        cr.mask(overlay_surface, x, y)
        #del cr
      end
      #self.darea.queue_draw_area(0, 0, w, h)
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
      w, h = ninix.pix.get_png_size(path)
      w = [8, (w * @__scale / 100).to_i].max
      h = [8, (h * @__scale / 100).to_i].max
      @w, @h = w, h # XXX
      @window.update_size(w, h)
      @window.queue_resize()
      @seriko.start(self)
      @seriko.invoke_kinoko(self)
    end

    def set_surface(surface_id, restart=1) ## FIXME
      path = File.join(@data['dir'], 'surface' + surface_id.to_s + '.png')
      if File.exists?(path)
        @path = path
      else
        #self.path = None
        @path = File.join(@data['dir'], @data['base'])
      end
    end

    def invoke(actor_id, update=0)
      @seriko.invoke(self, actor_id, update)
    end

    def delete() #widget, event)
      @parent.handle_request('NOTIFY', 'close')
    end

    def destroy()
      @seriko.destroy()
      @window.destroy()
    end

    def button_press(widget, event) ## FIXME
      @x_root = event.x_root
      @y_root = event.y_root
      if event.event_type == Gdk::Event::BUTTON_PRESS
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

  class TEST

    def initialize(path)
      @win = Pix::TransparentWindow.new
      @win.signal_connect('destroy') do
        Gtk.main_quit
      end
      @win.darea.signal_connect('draw') do |w, cr|
        expose_cb(w, cr)
      end
      @surface = Pix.create_surface_from_file(path, true, true)
      @win.set_default_size(@surface.width, @surface.height)
      @win.show_all
      require "ninix/home"
      kinoko_list = Home.search_kinoko()
      kinoko = Kinoko.new(kinoko_list)
      print("K: ", kinoko, "\n")
      kinoko.load(kinoko_list.sample, self)
      Gtk.main
    end

    def notify_event(event, *args) # dummy
    end

    def handle_request(type, event, *a) # dummy
      if event == 'get_kinoko_position'
        return 0, 0
      end
    end

    def attach_observer(arg) # dummy
    end

    def get_surface_scale() # dummy
      return 100
    end

    def expose_cb(widget, cr)
      cr.set_source(@surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint
      region = Cairo::Region.new()
      data = @surface.data
      for i in 0..(data.size / 4 - 1)
        if (data[i * 4 + 3].ord) != 0
          x = i % @surface.width
          y = i / @surface.width
          region.union!(x, y, 1, 1)
        end
      end
      @win.input_shape_combine_region(region)
    end
  end
end

$:.unshift(File.dirname(__FILE__))

Kinoko::TEST.new(ARGV.shift)