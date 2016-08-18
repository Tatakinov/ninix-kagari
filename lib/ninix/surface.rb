# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"

require_relative "keymap"
require_relative "pix"
require_relative "seriko"
require_relative "logging"

module Surface

  class Surface
    attr_reader :name, :prefix, :window

    def initialize
      @window = []
      @desc = nil
      @mikire = 0
      @kasanari = 0
      @key_press_count = 0
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
        'stick_window' => 'window_stick',
      }
      if handlers.include?(event)
        result = handlers[event].call # no argument
      else
        if Surface.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = @parent.handle_request(event_type, event, *arglist)
        end
      end
      return result if event_type == 'GET'
    end

    def finalize
      for surface_window in @window
        surface_window.destroy
      end
      @window = []
    end

    def create_gtk_window(title, skip_taskbar)
      window = Pix::TransparentWindow.new()
      window.set_title(title)
      if skip_taskbar
        window.set_skip_taskbar_hint(true)
      end
      window.signal_connect('delete_event') do |w, e|
        next delete(w, e)
      end
      window.signal_connect('key_press_event') do |w, e|
        next key_press(w, e)
      end
      window.signal_connect('key_release_event') do |w, e|
        next key_press(w, e)
      end
      window.signal_connect('window_state_event') do |w, e|
        window_state(w, e)
        next true
      end
      window.set_events(Gdk::EventMask::KEY_PRESS_MASK|
                        Gdk::EventMask::KEY_RELEASE_MASK)
      window.realize()
      return window
    end

    def identify_window(win)
      for surface_window in @window
        return true if win == surface_window.get_window.window
      end
      return false
    end

    def window_stayontop(flag)
      for surface_window in @window
        gtk_window = surface_window.get_window
        gtk_window.set_keep_above(flag)
      end
    end
         
    def window_iconify(flag)
      gtk_window = @window[0].window
      iconified = (gtk_window.window.state & \
                   Gdk::WindowState::ICONIFIED).nonzero?
      if flag and not iconified
        gtk_window.iconify()
      elsif not flag and iconified
        gtk_window.deiconify()
      end
    end

    def window_state(window, event)
      return unless @parent.handle_request('GET', 'is_running')
      return if (event.changed_mask & Gdk::WindowState::ICONIFIED).zero?
      if (event.new_window_state & Gdk::WindowState::ICONIFIED).nonzero?
        if window == @window[0].get_window
          @parent.handle_request('NOTIFY', 'notify_iconified')
        end
        for surface_window in @window
          gtk_window = surface_window.get_window
          if gtk_window != window and \
            (gtk_window.window.state & \
             Gdk::WindowState::ICONIFIED).nonzero?
            gtk_window.iconify()
          end
        end
      else
        for surface_window in @window
          gtk_window = surface_window.get_window
          if gtk_window != window and \
            (gtk_window.window.state & \
             Gdk::WindowState::ICONIFIED).nonzero?
            gtk_window.deiconify()
          end
        end
        if window == @window[0].window
          @parent.handle_request('NOTIFY', 'notify_deiconified')
        end
      end
      return
    end

    def delete(window, event)
      return true
    end

    def key_press(window, event)
      name = Keymap::Keymap_old[event.keyval]
      keycode = Keymap::Keymap_new[event.keyval]
      if event.event_type == Gdk::EventType::KEY_RELEASE
        @key_press_count = 0
        return true
      end
      return false unless (event.event_type == Gdk::EventType::KEY_PRESS)
      @key_press_count += 1
      if (event.state & \
          (Gdk::ModifierType::CONTROL_MASK | \
           Gdk::ModifierType::SHIFT_MASK)).nonzero?
        if name == 'f12'
          Logging::Logging.info('reset surface position')
          reset_position()
        end
        if name == 'f10'
          Logging::Logging.info('reset balloon offset')
          for side in 0..@window.length-1
            set_balloon_offset(side, nil)
          end
        end
      end
      unless name.nil? and keycode.nil?
        @parent.handle_request(
          'NOTIFY', 'notify_event', 'OnKeyPress', name, keycode,
          @key_press_count)
      end
      return true
    end

    def window_stick(stick)
      for window in @window
        if stick
          window.get_window.stick()
        else
          window.get_window.unstick()
        end
      end
    end

    RE_SURFACE_ID = Regexp.new('\Asurface([0-9]+)\z')

    def get_seriko(surface)
      seriko = {}
      for basename in surface.keys
        path, config = surface[basename]
        match = RE_SURFACE_ID.match(basename)
        next if match.nil?
        key = match[1]
        # define animation patterns
        version = 1 # default: SERIKO/1.x
        if @seriko_descript['version'] == '1'
          version = 2 # SERIKO/2.0
        end
        seriko[key] = Seriko.get_actors(config, :version => version)
      end
      return seriko
    end

    def new_(desc, surface_alias, surface, name, prefix, tooltips, seriko_descript,
            default_sakura, default_kero)
      @desc = desc
      @__tooltips = tooltips
      @seriko_descript = seriko_descript
      @name = name
      @prefix = prefix
      # load surface
      surfaces = {}
      elements = {}
      begin
        maxwidth = Integer(@seriko_descript.get('maxwidth', :default => '0'))
      rescue
        maxwidth = 0
      end
      maxheight = 0
      for basename in surface.keys
        path, config = surface[basename]
        next if path.nil?
        unless File.exists?(path)
          name = File.basename(path, ".*")
          ext = File.extname(path)
          dgp_path = [name, '.dgp'].join('')
          unless File.exists?(dgp_path)
            ddp_path = [name, '.ddp'].join('')
            unless File.exists?(ddp_path)
              Logging::Logging.error(
                path + ': file not found (ignored)')
              next
            else
              path = ddp_path
            end
          else
            path = dgp_path
          end
        end
        elements[basename] = [path]
        w, h = Pix.get_png_size(path)
        maxwidth = [maxwidth, w].max
        maxheight = [maxheight, h].max
        match = RE_SURFACE_ID.match(basename)
        next if match.nil?
        key = match[1]
        surfaces[key] = elements[basename]
      end
      # compose surface elements
      composite_surface = {}
      for basename in surface.keys
        path, config = surface[basename]
        match = RE_SURFACE_ID.match(basename)
        next if match.nil?
        key = match[1]
        if config.include?('element0')
          Logging::Logging.debug('surface ' + key)
          composite_surface[key] = compose_elements(elements, config)
        end
      end
      surfaces.update(composite_surface)
      # check if necessary surfaces have been loaded
      for key in [default_sakura, default_kero]
        unless surfaces.include?(key.to_s)
          fail RuntimeError, "cannot load default surface ##{key} (abort)\n"
        end
      end
      @__surfaces = surfaces
      # arrange surface configurations
      region = {}
      for basename in surface.keys
        path, config = surface[basename]
        match = RE_SURFACE_ID.match(basename)
        next if match.nil?
        key = match[1]
        # define collision areas
        buf = []
        for n in 0..255
          # "redo" syntax
          rect = config.get(['collision', n.to_s].join(''))
          next if rect.nil?
          values = rect.split(',', 0)
          next if values.length != 5
          begin
            x1 = Integer(values[0])
            y1 = Integer(values[1])
            x2 = Integer(values[2])
            y2 = Integer(values[3])
          rescue
            next
          end
          buf << [values[4].strip(), x1, y1, x2, y2]
        end
        for part in ['head', 'face', 'bust']
          # "inverse" syntax
          rect = config.get(['collision.', part].join(''))
          next if rect.nil?
          begin
            values = rect.split(',', 0)
            x1 = Integer(values[0])
            y1 = Integer(values[1])
            x2 = Integer(values[2])
            y2 = Integer(values[3])
          rescue
            #pass
          end
          buf << [part.capitalize(), x1, y1, x2, y2]
        end
        region[key] = buf
      end
      @__region = region
      # MAYUNA
      mayuna = {}
      for basename in surface.keys
        path, config = surface[basename]
        match = RE_SURFACE_ID.match(basename)
        next if match.nil?
        key = match[1]
        # define animation patterns
        mayuna[key] = Seriko.get_mayuna(config)
      end
      @mayuna = {}
      # create surface windows
      for surface_window in @window
        surface_window.destroy()
      end
      @window = []
      @__surface = surface
      @maxsize = [maxwidth, maxheight]
      add_window(0, default_sakura, :config_alias => surface_alias, :mayuna => mayuna)
      add_window(1, default_kero, :config_alias => surface_alias, :mayuna => mayuna)
    end

    def get_menu_pixmap
      top_dir = @prefix
      name = @desc.get('menu.background.bitmap.filename')
      unless name.nil?
        name = name.gsub('\\', '/')
        path_background = File.join(top_dir, name)
      else
        path_background = nil
      end
      name = @desc.get('menu.sidebar.bitmap.filename')
      unless name.nil?
        name = name.gsub('\\', '/')
        path_sidebar = File.join(top_dir, name)
      else
        path_sidebar = nil
      end
      name = @desc.get('menu.foreground.bitmap.filename')
      unless name.nil?
        name = name.gsub('\\', '/')
        path_foreground = File.join(top_dir, name)
      else
        path_foreground = nil
      end
      align_background = @desc.get('menu.background.alignment')
      align_sidebar = @desc.get('menu.sidebar.alignment')
      align_foreground = @desc.get('menu.foreground.alignment')
      return path_background, path_sidebar, path_foreground, \
      align_background, align_sidebar, align_foreground
    end

    def get_menu_fontcolor
      fontcolor_r = @desc.get('menu.background.font.color.r', :default => 0).to_i
      fontcolor_g = @desc.get('menu.background.font.color.g', :default => 0).to_i
      fontcolor_b = @desc.get('menu.background.font.color.b', :default => 0).to_i
      fontcolor_r = [0, [255, fontcolor_r].min].max
      fontcolor_g = [0, [255, fontcolor_g].min].max
      fontcolor_b = [0, [255, fontcolor_b].min].max
      background = [fontcolor_r, fontcolor_g, fontcolor_b]
      fontcolor_r = @desc.get('menu.foreground.font.color.r', :default => 0).to_i
      fontcolor_g = @desc.get('menu.foreground.font.color.g', :default => 0).to_i
      fontcolor_b = @desc.get('menu.foreground.font.color.b', :default => 0).to_i
      fontcolor_r = [0, [255, fontcolor_r].min].max
      fontcolor_g = [0, [255, fontcolor_g].min].max
      fontcolor_b = [0, [255, fontcolor_b].min].max
      foreground = [fontcolor_r, fontcolor_g, fontcolor_b]
      return background, foreground
    end

    def add_window(side, default_id, config_alias: nil, mayuna: {})
      fail "assert" unless @window.length == side
      case side
      when 0
        name = 'sakura'
        title = @parent.handle_request('GET', 'get_selfname') or \
        ['surface.', name].join('')
      when 1
        name = 'kero'
        title = @parent.handle_request('GET', 'get_keroname') or \
        ['surface.', name].join('')
      else
        name = ('char' + side.to_i.to_s)
        title = ['surface.', name].join('')
      end
      if config_alias.nil?
        surface_alias = nil
      else
        surface_alias = config_alias.get(name + '.surface.alias')
      end
      # MAYUNA
      bind = {}
      for index in 0..127
        group = @desc.get(
          name + '.bindgroup' + index.to_i.to_s + '.name', :default => nil)
        default = @desc.get(
          name + '.bindgroup' + index.to_i.to_s + '.default', :default => 0)
        bind[index] = [group, (not default.zero?)] unless group.nil?
      end
      @mayuna[name] = []
      for index in 0..127
        key = @desc.get(name + '.menuitem' + index.to_i.to_s, :default => nil)
        if key == '-'
          @mayuna[name] << [key, nil, 0]
        else
          begin
            key = Integer(key)
          rescue
            #pass
          else
            if bind.include?(key)
              group = bind[key][0].split(',', 2)
              @mayuna[name] << [key, group[1], bind[key][1]]
            end
          end
        end
      end
      skip_taskbar = (side >= 1)
      gtk_window = create_gtk_window(title, skip_taskbar)
      seriko = get_seriko(@__surface)
      tooltips = {}
      if @__tooltips.include?(name)
        tooltips = @__tooltips[name]
      end
      surface_window = SurfaceWindow.new(
        gtk_window, side, @desc, surface_alias, @__surface, tooltips,
        @__surfaces, seriko, @__region, mayuna, bind,
        default_id, @maxsize)
      surface_window.set_responsible(self)
      @window << surface_window
    end

    def get_mayuna_menu
      for side, index in [['sakura', 0], ['kero', 1]]
        for menu in @mayuna[side]
          if menu[0] != '-'
            menu[2] = @window[index].bind[menu[0]][1]
          end
        end
      end
      return @mayuna
    end

    def compose_elements(elements, config)
      error = nil
      for n in 0..255
        key = ['element', n.to_s].join('')
        break unless config.include?(key)
        spec = []
        for value in config[key].split(',', 0)
          spec << value.strip()
        end
        begin
          method, filename, x, y = spec
          x = Integer(x)
          y = Integer(y)
        rescue
          error = ('invalid element spec for ' + key + ': ' + config[key])
          break
        end
        basename = File.basename(filename, ".*")
        ext = File.extname(filename)
        ext = ext.downcase
        unless ['.png', '.dgp', '.ddp'].include?(ext)
          error = ('unsupported file format for ' + key + ': ' + filename)
          break
        end
        basename = basename.downcase
        unless elements.include?(basename)
          error = (key + ' file not found: ' + filename)
          break
        end
        surface = elements[basename][0]
        if n.zero? # base surface
          surface_list = [surface]
        elsif ['overlay', 'overlayfast',
               'interpolate', 'reduce', 'replace', 'asis'].include?(method)
          surface_list << [surface, x, y, method]
        elsif method == 'base'
          surface_list << [surface, x, y, method]
        else
          error = ('unknown method for ' + key + ': ' + method)
          break
        end
        Logging::Logging.debug(key + ': ' + method + ' ' + filename + ', x=' + x.to_i.to_s + ', y=' + y.to_i.to_s)
      end
      unless error.nil?
        Logging::Logging.error(error)
        surface_list = []
      end
      return surface_list
    end

    def get_window(side)
      if @window.length > side
        return @window[side].get_window
      else 
        return nil
      end
    end

    def reset_surface
      for window in @window
        window.reset_surface()
      end
    end

    def set_surface_default(side)
      if side.nil?
        for side in 0..@window.length-1
          @window[side].set_surface_default()
        end
      elsif 0 <= side and side < @window.length
        @window[side].set_surface_default()
      end
    end

    def set_surface(side, surface_id)
      if @window.length > side
        @window[side].set_surface(surface_id)
      end
    end

    def get_surface(side)
      if @window.length > side
        return @window[side].get_surface()
      else
        return 0
      end
    end

    def get_max_size(side)
      if @window.length > side
        return @window[side].get_max_size()
      else
        return @window[0].get_max_size() # XXX
      end
    end

    def get_surface_size(side)
      if @window.length > side
        return @window[side].get_surface_size()
      else
        return 0, 0
      end
    end

    def get_surface_offset(side)
      if @window.length > side
        return @window[side].get_surface_offset()
      else
        return 0, 0
      end
    end

    def get_touched_region(side, x, y)
      if @window.length > side
        return @window[side].get_touched_region(x, y)
      else
        return ''
      end
    end

    def get_center(side)
      if @window.length > side
        return @window[side].get_center()
      else
        return nil, nil
      end
    end

    def get_kinoko_center(side)
      if @window.length > side
        return @window[side].get_kinoko_center()
      else
        return nil, nil
      end
    end

    def reset_balloon_position
      for side in 0..@window.length-1
        x, y = get_position(side)
        direction = @window[side].direction
        ox, oy = get_balloon_offset(side)
        @parent.handle_request(
          'NOTIFY', 'set_balloon_direction', side, direction)
        if direction.zero? # left
          base_x = (x + ox)
        else
          w, h = get_surface_size(side)
          base_x = (x + w - ox)
        end
        base_y = (y + oy)
        @parent.handle_request(
          'NOTIFY', 'set_balloon_position', side, base_x, base_y)
      end
    end

    def reset_position
      left, top, scrn_w, scrn_h = get_workarea(0) # XXX
      s0x, s0y, s0w, s0h = 0, 0, 0, 0 # XXX
      for side in 0..@window.length-1
        align = get_alignment(side)
        w, h = get_max_size(side)
        if side.zero? # sakura
          x = (left + scrn_w - w)
        else
          b0w, b0h = @parent.handle_request(
                 'GET', 'get_balloon_size', side - 1)
          b1w, b1h = @parent.handle_request(
                 'GET', 'get_balloon_size', side)
          bpx, bpy = @parent.handle_request(
                 'GET', 'get_balloon_windowposition', side)
          o0x, o0y = get_balloon_offset(side - 1)
          o1x, o1y = get_balloon_offset(side)
          offset = [0, b1w - (b0w - o0x)].max
          if ((s0x + o0x - b0w) - offset - w + o1x) < left
            x = left
          else
            x = ((s0x + o0x - b0w) - offset - w + o1x)
          end
        end
        if align == 1 # top
          y = top
        else
          y = (top + scrn_h - h)
        end
        set_position(side, x, y)
        s0x, s0y, s0w, s0h = x, y, w, h # for next loop
      end
    end

    def get_workarea(side)
      if @window.length > side
        return @window[side].get_window.workarea
      else
        return [0, 0, 0, 0]
      end
    end

    def set_position(side, x, y)
      if @window.length > side
        @window[side].set_position(x, y)
      end
    end

    def get_position(side)
      if @window.length > side
        return @window[side].get_position()
      else
        return 0, 0
      end
    end

    def set_alignment_current
      for side in 0..@window.length-1
        @window[side].set_alignment_current()
      end
    end

    def set_alignment(side, align)
      if @window.length > side
        @window[side].set_alignment(align)
      end
    end

    def get_alignment(side)
      if @window.length > side
        return @window[side].get_alignment()
      else
        return 0
      end
    end

    def reset_alignment
      if @desc.get('seriko.alignmenttodesktop') == 'free'
        align = 2
      else
        align = 0
      end
      for side in 0..@window.length-1
        set_alignment(side, align)
      end
    end

    def is_shown(side)
      if @window.length > side
        return @window[side].is_shown()
      else
        return false
      end
    end

    def show(side)
      if @window.length > side
        @window[side].show()
      end
    end

    def hide_all
      for side in 0..@window.length-1
        @window[side].hide()
      end
    end

    def hide(side)
      if @window.length > side
        @window[side].hide()
      end
    end

    def raise_all
      for side in 0..@window.length-1
        @window[side].raise
      end
    end

    def raise(side)
      if @window.length > side
        @window[side].raise
      end
    end

    def lower_all
      for side in 0..@window.length-1
        @window[side].lower()
      end
    end

    def lower(side)
      if @window.length > side
        @window[side].lower()
      end
    end

    def invoke(side, actor_id)
      if @window.length > side
        @window[side].invoke(actor_id)
      end
    end

    def invoke_yen_e(side, surface_id)
      if @window.length > side
        @window[side].invoke_yen_e(surface_id)
      end
    end

    def invoke_talk(side, surface_id, count)
      if @window.length > side
        return @window[side].invoke_talk(surface_id, count)
      else
        return false
      end
    end

    def set_icon(path)
      return if path.nil? or not File.exists?(path)
      for window in @window
        window.get_window.set_icon(path) # XXX
      end
    end

    def get_mikire
      @mikire
    end

    def get_kasanari
      @kasanari
    end

    def get_name
      @name
    end

    def get_username
      if @desc.nil?
        return nil
      else
        return @desc.get('user.defaultname')
      end
    end

    def get_selfname
      if @desc.nil?
        return nil
      else
        return @desc.get('sakura.name')
      end
    end

    def get_selfname2
      if @desc.nil?
        return nil
      else
        return @desc.get('sakura.name2')
      end
    end

    def get_keroname
      if @desc.nil?
        return nil
      else
        return @desc.get('kero.name')
      end
    end

    def get_friendname
      if @desc.nil?
        return nil
      else
        return @desc.get('sakura.friend.name')
      end
    end

    def get_balloon_offset(side)
      if @window.length > side
        x, y = @window[side].get_balloon_offset
        scale = @window[side].get_scale
        x = (x * scale / 100).to_i
        y = (y * scale / 100).to_i
        return x, y
      end
      return 0, 0
    end

    def set_balloon_offset(side, offset)
      if @window.length > side
        @window[side].balloon_offset = offset
      end
    end

    def toggle_bind(args)
      side, bind_id = args
      @window[side].toggle_bind(bind_id)
    end

    def get_collision_area(side, part)
      if @window.length > side
        return @window[side].get_collision_area(part)
      end
      return nil
    end

    def check_mikire_kasanari
      unless is_shown(0)
        @mikire = @kasanari = 0
        return
      end
      left, top, scrn_w, scrn_h = get_workarea(0)
      x0, y0 = get_position(0)
      s0w, s0h = get_surface_size(0)
      if (x0 + s0w / 3) < left or (x0 + s0w * 2 / 3) > (left + scrn_w) or \
        (y0 + s0h / 3) < top or (y0 + s0h * 2 / 3) > (top + scrn_h)
        @mikire = 1
      else
        @mikire = 0
      end
      unless is_shown(1)
        @kasanari = 0
        return
      end
      x1, y1 = get_position(1)
      s1w, s1h = get_surface_size(1)
      if (x0 < (x1 + s1w / 2) and
          (x1 + s1w / 2) < (x0 + s0w) and
          y0 < (y1 + s1h / 2) and
          (y1 + s1h / 2) < (y0 + s0h)) or
        (x1 < (x0 + s0w / 2) and
         (x0 + s0w / 2) < (x1 + s1w) and
         y1 < (y0 + s0h / 2) and
         (y0 + s0h / 2) < (y1 + s1h))
        @kasanari = 1
      else
        @kasanari = 0
      end
    end
  end

  class SurfaceWindow
    attr_reader :bind

    def initialize(window, side, desc, surface_alias, surface_info, tooltips,
                   surfaces, seriko, region, mayuna, bind, default_id, maxsize)
      @window = window
      @maxsize = maxsize
      @side = side
      @parent = nil
      @desc = desc
      @alias = surface_alias
      @tooltips = tooltips
      @align = 0
      @__current_part = ''
      unless @alias.nil? or @alias[default_id].nil?
        default_id = @alias[default_id][0]
      end
      @surface_info = surface_info
      @surface_id = default_id
      @surfaces = surfaces
      @image_surface = nil # XXX
      @seriko = Seriko::Controller.new(seriko)
      @seriko.set_responsible(self)
      @region = region
      @mayuna = mayuna
      @bind = bind
      @default_id = default_id
      @__shown = false
      @window_offset = [0, 0]
      @position = [0, 0]
      @__direction = 0
      @dragged = false
      @x_root = nil
      @y_root = nil
      @click_count = 0
      @__balloon_offset = nil
      @window.signal_connect('leave_notify_event') do |w, e|
        next window_leave_notify(w, e) # XXX
      end
      @window.signal_connect('enter_notify_event') do |w, e|
        window_enter_notify(w, e) # XXX
        next true
      end
      @darea = @window.darea
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK|
                        Gdk::EventMask::BUTTON_PRESS_MASK|
                        Gdk::EventMask::BUTTON_RELEASE_MASK|
                        Gdk::EventMask::POINTER_MOTION_MASK|
                        Gdk::EventMask::POINTER_MOTION_HINT_MASK|
                        Gdk::EventMask::SCROLL_MASK)
      @darea.signal_connect('draw') do |w, e|
        redraw(w, e)
        next true
      end
      @darea.signal_connect('button_press_event') do |w, e|
        next button_press(w, e)
      end
      @darea.signal_connect('button_release_event') do |w, e|
        next button_release(w, e)
      end
      @darea.signal_connect('motion_notify_event') do |w, e|
        next motion_notify(w, e)
      end
      @darea.signal_connect('drag_data_received') do |widget, context, x, y, data, info, time|
        drag_data_received(widget, context, x, y, data, info, time)
        next true
      end
      @darea.signal_connect('scroll_event') do |w, e|
        next scroll(w, e)
      end
      if @side.zero?
        screen = @window.screen
        screen.signal_connect('size-changed') do |scr|
          display_changed(scr)
          next true
        end
      end
      # DnD data types
      dnd_targets = [['text/uri-list', 0, 0]]
      @darea.drag_dest_set(Gtk::Drag::DestDefaults::ALL, dnd_targets,
                           Gdk::DragAction::COPY)
      @darea.drag_dest_add_uri_targets()
    end

    def get_seriko
      @seriko
    end

    def get_window
      @window
    end

    def get_surface_id
      @surface_id
    end

    def display_changed(screen)
      return unless @side.zero?
      @parent.handle_request('NOTIFY', 'reset_position') # XXX
      left, top, scrn_w, scrn_h = @window.workarea
      @parent.handle_request(
        'NOTIFY', 'notify_event', 'OnDisplayChange',
        Gdk.Visual.get_best_depth(), scrn_w, scrn_h)
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
            }
      if handlers.include?(event)
        result = handlers[event].call # no argument
      else
        if SurfaceWindow.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = @parent.handle_request(event_type, event, *arglist)
        end
      end
      return result if event_type == 'GET'
    end

    @property
    def direction
      @__direction
    end

    def direction=(value)
      @__direction = value # 0: left, 1: right
      @parent.handle_request(
        'NOTIFY', 'set_balloon_direction', @side, value)
    end

    def get_scale
      @parent.handle_request('GET', 'get_preference', 'surface_scale')
    end

    def get_balloon_offset
      if @__balloon_offset.nil?
        path, config = @surface_info[['surface', @surface_id].join('')]
        side = @side
        case side
        when 0
          name = 'sakura'
          x = config.get(name + '.balloon.offsetx').to_i
          y = config.get(name + '.balloon.offsety').to_i
        when 1
          name = 'kero'
          x = config.get(name + '.balloon.offsetx').to_i
          y = config.get(name + '.balloon.offsety').to_i
        else
          name = ('char' + side.to_i.to_s)
          x, y = nil, nil # XXX
        end
        if x.nil?
          x = @desc.get(name + '.balloon.offsetx')
          if x.nil?
            x = 0
          else
            x = x.to_i
          end
        end
        if y.nil?
          y = @desc.get(name + '.balloon.offsety')
          if y.nil?
            y = 0
          else
            y = y.to_i
          end
        end
      else
        x, y = @__balloon_offset
      end
      return x, y
    end

    def balloon_offset=(offset)
      @__balloon_offset = offset # (x, y)
      @parent.handle_request('NOTIFY', 'reset_balloon_position')
    end

    def drag_data_received(widget, context, x, y, data, info, time)
      filelist = []
      for uri in data.uris
        uri_parsed = URI.parse(uri)
        pathname = URI.unescape(uri_parsed.path)
        if uri_parsed.scheme == 'file' and File.exists?(pathname)
          filelist << pathname
        end
      end
      unless filelist.empty?
        @parent.handle_request(
          'NOTIFY', 'enqueue_event',
          'OnFileDrop2', filelist.join(1.chr), @side)
      end
    end

    def append_actor(frame, actor)
      @seriko.append_actor(frame, actor)
    end

    def invoke(actor_id, update: 0)
      @seriko.invoke(self, actor_id, :update => update)
    end

    def invoke_yen_e(surface_id)
      @seriko.invoke_yen_e(self, surface_id)
    end

    def invoke_talk(surface_id, count)
      @seriko.invoke_talk(self, surface_id, count)
    end

    def reset_surface
      surface_id = get_surface()
      set_surface(surface_id)
    end

    def set_surface_default
      set_surface(@default_id)
    end

    def set_surface(surface_id)
      prev_id = @surface_id
      if not @alias.nil? and @alias.include?(surface_id)
        aliases = @alias[surface_id]
        unless aliases.empty?
          surface_id = aliases.sample
        end
      end
      if surface_id == '-2'
        @seriko.terminate(self)
      end
      if ['-1', '-2'].include?(surface_id)
        #pass
      elsif not @surfaces.include?(surface_id)
        @surface_id = @default_id
      else
        @surface_id = surface_id
      end
      @seriko.reset(self, surface_id)
      # define collision areas
      @collisions = @region[@surface_id]
      # update window offset
      x, y = @position # XXX: without window_offset
      w, h = get_surface_size(:surface_id => @surface_id)
      dw, dh = get_max_size()
      xoffset = ((dw - w) / 2)
      case get_alignment()
      when 0
        yoffset = (dh - h)
        left, top, scrn_w, scrn_h = @window.workarea
        y = (top + scrn_h - dh)
      when 1
        yoffset = 0
      else
        yoffset = ((dh - h) / 2)
      end
      @window_offset = [xoffset, yoffset]
      # resize window
      @window.update_size(*get_max_size())
      @seriko.start(self)
      # relocate window
      unless @dragged # XXX
        set_position(x, y)
      end
      if @side < 2
        @parent.handle_request('NOTIFY', 'notify_observer', 'set surface')
      end
      w, h = get_surface_size(:surface_id => @surface_id)
      new_x, new_y = get_position()
      @parent.handle_request(
        'NOTIFY', 'notify_event',
        'OnSurfaceChange',
        @parent.handle_request('GET', 'get_surface_id', 0),
        @parent.handle_request('GET', 'get_surface_id', 1),
        [@side, @surface_id, w, h].join(','),
        prev_id.to_s,
        [new_x, new_y, new_x + w, new_y + h].join(','))
      update_frame_buffer() #XXX
    end

    def iter_mayuna(surface_width, surface_height, mayuna, done)
      mayuna_list = [] # XXX: FIXME
      for surface_id, interval, method, args in mayuna.get_patterns
        case method
        when 'bind', 'add'
          if @surfaces.include?(surface_id)
            dest_x, dest_y = args
            mayuna_list << [method, surface_id, dest_x, dest_y]
          end
        when 'reduce'
          if @surfaces.include?(surface_id)
            dest_x, dest_y = args
            mayuna_list << [method, surface_id, dest_x, dest_y]
          end
        when 'insert'
          index = args[0]
          for actor in @mayuna[@surface_id]
            actor_id = actor.get_id()
            if actor_id == index
              if @bind.include?(actor_id) and @bind[actor_id][1] and \
                not done.include?(actor_id)
                done << actor_id
                for result in iter_mayuna(surface_width, surface_height, actor, done)
                  mayuna_list << result
                end
              else
                break
              end
            end
          end
        else
          fail RuntimeError('should not reach here')
        end
      end
      return mayuna_list
    end
    
    def create_surface_from_file(surface_id, is_asis: false)
      fail "assert" unless @surfaces.include?(surface_id)
      if is_asis
        use_pna = false
        is_pnr = false
      else
        use_pna = (not @parent.handle_request('GET', 'get_preference', 'use_pna').zero?)
        is_pnr = true
      end
      begin
        surface = Pix.create_surface_from_file(
          @surfaces[surface_id][0], :is_pnr => is_pnr, :use_pna => use_pna)
      rescue
        Logging::Logging.debug('cannot load surface #' + surface_id.to_s)
        return Pix.create_blank_surface(100, 100)
      end
      for element, x, y, method in @surfaces[surface_id][1, @surfaces[surface_id].length - 1]
        begin
          if method == 'asis'
            is_pnr = false
            use_pna = false
          else
            is_pnr = true
            use_pna = (not @parent.handle_request(
                        'GET', 'get_preference', 'use_pna').zero?)
          end
          overlay = Pix.create_surface_from_file(
            element, :is_pnr => is_pnr, :use_pna => use_pna)
        rescue
          next
        end
        cr = Cairo::Context.new(surface)
        op = {
          'base' =>        Cairo::OPERATOR_SOURCE, # XXX
          'overlay' =>     Cairo::OPERATOR_OVER,
          'overlayfast' => Cairo::OPERATOR_ATOP,
          'interpolate' => Cairo::OPERATOR_SATURATE,
          'reduce' =>      Cairo::OPERATOR_DEST_IN,
          'replace' =>     Cairo::OPERATOR_SOURCE,
          'asis' =>        Cairo::OPERATOR_OVER,
        }[method]
        cr.set_operator(op)
        cr.set_source(overlay, x, y)
        if ['overlay', 'overlayfast'].include?(method)
          cr.mask(overlay, x, y)
        else
          cr.paint()
        end
      end
      return surface
    end

    def get_image_surface(surface_id, is_asis: false)
      unless @surfaces.include?(surface_id)
        Logging::Logging.debug('cannot load surface #' + surface_id.to_s)
        return Pix.create_blank_surface(100, 100)
      end
      return create_surface_from_file(surface_id, :is_asis => is_asis)
    end

    def draw_region(cr)
      return if @collisions.nil?
      cr.save()
      # translate the user-space origin
      cr.translate(*@window.get_draw_offset) # XXX
      scale = get_scale
      cr.scale(scale / 100.0, scale / 100.0)
      for part, x1, y1, x2, y2 in @collisions
        unless @parent.handle_request('GET', 'get_preference',
                                      'check_collision_name').zero?
          cr.set_operator(Cairo::OPERATOR_SOURCE)
          cr.set_source_rgba(0.4, 0.0, 0.0, 1.0) # XXX
          cr.move_to(x1 + 2, y1)
          font_desc = Pango::FontDescription.new
          font_desc.set_size(8 * Pango::SCALE)
          layout = cr.create_pango_layout
          layout.set_font_description(font_desc)
          layout.set_wrap(Pango::WRAP_WORD_CHAR) # XXX
          layout.set_text(part)
          cr.show_pango_layout(layout)
        end
        cr.set_operator(Cairo::OPERATOR_ATOP)
        cr.set_source_rgba(0.2, 0.0, 0.0, 0.4) # XXX
        cr.rectangle(x1, y1, x2 - x1, y2 - y1)
        cr.fill_preserve()
        cr.set_operator(Cairo::OPERATOR_SOURCE)
        cr.set_source_rgba(0.4, 0.0, 0.0, 0.8) # XXX
        cr.stroke()
      end
      cr.restore()
    end

    def create_image_surface(surface_id)
      if surface_id.nil?
        surface_id = @surface_id
      end
      if @mayuna.include?(surface_id) and @mayuna[surface_id]
        surface = get_image_surface(surface_id)
        surface_width = surface.width
        surface_height = surface.height
        done = []
        for actor in @mayuna[surface_id]
          actor_id = actor.get_id()
          if @bind.include?(actor_id) and @bind[actor_id][1] and \
            not done.include?(actor_id)
            done << actor_id
            for method, mayuna_id, dest_x, dest_y in iter_mayuna(surface_width, surface_height, actor, done)
              mayuna_surface = get_image_surface(mayuna_id)
              cr = Cairo::Context.new(surface)
              if ['bind', 'add'].include?(method)
                cr.set_source(mayuna_surface, dest_x, dest_y)
                cr.mask(mayuna_surface, dest_x, dest_y)
              elsif method == 'reduce'
                cr.set_operator(Cairo::OPERATOR_DEST_IN)
                cr.set_source(mayuna_surface, dest_x, dest_y)
                cr.paint()
              else
                fail RuntimeError('should not reach here')
              end
            end
          end
        end
      else
        surface = get_image_surface(surface_id)
      end
      return surface
    end

    def update_frame_buffer
      return if @parent.handle_request('GET', 'lock_repaint')
      new_surface = create_image_surface(@seriko.get_base_id)
      fail "assert" if new_surface.nil?
      # update collision areas
      @collisions = @region[@seriko.get_base_id]
      # draw overlays
      for surface_id, x, y, method in @seriko.iter_overlays()
        begin
          overlay_surface = get_image_surface(
            surface_id, :is_asis => (method == 'asis'))
        rescue
          next
        end
        # overlay surface
        cr = Cairo::Context.new(new_surface)
        op = {
          'base' =>        Cairo::OPERATOR_SOURCE, # XXX
          'overlay' =>     Cairo::OPERATOR_OVER,
          'overlayfast' => Cairo::OPERATOR_ATOP,
          'interpolate' => Cairo::OPERATOR_SATURATE,
          'reduce' =>      Cairo::OPERATOR_DEST_IN,
          'replace' =>     Cairo::OPERATOR_SOURCE,
          'asis' =>        Cairo::OPERATOR_OVER,
        }[method]
        cr.set_operator(op)
        cr.set_source(overlay_surface, x, y)
        if ['overlay', 'overlayfast'].include?(method)
          cr.mask(overlay_surface, x, y)
        else
          cr.paint()
        end
      end
      @image_surface = new_surface
      @darea.queue_draw()
    end

    def redraw(darea, cr)
      return if @image_surface.nil? # XXX
      @window.set_surface(cr, @image_surface, get_scale)
      unless @parent.handle_request('GET', 'get_preference', 'check_collision').zero?
        draw_region(cr)
      end
      @window.set_shape(cr)
    end

    def remove_overlay(actor)
      @seriko.remove_overlay(actor)
    end

    def add_overlay(actor, surface_id, x, y, method)
      @seriko.add_overlay(self, actor, surface_id, x, y, method)
    end

    def move_surface(xoffset, yoffset)
      return if @parent.handle_request('GET', 'lock_repaint')
      x, y = get_position()
      @window.move(x + xoffset, y + yoffset)
      if @side < 2
        args = [@side, xoffset, yoffset]
        @parent.handle_request(
          'NOTIFY', 'notify_observer', 'move surface', :args => args) # animation
      end
    end

    def get_collision_area(part)
      for p, x1, y1, x2, y2 in @collisions
        if p == part
          scale = get_scale
          x1 = (x1 * scale / 100).to_i
          x2 = (x2 * scale / 100).to_i
          y1 = (y1 * scale / 100).to_i
          y2 = (y2 * scale / 100).to_i
          return x1, y1, x2, y2
        end
      end
      return nil
    end

    def get_surface
      @surface_id
    end

    def get_max_size
      left, top, scrn_w, scrn_h = @window.workarea
      w, h = @maxsize
      scale = get_scale
      w = [scrn_w, [8, (w * scale / 100).to_i].max].min
      h = [scrn_h, [8, (h * scale / 100).to_i].max].min
      return w, h
    end

    def get_surface_size(surface_id: nil)
      if surface_id.nil?
        surface_id = @surface_id
      end
      unless @surfaces.include?(surface_id)
        w, h = 100, 100 # XXX
      else
        w, h = Pix.get_png_size(@surfaces[surface_id][0])
      end
      scale = get_scale
      w = [8, (w * scale / 100).to_i].max
      h = [8, (h * scale / 100).to_i].max
      return w, h
    end

    def get_surface_offset
      @window_offset
    end

    def get_touched_region(x, y)
      return '' if @collisions.nil?
      for part, x1, y1, x2, y2 in @collisions
        if x1 <= x and x <= x2 and y1 <= y and y <= y2
          Logging::Logging.debug(part + ' touched')
          return part
        end
      end
      return ''
    end

    def __get_with_scaling(name)
      basename = ['surface', @surface_id].join('')
      path, config = @surface_info[basename]
      value = config.get(name)
      unless value.nil?
        scale = get_scale
        value = (value.to_f * scale / 100)
      end
      return value
    end

    def get_center
      centerx = __get_with_scaling('point.centerx')
      centery = __get_with_scaling('point.centery')
      unless centerx.nil?
        centerx = centerx.to_i
      end
      unless centery.nil?
        centery = centery.to_i
      end
      return centerx, centery
    end

    def get_kinoko_center
      centerx = __get_with_scaling('point.kinoko.centerx')
      centery = __get_with_scaling('point.kinoko.centery')
      unless centerx.nil?
        centerx = centerx.to_i
      end
      unless centery.nil?
        centery = centery.to_i
      end
      return centerx, centery
    end

    def set_position(x, y)
      return if @parent.handle_request('GET', 'lock_repaint')
      @position = [x, y]
      new_x, new_y = get_position()
      @window.move(new_x, new_y)
      left, top, scrn_w, scrn_h = @window.workarea
      if x > (left + scrn_w / 2)
        new_direction = 0
      else
        new_direction = 1
      end
      @__direction = new_direction
      ox, oy = get_balloon_offset # without scaling
      scale = get_scale
      ox = (ox * scale / 100).to_i
      oy = (oy * scale / 100).to_i
      if new_direction.zero? # left
        base_x = (new_x + ox)
      else
        w, h = get_surface_size()
        base_x = (new_x + w - ox)
      end
      base_y = (new_y + oy)
      @parent.handle_request(
        'NOTIFY', 'set_balloon_position', @side, base_x, base_y)
      @parent.handle_request('NOTIFY', 'notify_observer', 'set position')
      @parent.handle_request('NOTIFY', 'check_mikire_kasanari')
    end

    def get_position ## FIXME: position with offset(property)
      @position.zip(@window_offset).map {|x, y| x + y }
    end

    def set_alignment_current
      set_alignment(get_alignment())
    end

    def set_alignment(align)
      @align = align if [0, 1, 2].include?(align)
      return if @dragged # XXX: position will be reset after button release event
      case align
      when 0
        left, top, scrn_w, scrn_h = @window.workarea
        sw, sh = get_max_size()
        sx, sy = @position # XXX: without window_offset
        sy = (top + scrn_h - sh)
        set_position(sx, sy)
      when 1
        left, top, scrn_w, scrn_h = @window.workarea
        sx, sy = @position # XXX: without window_offset
        sy = top
        set_position(sx, sy)
      else # free
        #pass
      end
    end

    def get_alignment
      @align
    end

    def destroy
      @seriko.destroy()
      @window.destroy()
    end

    def is_shown
      @__shown
    end

    def show
      return if @parent.handle_request('GET', 'lock_repaint')
      return if @__shown
      @__shown = true
      x, y = get_position()
      @window.move(x, y) # XXX: call before showing the window
      @window.show()
      @parent.handle_request('NOTIFY', 'notify_observer', 'show', :args => [@side])
      @parent.handle_request('NOTIFY', 'notify_observer', 'raise', :args => [@side])
    end

    def hide
      return unless @__shown
      @window.hide()
      @__shown = false
      @parent.handle_request(
        'NOTIFY', 'notify_observer', 'hide', :args => [@side])
    end

    def raise
      @window.window.raise
      @parent.handle_request('NOTIFY', 'notify_observer', 'raise', :args => [@side])
    end

    def lower
      @window.window.lower()
      @parent.handle_request('NOTIFY', 'notify_observer', 'lower', :args => [@side])
    end

    def button_press(window, event)
      @parent.handle_request('NOTIFY', 'reset_idle_time')
      x, y = @window.winpos_to_surfacepos(
           event.x.to_i, event.y.to_i, get_scale)
      @x_root = event.x_root
      @y_root = event.y_root
      # automagical raise
      @parent.handle_request('NOTIFY', 'notify_observer', 'raise', :args => [@side])
      if event.event_type == Gdk::EventType::BUTTON2_PRESS
        @click_count = 2
      else # XXX
        @click_count = 1
      end
      if [1, 2, 3].include?(event.button)
        num_button = [0, 2, 1][event.button - 1]
        @parent.handle_request('NOTIFY', 'notify_event', 'OnMouseDown',
                               x, y, 0, @side, @__current_part,
                               num_button,
                               'mouse') # FIXME
      end
      if [2, 8, 9].include?(event.button)
        ex_button = {
          2 => 'middle',
          8 => 'xbutton1',
          9 => 'xbutton2'
        }[event.button]
        @parent.handle_request('NOTIFY', 'notify_event', 'OnMouseDownEx',
                               x, y, 0, @side, @__current_part,
                               ex_button,
                               'mouse') # FIXME
      end
      return true
    end

    CURSOR_HAND1 = Gdk::Cursor.new(Gdk::CursorType::HAND1)

    def button_release(window, event)
      x, y = @window.winpos_to_surfacepos(
           event.x.to_i, event.y.to_i, get_scale)
      if @dragged
        @dragged = false
        set_alignment_current()
        @parent.handle_request(
          'NOTIFY', 'notify_event',
          'OnMouseDragEnd', x, y, '', @side, @__current_part, '')
      end
      @x_root = nil
      @y_root = nil
      if @click_count > 0
        @parent.handle_request('NOTIFY', 'notify_surface_click',
                               event.button, @click_count,
                               @side, x, y)
        @click_count = 0
      end
      return true
    end

    def motion_notify(darea, event)
      x, y, state = event.x, event.y, event.state
      x, y = @window.winpos_to_surfacepos(x, y, get_scale)
      part = get_touched_region(x, y)
      if part != @__current_part
        if part == ''
          @window.set_tooltip_text('')
          @darea.window.set_cursor(nil)
          @parent.handle_request(
            'NOTIFY', 'notify_event',
            'OnMouseLeave', x, y, '', @side, @__current_part)
        else
          if @tooltips.include?(part)
            tooltip = @tooltips[part]
            @window.set_tooltip_text(tooltip)
          else
            @window.set_tooltip_text('')
          end
          @darea.window.set_cursor(CURSOR_HAND1)
          @parent.handle_request(
            'NOTIFY', 'notify_event',
            'OnMouseEnter', x, y, '', @side, part)
        end
      end
      @__current_part = part
      unless @parent.handle_request('GET', 'busy')
        if (state & Gdk::ModifierType::BUTTON1_MASK).nonzero?
          unless @x_root.nil? or @y_root.nil?
            unless @dragged
              @parent.handle_request(
                'NOTIFY', 'notify_event',
                'OnMouseDragStart', x, y, '',
                @side, @__current_part, '')
            end
            @dragged = true
            x_delta = (event.x_root - @x_root).to_i
            y_delta = (event.y_root - @y_root).to_i
            x, y = @position # XXX: without window_offset
            set_position(x + x_delta, y + y_delta)
            @x_root = event.x_root
            @y_root = event.y_root
          end
        elsif (state & Gdk::ModifierType::BUTTON2_MASK).nonzero? or \
             (state & Gdk::ModifierType::BUTTON3_MASK).nonzero?
          #pass
        else
          @parent.handle_request('NOTIFY', 'notify_surface_mouse_motion',
                                 @side, x, y, part)
        end
      end
      if event.is_hint == 1
        Gdk::Event.request_motions(event)
      end
      return true
    end

    def scroll(darea, event)
      x, y = @window.winpos_to_surfacepos(
           event.x.to_i, event.y.to_i, get_scale)
      case event.direction
      when Gdk::ScrollDirection::UP
        count = 1
      when Gdk::ScrollDirection::DOWN
        count = -1
      else
        count = 0
      end
      unless count.zero?
        part = get_touched_region(x, y)
        @parent.handle_request('NOTIFY', 'notify_event',
                               'OnMouseWheel', x, y, count, @side, part)
      end
      return true
    end

    def toggle_bind(bind_id)
      if @bind.include?(bind_id)
        current = @bind[bind_id][1]
        @bind[bind_id][1] = (not current)
        group = @bind[bind_id][0].split(',', 2)
        if @bind[bind_id][1]
          @parent.handle_request('NOTIFY', 'notify_event',
                                 'OnDressupChanged', @side,
                                 group[1],
                                 1,
                                 group[0])
        else
          @parent.handle_request('NOTIFY', 'notify_event',
                                 'OnDressupChanged', @side,
                                 group[1],
                                 0,
                                 group[0])
        end
        reset_surface()
      end
    end

    def window_enter_notify(window, event)
      x, y, state = event.x, event.y, event.state
      x, y = @window.winpos_to_surfacepos(x, y, get_scale)
      @parent.handle_request('NOTIFY', 'notify_event',
                             'OnMouseEnterAll', x, y, '', @side, '')
    end

    def window_leave_notify(window, event)
      x, y, state = event.x, event.y, event.state
      x, y = @window.winpos_to_surfacepos(x, y, get_scale)
      if @__current_part != '' # XXX
        @parent.handle_request(
          'NOTIFY', 'notify_event',
          'OnMouseLeave', x, y, '', @side, @__current_part)
        @__current_part = ''
      end
      @parent.handle_request(
        'NOTIFY', 'notify_event',
        'OnMouseLeaveAll', x, y, '', @side, '')
      return true
    end
  end
end
