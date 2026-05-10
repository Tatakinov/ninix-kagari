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

require "gettext"
require "gtk4"

require_relative "pix"
require_relative "home"
require_relative "logging"

module Nekodorif

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
      widget.insert_action_group('neko', group)
    end

    def popup(widget)
      katochan_list = @parent.handle_request(:GET, :get_katochan_list)

      # Register dynamic katochan actions
      katochan_list.each_with_index do |katochan, i|
        name = "selectkatochan#{i}"
        existing = @__action_group.lookup_action(name) rescue nil
        @__action_group.remove_action(name) if existing
        action = Gio::SimpleAction.new(name)
        action.signal_connect('activate') do
          @parent.handle_request(:GET, :select_katochan, katochan)
        end
        @__action_group.add_action(action)
      end

      menu = Gio::Menu.new
      menu.append(_('Settings...(O)'), 'neko.settings')

      unless katochan_list.empty?
        katochan_submenu = Gio::Menu.new
        katochan_list.each_with_index do |katochan, i|
          katochan_submenu.append(katochan['name'], "neko.selectkatochan#{i}")
        end
        menu.append_submenu(_('Katochan(K)'), katochan_submenu)
      end

      menu.append(_('Exit(Q)'), 'neko.exit')

      @__popover&.unparent
      @__popover = Gtk::PopoverMenu.new(menu)
      @__popover.set_parent(widget)
      @__popover.set_has_arrow(false)
      @__popover.popup
    end
  end

  class Nekoninni

    def initialize
      @mode = 1 # 0: SEND SSTP1.1, 1: SHIORI/2.2
      @__running = false
      @skin = nil
      @katochan = nil
    end

    def observer_update(event, args)
      if ['set position', 'set surface'].include?(event)
        @skin.set_position() unless @skin.nil?
        if not @katochan.nil? and @katochan.loaded
          @katochan.set_position()
        end
      elsif event == 'set scale'
        scale = @target.get_surface_scale()
        @skin.set_scale(scale) unless @skin.nil?
        @katochan.set_scale(scale) unless @katochan.nil?
      elsif event == 'finalize'
        finalize()
      else
        Logging::Logging.debug("OBSERVER(nekodorif): ignore - #{event}")
      end
    end

    def load(dir, katochan, target)
      return 0 if katochan.empty?
      @dir = dir
      @target = target
      @target.attach_observer(self)
      scale = @target.get_surface_scale()
      @skin = Skin.new(@dir, scale)
      @skin.set_responsible(self)
      @skin.setup
      return 0 if @skin.nil?
      @katochan_list = katochan
      @katochan = nil
      launch_katochan(@katochan_list[0])
      @__running = true
      GLib::Timeout.add(50) { do_idle_tasks } # 50[ms]
      return 1
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless [:GET, :NOTIFY].include?(event_type)
      handlers = {
        :get_katochan_list =>  lambda { return @katochan_list },
        :get_mode =>  lambda { return @mode },
        :get_workarea => lambda { return @target.get_workarea },
      }
      if handlers.include?(event)
        result = handlers[event].call # no argument
      else
        if Nekoninni.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = nil # XXX
        end
      end
      return result if event_type == 'GET'
    end

    def do_idle_tasks
      return false unless @__running
      @skin.update()
      @katochan.update() unless @katochan.nil?
      return true
    end

    def send_event(event)
      if not ['Emerge', 'Hit', 'Drop', 'Vanish', 'Dodge'].include?(event)
        return
      end
      args = [@katochan.get_name(),
              @katochan.get_ghost_name(),
              @katochan.get_category(),
              @katochan.get_kinoko_flag(),
              @katochan.get_target()]
      @target.notify_event('OnNekodorifObject' + event.to_s, *args)
    end

    def has_katochan
      !@katochan.nil?
    end

    def select_katochan(args)
      launch_katochan(args)
    end

    def drop_katochan
      @katochan.drop()
    end

    def delete_katochan
      @katochan.destroy()
      @katochan = nil
      @skin.reset()
    end

    def launch_katochan(katochan)
      delete_katochan unless @katochan.nil?
      @katochan = Katochan.new(@target)
      @katochan.set_responsible(self)
      @katochan.load(katochan)
    end

    def edit_preferences
    end

    def finalize
      @__running = false
      @target.detach_observer(self)
      @katochan.destroy() unless @katochan.nil?
      @skin.destroy() unless @skin.nil?
    end

    def close
      finalize()
    end
  end

  class Skin
    HANDLERS = {
    }

    def initialize(dir, scale)
      @dir = dir
      @parent = nil
      @dragged = false
      @drag_last_x = nil
      @drag_last_y = nil
      @button1_pressed = false
      @__scale = scale
      @__menu = Menu.new()
      @__menu.set_responsible(self)
      path = File.join(@dir, 'omni.txt')
      if File.file?(path) and File.size(path).zero?
        @omni = 1
      else
        @omni = 0
      end
      @window = Pix::TransparentWindow.new()
      name, top_dir = Home.read_profile_txt(dir) # XXX
      @window.set_title(name)
      @window.signal_connect('close-request') do |w|
        delete(w)
        next true
      end
      @darea = @window.darea

      # GTK4: draw func
      @darea.set_draw_func do |widget, cr, width, height|
        redraw(widget, cr)
      end

      # GTK4: gesture controllers
      gesture = Gtk::GestureClick.new
      gesture.set_button(0)
      gesture.signal_connect('pressed') do |g, n_press, x, y|
        button_press(g.current_button, n_press, x, y)
      end
      gesture.signal_connect('released') do |g, n_press, x, y|
        button_release(g.current_button)
      end
      @darea.add_controller(gesture)

      motion = Gtk::EventControllerMotion.new
      motion.signal_connect('motion') do |c, x, y|
        motion_notify(x, y)
      end
      motion.signal_connect('leave') do
        leave_notify()
      end
      @darea.add_controller(motion)

      # GTK4: key controller on window
      key_controller = Gtk::EventControllerKey.new
      key_controller.signal_connect('key-pressed') do |c, keyval, keycode, state|
        if state & (Gdk::ModifierType::CONTROL_MASK | Gdk::ModifierType::SHIFT_MASK) != 0
          if keyval == Gdk::Keyval::KEY_F12
            Logging::Logging.info('reset skin position')
            set_position(:reset => 1)
          end
        end
        next false
      end
      @window.add_controller(key_controller)

      # Set up action group for menu
      @__menu.setup_actions(@darea)

      @id = [0, nil]
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless [:GET, :NOTIFY].include?(event_type)
      unless HANDLERS.include?(event)
        result = @parent.handle_request(event_type, event, *arglist)
      else
        if Skin.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = nil
        end
      end
      return result if event_type == 'GET'
    end

    def setup
      set_surface()
      set_position(:reset => 1)
      @window.show()
    end

    def set_scale(scale)
      @__scale = scale
      set_surface()
      set_position()
    end

    def redraw(widget, cr)
      @window.set_surface(cr, @image_surface, @__scale, @reshape)
      @window.set_shape(cr, @reshape)
      @reshape = false
    end

    def delete(widget = nil)
      @parent.handle_request(:GET, :finalize)
    end

    def destroy
      @window.destroy()
    end

    def button_press(button, n_press, x, y)
      if button == 1
        if n_press == 1
          @button1_pressed = true
          @drag_last_x = x
          @drag_last_y = y
        elsif n_press == 2
          if @parent.handle_request(:GET, :has_katochan)
            start()
            @parent.handle_request(:GET, :drop_katochan)
          end
        end
      elsif button == 3 && n_press == 1
        @__menu.popup(@darea)
      end
      true
    end

    def set_surface
      unless @id[1].nil?
        path = File.join(@dir, 'surface' + @id[0].to_s + @id[1].to_s + '.png')
        unless File.exist?(path)
          @id[1] = nil
          set_surface()
          return
        end
      else
        path = File.join(@dir, 'surface' + @id[0].to_s + '.png')
      end
      begin
        new_surface = Pix.create_surface_from_file(path)
        w = [8, (new_surface.width * @__scale / 100).to_i].max
        h = [8, (new_surface.height * @__scale / 100).to_i].max
      rescue
        @parent.handle_request(:GET, :finalize)
        return
      end
      @w, @h = w, h
      @reshape = true
      @image_surface = new_surface
      @darea.queue_draw()
    end

    def set_position(reset: 0)
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea)
      unless reset.zero?
        @x = left
        @y = (top + scrn_h - @h)
      else
        @y = (top + scrn_h - @h) unless @omni.zero?
      end
      @window.move(@x, @y)
    end

    def move(x_delta, y_delta)
      @x = (@x + x_delta)
      @y = (@y + y_delta) unless @omni.zero?
      set_position()
    end

    def update
      unless @id[1].nil?
        @id[1] += 1
      else
        return unless Random.rand(0..99).zero? ## XXX
        @id[1] = 0
      end
      set_surface()
    end

    def start
      @id[0] = 1
      set_surface()
    end

    def reset
      @id[0] = 0
      set_surface()
    end

    def button_release(button)
      if button == 1
        @button1_pressed = false
        if @dragged
          @dragged = false
          set_position()
        end
        @drag_last_x = nil
        @drag_last_y = nil
      end
      true
    end

    def motion_notify(x, y)
      if @button1_pressed && !@drag_last_x.nil? && !@drag_last_y.nil?
        x_delta = (x - @drag_last_x).to_i
        y_delta = (y - @drag_last_y).to_i
        @dragged = true
        move(x_delta, y_delta)
        @drag_last_x = x
        @drag_last_y = y
      end
      true
    end

    def leave_notify ## FIXME
    end
  end

  class Balloon

    def initialize
    end

    def destroy ## FIXME
    end
  end

  class Katochan
    attr_reader :loaded

    CATEGORY_LIST = ['pain', 'stab', 'surprise', 'hate', 'huge', 'love',
                     'elegant', 'pretty', 'food', 'reference', 'other']

    def initialize(target)
      @side = 0
      @target = target
      @parent = nil
      @settings = {}
      @settings['state'] = 'before'
      @settings['fall.type'] = 'gravity'
      @settings['fall.speed'] = 1
      @settings['slide.type'] = 'none'
      @settings['slide.magnitude'] = 0
      @settings['slide.sinwave.degspeed'] = 30
      @settings['wave'] = nil
      @settings['wave.loop'] = 0
      @__scale = 100
      @loaded = false
    end

    def set_responsible(parent)
      @parent = parent
    end

    def get_name
      @data['name']
    end

    def get_category
      @data['category']
    end

    def get_kinoko_flag ## FIXME
      return 0
    end

    def get_target
      if @side.zero?
        return @target.get_selfname()
      else
        return @target.get_keroname()
      end
    end

    def get_ghost_name
      if @data.include?('for')
        return @data['for']
      else
        return ''
      end
    end

    def destroy
      @window.destroy()
    end

    def delete(widget = nil)
      destroy()
    end

    def redraw(widget, cr)
      @window.set_surface(cr, @image_surface, @__scale, @reshape)
      @window.set_shape(cr, @reshape)
      @reshape = false
    end

    def set_movement(timing)
      key = (timing + 'fall.type')
      if @data.include?(key) and \
        ['gravity', 'evenspeed', 'none'].include?(@data[key])
          @settings['fall.type'] = @data[key]
      else
        @settings['fall.type'] = 'gravity'
      end
      if @data.include?(timing + 'fall.speed')
        @settings['fall.speed'] = @data[timing + 'fall.speed']
      else
        @settings['fall.speed'] = 1
      end
      if @settings['fall.speed'] < 1
        @settings['fall.speed'] = 1
      end
      if @settings['fall.speed'] > 100
        @settings['fall.speed'] = 100
      end
      key = (timing + 'slide.type')
      if @data.include?(key) and \
        ['none', 'sinwave', 'leaf'].include?(@data[key])
        @settings['slide.type'] = @data[key]
      else
        @settings['slide.type'] = 'none'
      end
      if @data.include?(timing + 'slide.magnitude')
        @settings['slide.magnitude'] = @data[timing + 'slide.magnitude']
      else
        @settings['slide.magnitude'] = 0
      end
      if @data.include?(timing + 'slide.sinwave.degspeed')
        @settings['slide.sinwave.degspeed'] = @data[timing + 'slide.sinwave.degspeed']
      else
        @settings['slide.sinwave.degspeed'] = 30
      end
      if @data.include?(timing + 'wave')
        @settings['wave'] = @data[timing + 'wave']
      else
        @settings['wave'] = nil
      end
      if @data.include?(timing + 'wave.loop')
        if @data[timing + 'wave.loop'] == 'on'
          @settings['wave.loop'] = 1
        else
          @settings['wave.loop'] = 0
        end
      else
        @settings['wave.loop'] = 0
      end
    end

    def set_scale(scale)
      @__scale = scale
      set_surface()
      set_position()
    end

    def set_position
      return if @settings['state'] != 'before'
      target_x, target_y = @target.get_surface_position(@side)
      target_w, target_h = @target.get_surface_size(@side)
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea)
      @x = (target_x + target_w / 2 - @w / 2 + (@offset_x * @__scale / 100).to_i)
      @y = (top + (@offset_y * @__scale / 100).to_i)
      @window.move(@x, @y)
    end

    def set_surface
      path = File.join(@data['dir'], 'surface' + @id.to_s + '.png')
      begin
        new_surface = Pix.create_surface_from_file(path)
        w = [8, (new_surface.width * @__scale / 100).to_i].max
        h = [8, (new_surface.height * @__scale / 100).to_i].max
      rescue
        @parent.handle_request(:GET, :finalize)
        return
      end
      @w, @h = w, h
      @reshape = true
      @image_surface = new_surface
      @darea.queue_draw()
    end

    def load(data)
      @data = data
      @__scale = @target.get_surface_scale()
      set_state('before')
      if @data.include?('category')
        category = @data['category'].split(',', 0)
        unless category.empty?
          unless CATEGORY_LIST.include?(category[0])
            Logging::Logging.warning('WARNING: unknown major category - ' + category[0])
          end
        else
          @data['category'] = CATEGORY_LIST[-1]
        end
      else
        @data['category'] = CATEGORY_LIST[-1]
      end
      if @data.include?('target')
        if @data['target'] == 'sakura'
          @side = 0
        elsif @data['target'] == 'kero'
          @side = 1
        else
          @side = 0 # XXX
        end
      else
        @side = 0 # XXX
      end
      if @parent.handle_request(:GET, :get_mode) == 1
        @parent.handle_request(:GET, :send_event, 'Emerge')
      end
      set_movement('before')
      offset_x = @data.include?('before.appear.ofset.x') ? @data['before.appear.ofset.x'] : 0
      offset_x = [[-32768, offset_x].max, 32767].min
      offset_y = @data.include?('before.appear.ofset.y') ? @data['before.appear.ofset.y'] : 0
      offset_y = [[-32768, offset_y].max, 32767].min
      @offset_x = offset_x
      @offset_y = offset_y
      @window = Pix::TransparentWindow.new()
      @window.set_title(@data['name'])
      @window.signal_connect('close-request') do |w|
        delete(w)
        next true
      end
      @darea = @window.darea

      # GTK4: draw func
      @darea.set_draw_func do |widget, cr, width, height|
        redraw(widget, cr)
      end

      @window.show()
      @id = 0
      set_surface()
      set_position()
      @loaded = true
    end

    def drop
      set_state('fall')
    end

    def set_state(state)
      @settings['state'] = state
      @time = 0
      @hit = 0
      @hit_stop = 0
    end

    def update_surface ## FIXME
    end

    def update_position ## FIXME
      if @settings['slide.type'] == 'leaf'
        #pass
      else
        if @settings['fall.type'] == 'gravity'
          @y += (@settings['fall.speed'].to_i * \
          (@time / 20.0)**2)
        elsif @settings['fall.type'] == 'evenspeed'
          @y += @settings['fall.speed']
        end
      end
      @window.move(@x, @y)
    end

    def check_collision ## FIXME
      for side in [0, 1]
        target_x, target_y = @target.get_surface_position(side)
        target_w, target_h = @target.get_surface_size(side)
        center_x = (@x + @w / 2)
        center_y = (@y + @h / 2)
        if target_x < center_x and center_x < (target_x + target_w) and \
          target_y < center_y and center_y < (target_y + target_h)
          @side = side
          return 1
        end
      end
      return 0
    end

    def check_mikire
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea)
      if (@x + @w - @w / 3) > (left + scrn_w) or \
        (@x + @w / 3) < left or \
        (@y + @h - @h / 3) > (top + scrn_h) or \
        (@y + @h / 3) < top
        return 1
      else
        return 0
      end
    end

    def update
      if @settings['state'] == 'fall'
        update_surface()
        update_position()
        unless check_collision().zero?
          set_state('hit')
          @hit = 1
          if @parent.handle_request(:GET, :get_mode) == 1
            @id = 1
            set_surface()
            @parent.handle_request(:GET, :send_event, 'Hit')
          end
        end
        set_state('dodge') unless check_mikire().zero?
      elsif @settings['state'] == 'hit'
        wait_time = @data.include?('hit.waittime') ? @data['hit.waittime'] : 0
        if @hit_stop >= wait_time
          set_state('after')
          set_movement('after')
          if @parent.handle_request(:GET, :get_mode) == 1
            @id = 2
            set_surface()
            @parent.handle_request(:GET, :send_event, 'Drop')
          end
        else
          @hit_stop += 1
          update_surface()
        end
      elsif @settings['state'] == 'after'
        update_surface()
        update_position()
        set_state('end') unless check_mikire().zero?
      elsif @settings['state'] == 'end'
        if @parent.handle_request(:GET, :get_mode) == 1
          @parent.handle_request(:GET, :send_event, 'Vanish')
        end
        @parent.handle_request(:GET, :delete_katochan)
        return false
      elsif @settings['state'] == 'dodge'
        if @parent.handle_request(:GET, :get_mode) == 1
          @parent.handle_request(:GET, :send_event, 'Dodge')
        end
        @parent.handle_request(:GET, :delete_katochan)
        return false
      end
      @time += 1
      return true
    end
  end
end
