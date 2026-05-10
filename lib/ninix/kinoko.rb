# -*- coding: utf-8 -*-
#
#  Copyright (C) 2004-2019 by Shyouzou Sugitani <shy@users.osdn.me>
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
require "gtk4"

require_relative "config"
require_relative "seriko"
require_relative "pix"
require_relative "logging"

module Kinoko

  class Menu
  include GetText

  bindtextdomain("ninix-kagari")

    def initialize
      @parent = nil
      @__popover = nil
      @__action_group = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def setup_actions(widget)
      group = Gio::SimpleActionGroup.new

      settings_action = Gio::SimpleAction.new('settings')
      settings_action.signal_connect('activate') do
        @parent.handle_request(:GET, :edit_preferences)
      end
      group.add_action(settings_action)

      exit_action = Gio::SimpleAction.new('exit')
      exit_action.signal_connect('activate') do
        @parent.handle_request(:GET, :close)
      end
      group.add_action(exit_action)

      @__action_group = group
      widget.insert_action_group('skin', group)
    end

    def popup(widget)
      skin_list = @parent.handle_request(:GET, :get_skin_list)

      # Register dynamic skin actions
      skin_list.each_with_index do |skin, i|
        name = "selectskin#{i}"
        existing = @__action_group.lookup_action(name) rescue nil
        @__action_group.remove_action(name) if existing
        action = Gio::SimpleAction.new(name)
        action.signal_connect('activate') do
          @parent.handle_request(:GET, :select_skin, skin)
        end
        @__action_group.add_action(action)
      end

      menu = Gio::Menu.new
      menu.append(_('Settings...(O)'), 'skin.settings')

      unless skin_list.empty?
        skin_submenu = Gio::Menu.new
        skin_list.each_with_index do |skin, i|
          skin_submenu.append(skin['title'], "skin.selectskin#{i}")
        end
        menu.append_submenu(_('Skin(K)'), skin_submenu)
      end

      menu.append(_('Exit(Q)'), 'skin.exit')

      @__popover&.unparent
      @__popover = Gtk::PopoverMenu.new(menu)
      @__popover.set_parent(widget)
      @__popover.set_has_arrow(false)
      @__popover.popup
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
      @skin.destroy() unless @skin.nil?
    end

    def observer_update(event, args)
      return if @skin.nil?
      case event
      when 'set position', 'set surface'
        @skin.set_position()
        @skin.show()
        @skin.reset_z_order()
      when 'set scale'
        scale = @target.get_surface_scale()
        @skin.set_scale(scale)
      when 'hide'
        side = args[0]
        @skin.hide() if side.zero? # sakura side
      when 'iconified'
        @skin.hide()
      when 'deiconified'
        @skin.show()
        @skin.reset_z_order()
      when 'finalize'
        finalize()
      when 'move surface'
        side, xoffset, yoffset = args
        @skin.set_position(:xoffset => xoffset, :yoffset => yoffset) if side.zero? # sakura side
        @skin.reset_z_order()
      when 'raise'
        side = args[0]
        @skin.set_position() if side.zero? # sakura side
        @skin.reset_z_order()
      else
        Logging::Logging.debug('OBSERVER(kinoko): ignore - ' + event)
      end
    end

    def load_skin()
      scale = @target.get_surface_scale()
      @skin = Skin.new()
      @skin.set_responsible(self)
      @skin.load(@data, scale)
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless [:GET, :NOTIFY].include?(event_type)
      handlers = {
        :get_target_window =>  lambda { return @target.get_target_window }, # XXX
        :get_kinoko_position => lambda {|a| return @target.get_kinoko_position(a) }
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
      return result if event_type == 'GET'
    end

    def load(data, target)
      @data = data
      @target = target
      @target.attach_observer(self)
      load_skin()
      return 0 if @skin.nil?
      send_event('OnKinokoObjectCreate')
      @__running = true
      GLib::Timeout.add(10) { do_idle_tasks } # 10[ms]
      return 1
    end

    def do_idle_tasks()
      @__running
    end

    def close()
      finalize()
      send_event('OnKinokoObjectDestroy')
    end

    def send_event(event)
      return unless ['OnKinokoObjectCreate', 'OnKinokoObjectDestroy',
                     'OnKinokoObjectChanging', 'OnKinokoObjectChanged',
                     'OnKinokoObjectInstalled'].include?(event)
      ## 'OnBatteryLow', 'OnBatteryCritical',
      ## 'OnSysResourceLow', 'OnSysResourceCritical'
      args = [@data['title'],
              @data['ghost'],
              @data['category']]
      @target.notify_event(event, *args)
    end

    def get_skin_list()
      @skin_list
    end

    def select_skin(args)
      send_event('OnKinokoObjectChanging')
      @skin.destroy()
      @data = args
      load_skin()
      return 0 if @skin.nil?
      send_event('OnKinokoObjectChanged')
      return 1
    end
  end

  class Skin

    HANDLERS = {
    }

    def initialize()
      @frame_buffer = []
      @parent = nil
      @__menu = Menu.new()
      @__menu.set_responsible(self)
    end

    def get_seriko
      @seriko
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless [:GET, :NOTIFY].include?(event_type)
      if HANDLERS.include?(event)
        result = HANDLERS[event].call # no argument
      else
        if Skin.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = @parent.handle_request(event_type, event, *arglist)
        end
      end
      return result if event_type == 'GET'
    end

    def load(data, scale)
      @data = data
      @__scale = scale
      @__shown = false
      @surface_id = 0 # dummy
      @window = Pix::TransparentWindow.new()
      @window.signal_connect('close-request') do |w|
        delete(w)
        next true
      end
      unless @data['animation'].nil?
        path = File.join(@data['dir'], @data['animation'])
        actors = {'' => Seriko.get_actors(NConfig.create_from_file(path))}
      else
        base = File.basename(@data['base'], ".*")
        ext = File.extname(@data['base'])
        path = File.join(@data['dir'], base + 'a.txt')
        if File.exist?(path)
          actors = {'' =>  Seriko.get_actors(NConfig.create_from_file(path))}
        else
          actors = {'' =>  []}
        end
      end
      @seriko = Seriko::Controller.new(actors)
      @seriko.set_responsible(self)
      path = File.join(@data['dir'], @data['base'])
      begin
        @reshape = true
        @image_surface = Pix.create_surface_from_file(path)
        w = [8, (@image_surface.width * @__scale / 100).to_i].max
        h = [8, (@image_surface.height * @__scale / 100).to_i].max
      rescue ## FIXME
        @parent.handle_request(:GET, :close)
        return
      end
      @path = path
      @w, @h = w, h
      @darea = @window.darea

      # GTK4: use draw func instead of draw signal
      @darea.set_draw_func do |widget, cr, width, height|
        redraw(widget, cr)
      end

      # GTK4: use gesture controllers instead of event signals
      gesture = Gtk::GestureClick.new
      gesture.set_button(0) # all buttons
      gesture.signal_connect('pressed') do |g, n_press, x, y|
        button_press(g.current_button, n_press, x, y)
      end
      @darea.add_controller(gesture)

      motion = Gtk::EventControllerMotion.new
      motion.signal_connect('leave') do
        leave_notify()
      end
      @darea.add_controller(motion)

      # Set up action group for menu
      @__menu.setup_actions(@darea)

      set_position()
      show()
      reset_z_order()
      @seriko.reset(self, '') # XXX
      @seriko.start(self)
      @seriko.invoke_kinoko(self)
    end

    def get_surface_id
      @surface_id
    end

    def get_preference(name) # dummy
      return 1.0 if name == 'animation_quality'
      return nil
    end

    def show()
      @window.show() unless @__shown
      @__shown = true
    end

    def hide()
      @window.hide() if @__shown
      @__shown = false
    end

    def reset_z_order
      # GTK4: window stacking not available via public API
    end

    def append_actor(frame, actor)
      @seriko.append_actor(frame, actor)
    end

    def set_position(xoffset: 0, yoffset: 0)
      base_x, base_y = @parent.handle_request(:GET, :get_kinoko_position, @data['baseposition'])
      a, b = [[0.5, 1], [0.5, 0], [0, 0.5], [1, 0.5], [0, 1],
              [1, 1], [0, 0], [1, 0], [0.5, 0.5]][@data['baseadjust']]
      offsetx = (@data['offsetx'] * @__scale / 100).to_i
      offsety = (@data['offsety'] * @__scale / 100).to_i
      @x = (base_x - (@w * a).to_i + offsetx + xoffset)
      @y = (base_y - (@h * b).to_i + offsety + yoffset)
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
      @window.set_surface(cr, @image_surface, @__scale, @reshape)
      @window.set_shape(cr, @reshape)
      @reshape = false
    end

    def get_image_surface(surface_id)
      path = File.join(@data['dir'],
                       'surface'+ surface_id.to_s + '.png')
      if File.exist?(path)
        surface = Pix.create_surface_from_file(path)
      else
        surface = nil
      end
      return surface
    end

    def create_image_surface(surface_id)
      unless surface_id.nil? or surface_id.empty?
        surface = get_image_surface(surface_id)
      else
        surface = Pix.create_surface_from_file(@path)
      end
      return surface
    end

    def update_frame_buffer()
      @reshape = true # FIXME: depends on Seriko
      new_surface = create_image_surface(@seriko.get_base_id)
      raise "assert" if new_surface.nil?
      # draw overlays
      for surface_id, x, y, method in @seriko.iter_overlays()
        begin
          overlay_surface = get_image_surface(surface_id)
        rescue
          next
        end
        # overlay surface
        Cairo::Context.new(new_surface) do |cr|
          cr.set_source(overlay_surface, x, y)
          cr.mask(overlay_surface, x, y)
        end
      end
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

    def reset_surface()
      @seriko.reset(self, '') # XXX
      path = File.join(@data['dir'], @data['base'])
      w, h = Pix.get_png_size(path)
      w = [8, (w * @__scale / 100).to_i].max
      h = [8, (h * @__scale / 100).to_i].max
      @w, @h = w, h # XXX
      @seriko.start(self)
      @seriko.invoke_kinoko(self)
    end

    def set_surface(surface_id, restart: 1)
      path = File.join(@data['dir'], 'surface' + surface_id.to_s + '.png')
      if File.exist?(path)
        @path = path
      else
        @path = File.join(@data['dir'], @data['base'])
      end
    end

    def invoke(actor_id, update: 0)
      @seriko.invoke(self, actor_id, :update => update)
    end

    def delete(widget = nil)
      @parent.handle_request(:GET, :close)
    end

    def destroy()
      @seriko.destroy()
      @window.destroy()
    end

    def button_press(button, n_press, x, y)
      if button == 3 && n_press == 1
        @__menu.popup(@darea)
      end
      true
    end
  end
end
