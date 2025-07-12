# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#  Copyright (C) 2024, 2025 by Tatakinov
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
require_relative "metamagic"
require_relative "logging"

module Surface

  class Surface < MetaMagic::Holon
    attr_reader :name, :prefix, :window

    def initialize
      super("") # FIXME
      @window = {}
      @desc = nil
      @mikire = 0
      @kasanari = 0
      @key_press_count = 0
      @handlers = {
        'stick_window' => 'window_stick',
      }
    end

    def finalize
      for surface_window in @window.values
        surface_window.destroy
      end
      @window = {}
    end

    def create_gtk_window(title)
      window = Pix::TransparentWindow.new()
      window.set_title(title)
      window.signal_connect('delete_event') do |w, e|
        next delete(w, e)
      end
      window.signal_connect('window_state_event') do |w, e|
        window_state(w, e)
        next true
      end
      key_controller = Gtk::EventControllerKey.new(window)
      key_controller.signal_connect('key-pressed') do |ctrl, keyval, keycode, state|
        next key_press(ctrl.widget, ctrl, keyval, keycode, state)
      end
      key_controller.signal_connect('key-released') do |ctrl, keyval, keycode, state|
        next key_release(ctrl.widget, ctrl, keyval, keycode, state)
      end
      window.realize()
      return window
    end

    def identify_window(win)
      for surface_window in @window.values
        return true if win == surface_window.get_window.window
      end
      return false
    end

    def window_stayontop(flag)
      for surface_window in @window.values
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
        for surface_window in @window.values
          gtk_window = surface_window.get_window
          if gtk_window != window and \
            (gtk_window.window.state & \
             Gdk::WindowState::ICONIFIED).nonzero?
            gtk_window.iconify()
          end
        end
      else
        for surface_window in @window.values
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

    def key_press(window, event, keyval, keycode, state)
      name = Keymap::Keymap_old[keyval]
      keycode = Keymap::Keymap_new[keyval]
      @key_press_count += 1
      if (state & \
          (Gdk::ModifierType::CONTROL_MASK | \
           Gdk::ModifierType::SHIFT_MASK)).nonzero?
        if name == 'f12'
          Logging::Logging.info('reset surface position')
          reset_position()
        end
        if name == 'f10'
          Logging::Logging.info('reset balloon offset')
          for side in @window.keys
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

    def key_release(window, event, keyval, keycode, state)
      @key_press_count = 0
      return true
    end

    def window_stick(stick)
      for window in @window.values
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
      @surface_alias = surface_alias
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
        unless File.exist?(path)
          name = File.basename(path, ".*")
          ext = File.extname(path)
          dgp_path = [name, '.dgp'].join('')
          unless File.exist?(dgp_path)
            ddp_path = [name, '.ddp'].join('')
            unless File.exist?(ddp_path)
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
          buf << [values[4].strip, 'polygon', [x1, y1, x1, y2, x2, y2, x2, y1]]
        end
        for n in 0..255
          # "redo" syntax
          rect = config.get(['collisionex', n.to_s].join(''))
          next if rect.nil?
          values = rect.split(',', 0)
          id = values.shift.strip
          type = values.shift
          begin
            case type
            when 'rect'
              m = values.map do |e|
                Integer(e)
              end
              unless m.length == 4
                next
              end
              buf << [id, 'polygon', [m[0], m[1], m[0], m[3], m[2], m[3], m[2], m[1]]]
            when 'ellipse'
              m = values.map do |e|
                Integer(e)
              end
              unless m.length == 4
                next
              end
              buf << [id, type, m]
            when 'circle'
              m = values.map do |e|
                Integer(e)
              end
              unless m.length == 3
                next
              end
              buf << [id, type, m]
            when 'polygon'
              m = values.map do |e|
                Integer(e)
              end
              unless m.length > 4 and m.length % 2 == 0
                next
              end
              buf << [id, type, m]
            when 'region'
              # TODO stub
            end
          rescue
            next
          end
        end
=begin
# 使われてない?
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
=end
        region[key] = buf
      end
      @__region = region
      # MAYUNA
      @__mayuna = {}
      for basename in surface.keys
        path, config = surface[basename]
        match = RE_SURFACE_ID.match(basename)
        next if match.nil?
        key = match[1]
        # define animation patterns
        @__mayuna[key] = Seriko.get_mayuna(config)
      end
      @mayuna = {}
      # create surface windows
      for surface_window in @window.values
        surface_window.destroy()
      end
      @window = Hash.new do |hash, key|
        add_window(key, default_kero, :config_alias => @surface_alias, :mayuna => @__mayuna)
      end
      @__surface = surface
      @maxsize = [maxwidth, maxheight]
      add_window(0, default_sakura, :config_alias => @surface_alias, :mayuna => @__mayuna)
      add_window(1, default_kero, :config_alias => @surface_alias, :mayuna => @__mayuna)
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
      fontcolor_r = @desc.get('menu.background.font.color.r', :default => -1).to_i
      fontcolor_g = @desc.get('menu.background.font.color.g', :default => -1).to_i
      fontcolor_b = @desc.get('menu.background.font.color.b', :default => -1).to_i
      if fontcolor_r == -1 || fontcolor_g == -1 || fontcolor_b == -1
        background = [-1, -1, -1]
      else
        fontcolor_r = [0, [255, fontcolor_r].min].max
        fontcolor_g = [0, [255, fontcolor_g].min].max
        fontcolor_b = [0, [255, fontcolor_b].min].max
        background = [fontcolor_r, fontcolor_g, fontcolor_b]
      end
      fontcolor_r = @desc.get('menu.foreground.font.color.r', :default => -1).to_i
      fontcolor_g = @desc.get('menu.foreground.font.color.g', :default => -1).to_i
      fontcolor_b = @desc.get('menu.foreground.font.color.b', :default => -1).to_i
      if fontcolor_r == -1 || fontcolor_g == -1 || fontcolor_b == -1
        foreground = [-1, -1, -1]
      else
        fontcolor_r = [0, [255, fontcolor_r].min].max
        fontcolor_g = [0, [255, fontcolor_g].min].max
        fontcolor_b = [0, [255, fontcolor_b].min].max
        foreground = [fontcolor_r, fontcolor_g, fontcolor_b]
      end
      return background, foreground
    end

    def add_window(side, default_id, config_alias: nil, mayuna: {})
      return if @window.include?(side)
      case side
      when 0
        name = 'sakura'
        title = @parent.handle_request('GET', 'get_selfname') or \
        "surface.#{name}"
      when 1
        name = 'kero'
        title = @parent.handle_request('GET', 'get_keroname') or \
        "surface.#{name}"
      else
        name = ("char#{side}")
        title = "surface.#{name}"
      end
      if config_alias.nil?
        surface_alias = nil
      else
        surface_alias = config_alias.get("#{name}.surface.alias")
      end
      # MAYUNA
      bind = {}
      for index in @desc.each_group(name)
        group = @desc.get(
          "#{name}.bindgroup#{index}.name", default: nil)
        default = @desc.get(
          "#{name}.bindgroup#{index}.default", default: '0')
        bind[index] = [group, (default != '0'), []] unless group.nil?
      end
      for index in @desc.each_option(name)
        option = @desc.get(
          "#{name}.bindoption#{index}.group", default: nil)
        unless option.nil?
          category, option = option.split(',', 2)
          option = option.split('+')
          must_select = option.include?('mustselect')
          for b in bind
            group, default, _ = b
            if group[0] == category
              b[2] = option
            end
          end
        end
      end
      @mayuna[name] = []
      for index in @desc.each_menuitem(name)
        key = @desc.get("#{name}.menuitem#{index}", :default => nil)
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
              @mayuna[name] << [key, group[1], bind[key][1], bind[key][2]]
            end
          end
        end
      end
      gtk_window = create_gtk_window(title)
      seriko = get_seriko(@__surface)
      tooltips = {}
      if @__tooltips.include?(name)
        tooltips = @__tooltips[name]
      end
      if default_id.nil?
        # FIXME
        default_id = 10
      end
      surface_window = SurfaceWindow.new(
        gtk_window, side, @desc, surface_alias, @__surface, tooltips,
        @__surfaces, seriko, @__region, mayuna, bind,
        default_id, @maxsize)
      surface_window.set_responsible(self)
      @window[side] = surface_window
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
          filename = filename.downcase.gsub('\\', '/')
        rescue
          error = ('invalid element spec for ' + key + ': ' + config[key])
          break
        end
        basename = File.basename(filename, ".*")
        ext = File.extname(filename)
        ext = ext.downcase
        id = Home.filename_to_surface_id(filename)
        unless ['.png', '.dgp', '.ddp'].include?(ext)
          error = ('unsupported file format for ' + key + ': ' + filename)
          break
        end
        unless elements.include?(id)
          error = (key + ' file not found: ' + filename)
          break
        end
        surface = elements[id][0]
        if n.zero? # base surface
          surface_list = [surface]
        elsif ['overlay', 'overlayfast', 'overlaymultiply',
               'interpolate', 'reduce', 'replace', 'asis'].include?(method)
          if ['overlaymultiply'].include?(method)
            Logging::Logging.warning('overlaymultiply is not supported. fallback to overlayfast')
          end
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
      return @window[side].get_window
    end

    def reset_surface
      @window.each do |k, v|
        v.reset_surface
      end
    end

    def set_surface_default(side)
      if side.nil?
        for side in @window.keys
          @window[side].set_surface_default()
        end
      elsif 0 <= side
        @window[side].set_surface_default()
      end
    end

    def set_surface(side, surface_id)
      @window[side].set_surface(surface_id)
    end

    def get_surface(side)
      return @window[side].get_surface()
    end

    def get_max_size(side)
      return @window[side].get_max_size()
    end

    def get_surface_size(side)
      return @window[side].get_surface_size()
    end

    def get_surface_offset(side)
      return @window[side].get_surface_offset()
    end

    def get_touched_region(side, x, y)
      return @window[side].get_touched_region(x, y)
    end

    def get_center(side)
      return @window[side].get_center()
    end

    def get_kinoko_center(side)
      return @window[side].get_kinoko_center()
    end

    def reset_balloon_position
      for side in @window.keys
        x, y = get_position(side)
        direction = @window[side].direction
        ox, oy = get_balloon_offset(side)
        @parent.handle_request(
          'NOTIFY', 'set_balloon_direction', side, direction)
        if direction.zero? # left
          base_x = (x + ox)
        else
          sw, sh = get_surface_size(side)
          bw, bh = @parent.handle_request(
              'GET', 'get_balloon_size', side)
          base_x = (x + sw + bw - ox)
        end
        base_y = (y + oy)
        @parent.handle_request(
          'NOTIFY', 'set_balloon_position', side, base_x, base_y)
      end
    end

    def reset_position
      left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
      s0x, s0y, s0w, s0h = 0, 0, 0, 0 # XXX
      for side in @window.keys
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

    def set_position(side, x, y)
      @window[side].set_position(x, y)
    end

    def get_position(side)
      return @window[side].get_position()
    end

    def set_alignment_current
      for side in @window.keys
        @window[side].set_alignment_current()
      end
    end

    def set_alignment(side, align)
      @window[side].set_alignment(align)
    end

    def get_alignment(side)
      return @window[side].get_alignment()
    end

    def reset_alignment
      if @desc.get('seriko.alignmenttodesktop') == 'free'
        align = 2
      else
        align = 0
      end
      for side in @window.keys
        case side
        when 0
          key = 'sakura.seriko.alignmenttodesktop'
        when 1
          key = 'kero.seriko.alignmenttodesktop'
        else
          key = "char#{side}.seriko.alignmenttodesktop"
        end
        case @desc.get(key)
        when 'bottom'
          align = 0
        when 'top'
          align = 1
        when 'free'
          align = 2
        else
          # nop
        end
        set_alignment(side, align)
      end
    end

    def is_shown(side)
      return @window[side].is_shown()
    end

    def show(side)
      @window[side].show()
    end

    def hide_all
      for side in @window.keys
        @window[side].hide()
      end
    end

    def hide(side)
      @window[side].hide()
    end

    def raise_all
      for side in @window.keys
        @window[side].raise
      end
    end

    def raise(side)
      @window[side].raise
    end

    def lower_all
      for side in @window.keys
        @window[side].lower()
      end
    end

    def lower(side)
      @window[side].lower()
    end

    def invoke(side, actor_id)
      @window[side].invoke(actor_id)
    end

    def invoke_yen_e(side, surface_id)
      @window[side].invoke_yen_e(surface_id)
    end

    def invoke_talk(side, surface_id, count)
      return @window[side].invoke_talk(surface_id, count)
    end

    def set_icon(path)
      return if path.nil? or not File.exist?(path)
      for window in @window.values
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
      x, y = @window[side].get_balloon_offset
      scale = @window[side].get_scale
      x = (x * scale / 100).to_i
      y = (y * scale / 100).to_i
      return x, y
    end

    def set_balloon_offset(side, offset)
      @window[side].balloon_offset = offset
    end

    def toggle_bind(args)
      side, bind_id = args
      @window[side].toggle_bind(bind_id)
    end

    def get_collision_area(side, part)
      return @window[side].get_collision_area(part)
    end

    def is_playing_animation(side, actor_id)
      @window[side].is_playing_animation(actor_id)
    end

    def change_animation_state(side, actor_id, state, *args)
      @window[side].change_animation_state(actor_id, state, *args)
    end

    def check_mikire_kasanari
      unless is_shown(0)
        @mikire = @kasanari = 0
        return
      end
      left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
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

  class SurfaceWindow < MetaMagic::Holon
    attr_reader :bind

    def initialize(window, side, desc, surface_alias, surface_info, tooltips,
                   surfaces, seriko, region, mayuna, bind, default_id, maxsize)
      super("") # FIXME
      @handlers = {}
      @window = window
      @maxsize = maxsize
      @side = side
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
      @reshape = true
      @pix_cache = Pix::Cache.new
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
      @darea.signal_connect('size-allocate') do |w, allocation, data|
        # XXX DrawingAreaのsizeが変わったらreshapeしないと
        # マウスやキーボードのイベントを拾わない。
        @reshape = true
        next false
      end
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
      @darea.drag_dest_set(Gtk::DestDefaults::ALL, dnd_targets,
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
      @reshape = true # XXX
      @parent.handle_request('NOTIFY', 'reset_position') # XXX
      left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
      @parent.handle_request(
        'NOTIFY', 'notify_event', 'OnDisplayChange',
        Gdk.Visual.get_best_depth(), scrn_w, scrn_h)
    end

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
        if uri_parsed.scheme == 'file' and File.exist?(pathname)
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

    def is_playing_animation(actor_id)
      @seriko.is_playing_animation(actor_id)
    end

    def change_animation_state(actor_id, state, *args)
      case state
      when :clear
        @seriko.clear_animation(actor_id)
      when :pause
        @seriko.pause_animation(actor_id)
      when :resume
        @seriko.resume_animation(actor_id)
      when :offset
        x, y = *args
        @seriko.offset_animation(actor_id, x, y)
      end
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
      @reshape = true
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
        left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
        y = (top + scrn_h - dh)
      when 1
        yoffset = 0
      else
        yoffset = ((dh - h) / 2)
      end
      @window_offset = [xoffset, yoffset]
      @seriko.start(self, @bind)
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
        when 'overlay', 'overlayfast', 'overlaymultiply', 'replace'
          if @surfaces.include?(surface_id)
            if ['overlaymultiply'].include?(method)
              Logging::Logging.warning('overlaymultiply is not supported. fallback to overlayfast')
            end
            dest_x, dest_y = args
            mayuna_list << [method, surface_id, dest_x, dest_y]
          end
        when 'interpolate', 'asis', 'bind', 'add', 'reduce'
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
          fail RuntimeError, 'unreachable'
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
        pix = @pix_cache.load(@surfaces[surface_id][0], is_pnr: is_pnr, use_pna: use_pna)
      rescue
        Logging::Logging.debug('cannot load surface #' + surface_id.to_s)
        return Pix::Data.new(Pix.create_blank_surface(100, 100), Cairo::Region.new)
      end
      surface = Pix.create_blank_surface(pix.surface.width, pix.surface.height)
      Cairo::Context.new(surface) do |cr|
        cr.set_operator(Cairo::OPERATOR_SOURCE)
        cr.set_source(pix.surface, 0, 0)
        cr.paint()
      end
      region = Cairo::Region.new
      region.union!(pix.region)
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
          overlay_pix = @pix_cache.load(element, is_pnr: is_pnr, use_pna: use_pna)
        rescue
          next
        end
        Cairo::Context.new(surface) do |cr|
          op = {
            'base' =>            Cairo::OPERATOR_SOURCE, # XXX
            'overlay' =>         Cairo::OPERATOR_OVER,
            'overlayfast' =>     Cairo::OPERATOR_ATOP,
            'overlaymultiply' => Cairo::OPERATOR_ATOP, # FIXME
            'interpolate' =>     Cairo::OPERATOR_SATURATE,
            'reduce' =>          Cairo::OPERATOR_DEST_IN,
            'replace' =>         Cairo::OPERATOR_SOURCE,
            'asis' =>            Cairo::OPERATOR_OVER,
          }[method]
          cr.set_operator(op)
          cr.set_source(overlay_pix.surface, x, y)
          if ['overlay', 'overlayfast', 'overlaymultiply', 'interpolate'].include?(method)
            cr.mask(overlay_pix.surface, x, y)
          else
            cr.paint()
          end
        end
        # TODO
        # method毎のregion処理
        overlay_pix.region.translate!(x, y)
        region.union!(overlay_pix.region)
      end
      return Pix::Data.new(surface, region)
    end

    def get_image_surface(surface_id, is_asis: false)
      unless @surfaces.include?(surface_id)
        Logging::Logging.debug('cannot load surface #' + surface_id.to_s)
        return Pix::Data.new(Pix.create_blank_surface(*@window.size), Cairo::Region.new)
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
=begin
# FIXME stub
      for part, type, c in @collisions
        unless @parent.handle_request('GET', 'get_preference',
                                      'check_collision_name').zero?
          cr.set_operator(Cairo::OPERATOR_SOURCE)
          cr.set_source_rgba(0.4, 0.0, 0.0, 1.0) # XXX
          cr.move_to(x1 + 2, y1)
          font_desc = Pango::FontDescription.new
          font_desc.set_size(8 * Pango::SCALE)
          layout = cr.create_pango_layout
          layout.set_font_description(font_desc)
          layout.set_wrap(Pango::WrapMode::CHAR)
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
=end
      cr.restore()
    end

    def create_image_surface(surface_id, done = [], is_asis: false)
      if surface_id.nil?
        surface_id = @surface_id
      end
      if @mayuna.include?(surface_id) and @mayuna[surface_id]
        pix = get_image_surface(surface_id, is_asis: is_asis)
        surface_width = pix.surface.width
        surface_height = pix.surface.height
        for actor in @mayuna[surface_id]
          actor_id = actor.get_id()
          if @bind.include?(actor_id) and @bind[actor_id][1] and \
            not done.include?(actor_id)
            done << actor_id
            for method, mayuna_id, dest_x, dest_y in iter_mayuna(surface_width, surface_height, actor, done)
              mayuna_overlay_pix = create_image_surface(mayuna_id, done, is_asis: method == 'asis')
              Cairo::Context.new(pix.surface) do |cr|
                op = {
                  'base' =>            Cairo::OPERATOR_SOURCE, # XXX
                  'overlay' =>         Cairo::OPERATOR_OVER,
                  'overlayfast' =>     Cairo::OPERATOR_ATOP,
                  'overlaymultiply' => Cairo::OPERATOR_ATOP, # FIXME
                  'replace' =>         Cairo::OPERATOR_SOURCE,
                  'interpolate' =>     Cairo::OPERATOR_SATURATE,
                  'asis' =>            Cairo::OPERATOR_OVER,
                  'bind' =>            Cairo::OPERATOR_OVER,
                  'add' =>             Cairo::OPERATOR_OVER,
                  'reduce' =>          Cairo::OPERATOR_DEST_IN,
                }[method]
                cr.set_operator(op)
                cr.set_source(mayuna_overlay_pix.surface, dest_x, dest_y)
                if ['overlay', 'bind', 'add', 'overlayfast', 'overlaymultiply', 'interpolate'].include?(method)
                  cr.mask(mayuna_overlay_pix.surface, dest_x, dest_y)
                elsif ['replace', 'asis', 'reduce'].include?(method)
                  cr.paint()
                else
                  fail RuntimeError('should not reach here')
                end
              end
              # TODO
              # method毎のregion処理
              mayuna_overlay_pix.region.translate!(dest_x, dest_y)
              pix.region.union!(mayuna_overlay_pix.region)
            end
          end
        end
      else
        pix = get_image_surface(surface_id)
      end
      return pix
    end

    def update_frame_buffer
      return if @parent.handle_request('GET', 'lock_repaint')
      @reshape = true # FIXME: depends on Seriko
      new_pix = create_image_surface(@seriko.get_base_id)
      fail "assert" if new_pix.nil?
      region = Cairo::Region.new
      region.union!(new_pix.region)
      # update collision areas
      @collisions = @region[@seriko.get_base_id]
      # draw overlays
      for surface_id, x, y, method in @seriko.iter_overlays()
        begin
          overlay_pix = create_image_surface(
            surface_id, :is_asis => (method == 'asis'))
        rescue
          next
        end
        # overlay surface
        Cairo::Context.new(new_pix.surface) do |cr|
          op = {
            'base' =>        Cairo::OPERATOR_SOURCE, # XXX
            'overlay' =>     Cairo::OPERATOR_OVER,
            'bind' =>        Cairo::OPERATOR_OVER,
            'add' =>         Cairo::OPERATOR_OVER,
            'overlayfast' => Cairo::OPERATOR_ATOP,
            'interpolate' => Cairo::OPERATOR_SATURATE,
            'reduce' =>      Cairo::OPERATOR_DEST_IN,
            'replace' =>     Cairo::OPERATOR_SOURCE,
            'asis' =>        Cairo::OPERATOR_OVER,
          }[method]
          cr.set_operator(op)
          cr.set_source(overlay_pix.surface, x, y)
          if ['overlay', 'overlayfast'].include?(method)
            cr.mask(overlay_pix.surface, x, y)
          else
            cr.paint()
          end
        end
        # TODO
        # method毎のregion処理
        overlay_pix.region.translate!(x, y)
        region.union!(overlay_pix.region)
      end
      @image_surface = Pix::Data.new(new_pix.surface, region)
      @window.queue_draw(@image_surface.region)
    end

    def redraw(darea, cr)
      return if @image_surface.nil? # XXX
      @window.set_surface(cr, @image_surface.surface, get_scale, @reshape)
      unless @parent.handle_request('GET', 'get_preference', 'check_collision').zero?
        draw_region(cr)
      end
      @window.set_shape(cr, @reshape, @image_surface.region)
      @reshape = false
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
      for p, type, c in @collisions
=begin
# FIXME stub
        if p == part
          scale = get_scale
          x1 = (x1 * scale / 100).to_i
          x2 = (x2 * scale / 100).to_i
          y1 = (y1 * scale / 100).to_i
          y2 = (y2 * scale / 100).to_i
          return x1, y1, x2, y2
        end
=end
      end
      return nil
    end

    def get_surface
      @surface_id
    end

    def get_max_size
      left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
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
      for part, type, c in @collisions
        case type
        when 'circle'
          cx, cy, cr = c
          if (cx - x) * (cx - x) + (cy - y) * (cy - y) <= cr * cr
            Logging::Logging.debug(part + ' touched')
            return part
          end
        when 'ellipse'
          x1, y1, x2, y2 = c
          xr = (x1 - x2).abs
          xo = (x1 + x2) / 2
          yr = (y1 - y2).abs
          yo = (y1 + y2) / 2
          if ((xo - x) * (xo - x) / (xr * xr)) + ((yo - y) * (yo - y) / (yr * yr)) <= 1
            Logging::Logging.debug(part + ' touched')
            return part
          end
        when 'polygon'
          func = proc do |f, output, x1, y1, x2, y2, *args|
            output << [x1, y1, x2, y2]
            unless args.empty?
              f.call(f, output, x2, y2, *args)
            end
          end
          lines = []
          func.call(func, lines, *c, c[0], c[1])
          count = 0
          for line in lines
            if line[1] == line[3]
              next
            end
            if line[1] > line[3]
              if y == line[1]
                next
              elsif y == line[3] and x <= line[2]
                count += 1
                next
              end
            else
              if y == line[1] and x < line[0]
                count += 1
                next
              elsif y == line[3]
                next
              end
            end
            if y < [line[1], line[3]].min
              next
            elsif y > [line[1], line[3]].max
              next
            end
            intersection_x = line[0] + (y - line[1]) * (line[2] - line[0]) / (line[3] - line[1])
            if intersection_x > x
              count += 1
            end
          end
          if count % 2 == 1
            Logging::Logging.debug(part + ' touched')
            return part
          end
        when 'region'
          # TODO stub
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
      left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
      ox, oy = get_balloon_offset # without scaling
      scale = get_scale
      ox = (ox * scale / 100).to_i
      oy = (oy * scale / 100).to_i
      bw, bh = @parent.handle_request(
          'GET', 'get_balloon_size', @side)
      sw, sh = get_surface_size()
      if @__direction.zero? # left
        if new_x - bw + ox < 0
          new_direction = 1
        else
          new_direction = 0
        end
      else
        if new_x + sw + bw - ox > scrn_w
          new_direction = 0
        else
          new_direction = 1
        end
      end
      @__direction = new_direction
      @parent.handle_request(
        'NOTIFY', 'set_balloon_direction', @side, direction)
      if new_direction.zero? # left
        base_x = (new_x - bw + ox)
      else
        base_x = (new_x + sw - ox)
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
        left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
        sw, sh = get_max_size()
        sx, sy = @position # XXX: without window_offset
        sy = (top + scrn_h - sh)
        set_position(sx, sy)
      when 1
        left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
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
      @reshape = true
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
      Gdk::Event.request_motions(event) if event.is_hint == 1
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
