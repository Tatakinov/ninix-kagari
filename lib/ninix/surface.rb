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

require "gtk4"
require 'open3'

require_relative "keymap"
require_relative "pix"
require_relative "seriko"
require_relative "metamagic"
require_relative "logging"
require_relative 'cache'
require_relative 'version'

module Surface

  class SurfaceProxy < MetaMagic::Holon
    def initialize
      super("")
      @internal = Surface.new
      @internal.set_responsible(self)
      @external = Ayu.new
      @external.set_responsible(self)
      @current = @internal
    end

    def new_(desc, *args)
      ayu = desc.get('ayu')
      if ayu.nil?
        @current = @internal
      else
        @current = @external
      end
      @current.new_(desc, *args)
    end

    def set_responsible(parent)
      @parent = parent
    end

    def respond_to_missing?(symbol, include_private)
      @current.class.method_defined?(symbol)
    end

    def method_missing(name, *args)
      #p [:missing, name, *args]
      @current.send(name, *args)
    end
  end

  class Ayu
    def initialize
    end

    def new_(desc, surface_alias, surface, name, surface_dir, tooltips, seriko_descript, default_sakura, default_kero)
      @desc = desc
      @ayu = desc.get('ayu')
      fail if @ayu.nil?
      if ENV['AYU_PATH'].nil?
        command = @ayu
      else
        command = File.join(ENV['AYU_PATH'], @ayu)
      end
      begin
        @ayu_write, @ayu_read, @ayu_err, @ayu_thread = Open3.popen3(command)
      rescue
        # TODO error
        p command
        p e
        return
      end
      send_event('Initialize', File.join(surface_dir, ''))
      send_event('BasewareVersion', 'ninix', Version.NUMBER)
      send_event('Endpoint', *@parent.handle_request(:GET, :endpoint))
      info = []
      char = Regexp.new(/^char\d+/)
      char_menu = Regexp.new(/^char\d+\.menu/)
      @desc.each do |k, v|
        if k.start_with?('seriko')
          info << [k, v].join(',')
        elsif k.start_with?('sakura') and not k.start_with?('sakura.menu')
          info << [k, v].join(',')
        elsif k.start_with?('kero') and not k.start_with?('kero.menu')
          info << [k, v].join(',')
        elsif k =~ char and not k =~ char_menu
          info << [k, v].join(',')
        end
      end
      send_event('UpdateInfo', info.size, *info)
      reset_surface
    end

    def is_internal
      false
    end

    def set_responsible(parent)
      @parent = parent
    end

    def send_event(event, *args, method: 'NOTIFY')
      request = [
        "#{method} AYU/0.9",
        'Charset: UTF-8',
        "Command: #{event}",
      ].join("\r\n")
      args.each_with_index do |v, i|
        request = [request, "Argument#{i}: #{v}"].join("\r\n")
      end
      request = [request, "\r\n\r\n"].join
      request = [[request.bytesize].pack('L'), request.force_encoding(Encoding::BINARY)].join
      @ayu_write.write(request)
      len = nil
      begin
        len = @ayu_read.read(4)&.unpack('L').first
      end
      if len.nil?
        # TODO error
        return
      end
      response = @ayu_read.read(len)
      #p [:debug, request, response]
      iss = StringIO.new(response, 'r')
      protocol, code, status = iss.readline.split(' ', 3)
      headers = {}
      iss.each_line do |line|
        k, sep, v = line.partition(': ')
        next if sep != ': '
        headers[k] = v
      end
      return {proto: protocol, code: code.to_i, status: status, headers: headers}
    end

    def get_info(key)
      # TODO seriko.alignmenttodesktop系のSSP準拠
      @desc.get(key, fallback: true)
    end

    def add_window(side, default)
      send_event('Create', side)
    end

    def set_icon(path)
    end

    def get_balloon_offset(side, scaling)
      response = send_event('GetBalloonOffset', side, method: 'GET')
      headers = response[:headers]
      unless headers.include?('Value0') and headers.include?('Value1')
        return [0, 0]
      end
      x = headers['Value0'].to_i
      y = headers['Value1'].to_i
      return [x, y]
    end

    def set_balloon_offset(side, offset)
      send_event('SetBalloonOffset', side, *offset)
    end

    def get_surface_size(side)
      response = send_event('Size', side, method: 'GET')
      headers = response[:headers]
      unless headers.include?('Value0') and headers.include?('Value1')
        return [0, 0]
      end
      x = headers['Value0'].to_i
      y = headers['Value1'].to_i
      return [x, y]
    end

    def reset_surface
      scale = @parent.handle_request(:GET, :get_preference, 'surface_scale')
      if scale != @scale
        @scale = scale
        send_event('Scale', @scale)
      end
    end

    def get_position(side)
      response = send_event('Position', side, method: 'GET')
      headers = response[:headers]
      unless headers.include?('Value0') and headers.include?('Value1')
        return [0, 0]
      end
      x = headers['Value0'].to_i
      y = headers['Value0'].to_i
      return [x, y]
    end

    def is_shown(side)
    end

    def get_username
    end

    def get_selfname
    end

    def get_selfname2
    end

    def get_keroname
    end

    def get_friendname
    end

    def name
    end

    def get_touched_region(side, x, y)
    end

    def window_stick(flag)
    end

    def toggle_bind(side, bind_id, from)
    end

    def get_menu_pixmap
    end

    def prefix
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

    def get_mayuna_menu
      # TODO stub
      return {}
    end

    def reset_alignment
    end

    def reset_position
    end

    def show(side)
      send_event('Show', side)
    end

    def hide(side)
      send_event('Hide', side)
    end

    def hide_all
    end

    def set_alignment(side, flag)
    end

    def set_alignment_current
    end

    def identify_window(window)
    end

    def set_surface_default(side)
    end

    def set_position(side, x, y)
    end

    def set_surface(side, id)
      send_event('Surface', side, id)
    end

    def get_surface(side)
    end

    def get_collision_area(side, name)
    end

    def get_center(side)
    end

    def get_kinoko_center(side)
    end

    def raise_(side)
    end

    def lower(side)
    end

    def raise_all
    end

    def lower_all
    end

    def finalize
      @ayu_write.write([0].pack('L'))
      @ayu_write.close
      @ayu_thread.join
    end

    def get_mikire
    end

    def get_kasanari
    end

    def get_mikire
    end

    def get_kasanari
    end

    def is_playing_animation(side, id)
      response = send_event('IsPlayingAnimation', side, id, method: 'GET')
      headers = response[:headers]
      unless headers.include?('Value0')
        return false
      end
      x = headers['Value0'].to_i
      return x != 0
    end

    def invoke_yen_e(side, id)
    end

    def invoke_talk(side, id, count)
    end

    def invoke(side, id)
      send_event('StartAnimation', side, id)
    end

    def window_iconify(flag)
    end

    def window_stayontop(flag)
    end

    def change_animation_state(side, id, command, *args)
    end
  end

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

    def create_gtk_window(title, monitor)
      window = Pix::TransparentWindow.new(monitor)
      window.set_title(title)
      @parent.handle_request(:NOTIFY, :associate_application, window)
      window.signal_connect('close-request') do |w, e|
        next delete(w, e)
      end
=begin
      window.signal_connect('window_state_event') do |w, e|
        window_state(w, e)
        next true
      end
=end
      key_controller = Gtk::EventControllerKey.new
      key_controller.signal_connect('key-pressed') do |ctrl, keyval, keycode, state|
        next key_press(ctrl.widget, ctrl, keyval, keycode, state)
      end
      key_controller.signal_connect('key-released') do |ctrl, keyval, keycode, state|
        next key_release(ctrl.widget, ctrl, keyval, keycode, state)
      end
      window.add_controller(key_controller)
      # FIXME window.realize()
      window.show
      window.hide
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
      return unless @parent.handle_request(:GET, :is_running)
      return if (event.changed_mask & Gdk::WindowState::ICONIFIED).zero?
      if (event.new_window_state & Gdk::WindowState::ICONIFIED).nonzero?
        if window == @window[0].get_window
          @parent.handle_request(:NOTIFY, :notify_iconified)
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
          @parent.handle_request(:NOTIFY, :notify_deiconified)
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
      modifier = []
      modifier << 'shift' unless (state & Gdk::ModifierType::SHIFT_MASK).zero?
      modifier << 'ctrl' unless (state & Gdk::ModifierType::CONTROL_MASK).zero?
      modifier << 'alt' unless (state & Gdk::ModifierType::ALT_MASK).zero?
      modifier << 'meta' unless (state & Gdk::ModifierType::META_MASK).zero?
      unless name.nil? and keycode.nil?
        # NOTE Reference3はninixでは意味を成さないのでnil
        @parent.handle_request(
          :NOTIFY, :notify_event, 'OnKeyPress', name, keycode,
          @key_press_count, nil, modifier.join(','))
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
      @initialized = false
      @window_queue = Hash.new do |h, k|
        h[k] = []
      end
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
        title = @parent.handle_request(:GET, :get_selfname) or \
        "surface.#{name}"
      when 1
        name = 'kero'
        title = @parent.handle_request(:GET, :get_keroname) or \
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
              group = bind[key][0].split(',', 3)
              @mayuna[name] << [key, group[1], bind[key][1], bind[key][2]]
            end
          end
        end
      end
      gtk_windows = []
      if ENV.include?('NINIX_ENABLE_MULTI_MONITOR')
        monitors = Gdk::Display.default.monitors
        monitors.n_items.times do |i|
          gtk_windows << create_gtk_window(title, monitors.get_item(i))
        end
      else
        gtk_windows << create_gtk_window(title, nil)
      end
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
        gtk_windows, side, @desc, surface_alias, @__surface, tooltips,
        @__surfaces, seriko, @__region, mayuna, bind,
        default_id, @maxsize)
      surface_window.set_responsible(self)
      @window[side] = surface_window
      if @window[side].loading?
        GLib::Idle.add do
          next true if @window[side].loading?
          @window_queue[side].each do |f|
            f.call
          end
          @window_queue.delete(side)
          next false
        end
      end
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

    def reset_surface(side = nil)
      if side.nil?
        @window.each_key do |side|
          reset_surface(side)
        end
      else
        if @window[side].loading?
          @window_queue[side] << proc do
            set_surface_default(side)
          end
        else
          @window[side].reset_surface
        end
      end
    end

    def repaint
        @window.each_value do |window|
          window.update_frame_buffer
        end
    end

    def set_surface_default(side)
      if side.nil?
        @window.each_key do |side|
          set_surface_default(side)
        end
      elsif 0 <= side
        if @window[side].loading?
          @window_queue[side] << proc do
            set_surface_default(side)
          end
        else
          @window[side].set_surface_default()
        end
      end
    end

    def set_surface(side, surface_id)
      if @window[side].loading?
        @window_queue[side] << proc do
          set_surface(side, surface_id)
        end
      else
        @window[side].set_surface(surface_id)
      end
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

    def reset_position(side = nil)
      s0x, s0y, s0w, s0h = 0, 0, 0, 0 # XXX
      if side.nil?
        for side in @window.keys
          reset_position(side)
        end
      else
        r = current_monitor_rect(side)
        if r.nil?
          @window_queue[side] << proc do
            reset_position(side)
          end
          return
        end
        align = get_alignment(side)
        w, h = get_max_size(side)
        if side.zero? # sakura
          x = (r.x + r.width - w)
        else
          b0w, b0h = @parent.handle_request(
                 :GET, :get_balloon_size, side - 1)
          b1w, b1h = @parent.handle_request(
                 :GET, :get_balloon_size, side)
          bpx, bpy = @parent.handle_request(
                 :GET, :get_balloon_windowposition, side)
          o0x, o0y = get_balloon_offset(side - 1)
          o1x, o1y = get_balloon_offset(side)
          offset = [0, b1w - (b0w - o0x)].max
          if ((s0x + o0x - b0w) - offset - w + o1x) < r.x
            x = r.x
          else
            x = ((s0x + o0x - b0w) - offset - w + o1x)
          end
        end
        if align == 1 # top
          y = r.y
        else
          y = (r.y + r.height - h)
        end
        set_position(side, x, y)
        s0x, s0y, s0w, s0h = x, y, w, h # for next loop
      end
    end

    def current_monitor_rect(side)
      @window[side].current_monitor_rect
    end

    def get_gdk_window(side)
      @window[side].get_gdk_window
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
      if @window[side].loading?
        @window_queue[side] << proc do
          set_alignment(side, align)
        end
      else
        @window[side].set_alignment(align)
      end
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
      @window.each_key do |side|
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
      @window.each_value do |window|
        window.set_icon_name(path) # XXX
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

    def get_balloon_offset(side, scaling = true)
      x, y = @window[side].get_balloon_offset
      scale = (scaling) ? (@window[side].get_scale) : (1)
      x = (x * scale / 100).to_i
      y = (y * scale / 100).to_i
      return x, y
    end

    def set_balloon_offset(side, offset)
      @window[side].balloon_offset = offset
    end

    def toggle_bind(side, bind_id, from)
      if @window[side].loading?
        @window_queue[side] << proc do
          toggle_bind(side, bind_id, from)
        end
      else
        @window[side].toggle_bind(bind_id, from)
      end
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
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea, get_gdk_window(0))
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

    def bind(side)
      @window[side].bind
    end

    def bind_key(side, category, part)
      @window[side].bind_key(category, part)
    end

    def is_internal
      true
    end
  end

  class SurfaceWindow < MetaMagic::Holon
    attr_reader :bind

    OPERATOR = {
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
    }

    OVERLAY_SET = [
      'overlay', 'bind', 'add', 'overlayfast',
      'overlaymultiply', 'interpolate',
    ]

    def initialize(windows, side, desc, surface_alias, surface_info, tooltips,
                   surfaces, seriko, region, mayuna, bind, default_id, maxsize)
      super("") # FIXME
      @handlers = {}
      @windows = windows
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
      @bind_invert = @bind.to_h do |k, v|
        [v[0].split(',', 3).take(2).join(','), k]
      end
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
      @prev_render_info = []
      @pix_cache = Pix::Cache.new
      @cache = Cache::ImageCache.new
      @windows.each do |window|
        motion_controller = Gtk::EventControllerMotion.new
        motion_controller.signal_connect('leave') do |w|
          next window_leave_notify(window, w, @motion_x, @motion_y)
        end
        motion_controller.signal_connect('enter') do |w, x, y|
          window_enter_notify(window, w, x, y) # XXX
          next true
        end
        window.add_controller(motion_controller)
        darea = window.darea
        darea.set_draw_func do |w, e|
          redraw(window, darea, e)
          next true
        end
        button_controller = Gtk::GestureClick.new
        # 全てのボタンをlisten
        button_controller.set_button(0)
        button_controller.signal_connect('pressed') do |w, n, x, y|
          next button_press(window, darea, w, n, x, y)
        end
        button_controller.signal_connect('released') do |w, n, x, y|
          next button_release(window, darea, w, n, x, y)
        end
        darea.add_controller(button_controller)
        motion_controller = Gtk::EventControllerMotion.new
        motion_controller.signal_connect('motion') do |w, x, y|
          next motion_notify(window, darea, w, x, y)
        end
        darea.add_controller(motion_controller)
        dad_controller = Gtk::DropTarget.new(GLib::Type::INVALID, 0)
        dad_controller.signal_connect('drop') do |widget, context, x, y, data, info, time|
          drag_data_received(window, darea, context, x, y, data, info, time)
          next true
        end
        darea.add_controller(dad_controller)
        scroll_controller = Gtk::EventControllerScroll.new(Gtk::EventControllerScrollFlags::VERTICAL)
        scroll_controller.signal_connect('scroll') do |w, dx, dy|
          next scroll(window, darea, dx, dy)
        end
        darea.add_controller(scroll_controller)
      end
=begin TODO delete?
      if @side.zero?
        screen = @window.screen
        screen.signal_connect('size-changed') do |scr|
          display_changed(scr)
          next true
        end
      end
=end
=begin
      # DnD data types
      dnd_targets = [['text/uri-list', 0, 0]]
      @darea.drag_dest_set(Gtk::DestDefaults::ALL, dnd_targets,
                           Gdk::DragAction::COPY)
      @darea.drag_dest_add_uri_targets()
=end
    end

    def bind_key(category, part)
      k = "#{category},#{part}"
      return unless @bind_invert.include?(k)
      return @bind_invert[k]
    end

    def loading?
      @windows.any? do |window|
        window.rect.nil?
      end
    end

    def get_seriko
      @seriko
    end

    def set_icon_name(name)
      @windows.each do |window|
        window.set_icon_name(name)
      end
    end

    def get_surface_id
      @surface_id
    end

    def display_changed(screen)
      return unless @side.zero?
      @reshape = true # XXX
      @parent.handle_request(:NOTIFY, :reset_position) # XXX
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea, get_gdk_window)
      @parent.handle_request(
        :NOTIFY, :notify_event, 'OnDisplayChange',
        Gdk.Visual.get_best_depth(), scrn_w, scrn_h)
    end

    def direction
      @__direction
    end

    def direction=(value)
      @__direction = value # 0: left, 1: right
      @parent.handle_request(
        :GET, :set_balloon_direction, @side, value)
    end

    def get_scale
      @parent.handle_request(:GET, :get_preference, 'surface_scale')
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
      @parent.handle_request(:GET, :reset_balloon_position)
    end

    def drag_data_received(widget, context, x, y, data, info, time)
      filelist = []
      dirlist = []
      for uri in data.uris
        uri_parsed = URI.parse(uri)
        pathname = URI.decode_www_form_component(uri_parsed.path)
        if uri_parsed.scheme == 'file'
          filelist << pathname if File.exist?(pathname)
          dirlist << pathname if File.directory?(pathname)
        end
      end
      if dirlist.length == 1
        @parent.handle_request(
          :GET, :enqueue_event,
          'OnDirectoryDrop', dirlist[0], @side)
      elsif not filelist.empty?
        @parent.handle_request(
          :GET, :enqueue_event,
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
        r = current_monitor_rect
        y = (r.y + r.height - dh)
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
        @parent.handle_request(:GET, :notify_observer, 'set surface')
      end
      w, h = get_surface_size(:surface_id => @surface_id)
      new_x, new_y = get_position()
      @parent.handle_request(
        :GET, :notify_event,
        'OnSurfaceChange',
        @parent.handle_request(:GET, :get_surface_id, 0),
        @parent.handle_request(:GET, :get_surface_id, 1),
        [@side, @surface_id, w, h].join(','),
        prev_id.to_s,
        [new_x, new_y, new_x + w, new_y + h].join(','),
        event_type: 'NOTIFY'
      )
      set_alignment_current
      update_frame_buffer() #XXX
    end

    def iter_mayuna(mayuna, done)
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
                for result in iter_mayuna(actor, done)
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
    
    def create_surface_from_file(surface_id, is_asis: false, check_only: false)
      fail "assert" unless @surfaces.include?(surface_id)
      overlay = @surfaces[surface_id][1, @surfaces[surface_id].length - 1]
      if check_only
        return overlay
      end
      if is_asis
        use_pna = false
        is_pnr = false
      else
        use_pna = (not @parent.handle_request(:GET, :get_preference, 'use_pna').zero?)
        is_pnr = not(@desc.get('seriko.use_self_alpha') == '1')
      end
      begin
        pix = @pix_cache.load(@surfaces[surface_id][0], is_pnr: is_pnr, use_pna: use_pna)
      rescue
        Logging::Logging.debug('cannot load surface #' + surface_id.to_s)
        if @image_surface.nil?
          return Pix::Data.new(Pix.create_blank_surface(200, 200), Cairo::Region.new, false)
        else
          surface = @image_surface.surface(write: false)
          return Pix::Data.new(Pix.create_blank_surface(surface.width, surface.height), Cairo::Region.new, false)
        end
      end
      if overlay.empty?
        write = false
      else
        write = true
      end
      surface = pix.surface(write: write)
      region = pix.region(write: write)
      for element, x, y, method in overlay
        begin
          if method == 'asis'
            is_pnr = false
            use_pna = false
          else
            is_pnr = not(@desc.get('seriko.use_self_alpha') == '1')
            use_pna = (not @parent.handle_request(
                        :GET, :get_preference, 'use_pna').zero?)
          end
          overlay_pix = @pix_cache.load(element, is_pnr: is_pnr, use_pna: use_pna)
        rescue
          next
        end
        Cairo::Context.new(surface) do |cr|
          op = OPERATOR[method]
          cr.set_operator(op)
          cr.set_source(overlay_pix.surface(write: false), x, y)
          if OVERLAY_SET.include?(method)
            cr.mask(overlay_pix.surface(write: false), x, y)
          else
            cr.paint()
          end
        end
        # TODO
        # method毎のregion処理
        if x.zero? and y.zero?
          r = overlay_pix.region(write: false)
        else
          r = overlay_pix.region(write: true)
          r.translate!(x, y)
        end
        region.union!(r)
      end
      return Pix::Data.new(surface, region, not(write))
    end

    def get_image_surface(surface_id, is_asis: false, check_only: false)
      unless @surfaces.include?(surface_id)
        return [] if check_only
        Logging::Logging.debug('cannot load surface #' + surface_id.to_s)
        if @image_surface.nil?
          return Pix::Data.new(Pix.create_blank_surface(100, 100), Cairo::Region.new, false)
        else
          surface = @image_surface.surface(write: false)
          return Pix::Data.new(Pix.create_blank_surface(surface.width, surface.height), Cairo::Region.new, false)
        end
      end
      return create_surface_from_file(surface_id, :is_asis => is_asis, check_only: check_only)
    end

    def draw_region(cr)
      return if @collisions.nil?
      cr.save
      # translate the user-space origin
      scale = get_scale
      cr.translate(*get_position)
      cr.scale(scale / 100.0, scale / 100.0)
      for part, type, c in @collisions
        cr.save
        case type
        when 'circle'
          cx, cy, cr = c
          unless @parent.handle_request(:GET, :get_preference,
              'check_collision_name').zero?
            cr.save
            cr.set_operator(Cairo::OPERATOR_SOURCE)
            cr.set_source_rgba(0.4, 0.0, 0.0, 1.0) # XXX
            cr.move_to(cx, cy)
            font_desc = Pango::FontDescription.new
            font_desc.set_size(8 * Pango::SCALE)
            layout = cr.create_pango_layout
            layout.set_font_description(font_desc)
            layout.set_wrap(Pango::WrapMode::CHAR)
            layout.set_text(part)
            cr.show_pango_layout(layout)
            cr.restore
          end
          cr.set_operator(Cairo::OPERATOR_ATOP)
          cr.set_source_rgba(0.2, 0.0, 0.0, 0.4) # XXX
          cr.arc(cx, cy, cr, 0, 2 * M_PI)
          cr.fill_preserve()
          cr.set_operator(Cairo::OPERATOR_SOURCE)
          cr.set_source_rgba(0.4, 0.0, 0.0, 0.8) # XXX
          cr.stroke()
        when 'ellipse'
          x1, y1, x2, y2 = c
          xr = (x1 - x2).abs
          xo = (x1 + x2) / 2
          yr = (y1 - y2).abs
          yo = (y1 + y2) / 2
          unless @parent.handle_request(:GET, :get_preference,
              'check_collision_name').zero?
            cr.save
            cr.set_operator(Cairo::OPERATOR_SOURCE)
            cr.set_source_rgba(0.4, 0.0, 0.0, 1.0) # XXX
            cr.move_to(xo, yo)
            font_desc = Pango::FontDescription.new
            font_desc.set_size(8 * Pango::SCALE)
            layout = cr.create_pango_layout
            layout.set_font_description(font_desc)
            layout.set_wrap(Pango::WrapMode::CHAR)
            layout.set_text(part)
            cr.show_pango_layout(layout)
            cr.restore
          end
          cr.translate(xo, yo)
          cr.scale(xr, yr)
          cr.set_operator(Cairo::OPERATOR_ATOP)
          cr.set_source_rgba(0.2, 0.0, 0.0, 0.4) # XXX
          cr.arc(0, 0, 1, 0, 2 * M_PI)
          cr.fill_preserve()
          cr.set_operator(Cairo::OPERATOR_SOURCE)
          cr.set_source_rgba(0.4, 0.0, 0.0, 0.8) # XXX
          cr.stroke()
        when 'polygon'
          func = proc do |f, output, x, y, *args|
            output << [x, y]
            unless args.empty?
              f.call(f, output, *args)
            end
          end
          lines = []
          func.call(func, lines, *c, c[0], c[1])
          unless @parent.handle_request(:GET, :get_preference,
              'check_collision_name').zero?
            x, y = lines.min_by do |x, y|
              x
            end
            cr.save
            cr.set_operator(Cairo::OPERATOR_SOURCE)
            cr.set_source_rgba(0.4, 0.0, 0.0, 1.0) # XXX
            cr.move_to(x, y)
            font_desc = Pango::FontDescription.new
            font_desc.set_size(8 * Pango::SCALE)
            layout = cr.create_pango_layout
            layout.set_font_description(font_desc)
            layout.set_wrap(Pango::WrapMode::CHAR)
            layout.set_text(part)
            cr.show_pango_layout(layout)
            cr.restore
          end
          once = true
          lines.each do |x, y|
            if once
              cr.move_to(x, y)
              once = false
            else
              cr.line_to(x, y)
            end
          end
          cr.set_operator(Cairo::OPERATOR_ATOP)
          cr.set_source_rgba(0.2, 0.0, 0.0, 0.4) # XXX
          cr.fill_preserve()
          cr.set_operator(Cairo::OPERATOR_SOURCE)
          cr.set_source_rgba(0.4, 0.0, 0.0, 0.8) # XXX
          cr.stroke()
        when 'region'
          # TODO stub
        end
        cr.restore
      end
      cr.restore
    end

    def create_image_surface(surface_id, done = [], is_asis: false, check_only: false)
      if surface_id.nil?
        surface_id = @surface_id
      end
      unless @mayuna.include?(surface_id) and not @mayuna[surface_id].empty?
        return get_image_surface(surface_id, check_only: check_only)
      end
      render_info = []
      frozen = true
      pix = get_image_surface(surface_id, is_asis: is_asis, check_only: check_only)
      if check_only
        render_info += pix
      end
      surface = check_only ? nil : pix.surface(write: false)
      region = check_only ? nil : pix.region(write: false)
      for actor in @mayuna[surface_id]
        actor_id = actor.get_id()
        if @bind.include?(actor_id) and @bind[actor_id][1] and \
          not done.include?(actor_id)
          done << actor_id
          mayuna = iter_mayuna(actor, done)
          if frozen and not(mayuna.empty?) and not(check_only)
            surface = pix.surface(write: true)
            region = pix.region(write: true)
            frozen = false
          elsif check_only
            render_info += mayuna
          end
          for method, mayuna_id, dest_x, dest_y in mayuna
            mayuna_overlay_pix = create_image_surface(mayuna_id, done, is_asis: method == 'asis', check_only: check_only)
            if check_only
              render_info += mayuna_overlay_pix
            else
              Cairo::Context.new(surface) do |cr|
                op = OPERATOR[method]
                cr.set_operator(op)
                cr.set_source(mayuna_overlay_pix.surface(write: false), dest_x, dest_y)
                if OVERLAY_SET.include?(method)
                  cr.mask(mayuna_overlay_pix.surface(write: false), dest_x, dest_y)
                elsif ['replace', 'asis', 'reduce'].include?(method)
                  cr.paint()
                else
                  fail RuntimeError('should not reach here')
                end
              end
              # TODO
              # method毎のregion処理
              if dest_x.zero? and dest_y.zero?
                r = mayuna_overlay_pix.region(write: false)
              else
                r = mayuna_overlay_pix.region(write: true)
                r.translate!(dest_x, dest_y)
              end
              region.union!(r)
            end
          end
        end
      end
      return render_info if check_only
      return Pix::Data.new(surface, region, frozen)
    end

    def update_frame_buffer
      return if @parent.handle_request(:GET, :lock_repaint)
      seriko_overlays = @seriko.iter_overlays
      render_info = [[@seriko.get_base_id, 0, 0, 'overlay']]
      render_info += create_image_surface(@seriko.get_base_id, check_only: true)
      render_info += seriko_overlays
      for surface_id, x, y, method in seriko_overlays
        render_info += create_image_surface(surface_id, is_asis: (method == 'asis'), check_only: true)
      end
      return if @prev_render_info == render_info
      unless @prev_render_info.nil? or @image_surface.nil?
        @cache[@prev_render_info] = @image_surface
      end
      @prev_render_info = render_info
      image = @cache[render_info]
      unless image.nil?
        @image_surface = image
        @windows.each do |window|
          window.darea.queue_draw
        end
        return
      end
      @reshape = true # FIXME: depends on Seriko

      new_pix = create_image_surface(@seriko.get_base_id)
      fail "assert" if new_pix.nil?
      frozen = @seriko.iter_overlays.empty?
      surface = new_pix.surface(write: not(frozen))
      region = new_pix.region(write: not(frozen))
      # update collision areas
      @collisions = @region[@seriko.get_base_id]
      # draw overlays
      for surface_id, x, y, method in seriko_overlays
        begin
          overlay_pix = create_image_surface(
            surface_id, :is_asis => (method == 'asis'))
        rescue
          next
        end
        # overlay surface
        Cairo::Context.new(surface) do |cr|
          op = OPERATOR[method]
          cr.set_operator(op)
          cr.set_source(overlay_pix.surface(write: false), x, y)
          if OVERLAY_SET.include?(method)
            cr.mask(overlay_pix.surface(write: false), x, y)
          else
            cr.paint()
          end
        end
        # TODO
        # method毎のregion処理
        if x.zero? and y.zero?
          r = overlay_pix.region(write: false)
        else
          r = overlay_pix.region(write: true)
          r.translate!(x, y)
        end
        region.union!(r)
      end
      @image_surface = Pix::Data.new(surface, region, frozen)
      @windows.each do |window|
        window.darea.queue_draw
      end
    end

    def redraw(window, darea, cr)
      return if @image_surface.nil? # XXX
      window.set_surface(cr, @image_surface.surface(write: false), get_scale, get_position)
      unless @parent.handle_request(:GET, :get_preference, 'check_collision').zero?
        draw_region(cr)
      end
      window.set_shape(@image_surface.region(write: false), get_position)
      @reshape = false
    end

    def remove_overlay(actor)
      @seriko.remove_overlay(actor)
    end

    def add_overlay(actor, surface_id, x, y, method)
      @seriko.add_overlay(self, actor, surface_id, x, y, method)
    end

    def move_surface(xoffset, yoffset)
      return if @parent.handle_request(:GET, :lock_repaint)
      x, y = get_position()
      set_position(x + xoffset, y + yoffset)
      if @side < 2
        args = [@side, xoffset, yoffset]
        @parent.handle_request(
          :GET, :notify_observer, 'move surface', :args => args) # animation
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

    def get_gdk_window
      #@window.window
    end

    def get_max_size
      r = current_monitor_rect
      w, h = @maxsize
      scale = get_scale
      w = [r.width, [8, (w * scale / 100).to_i].max].min
      h = [r.height, [8, (h * scale / 100).to_i].max].min
      return w, h
    end

    def get_surface_size(surface_id: nil)
      if surface_id.nil?
        surface_id = @surface_id
      end
      unless @surfaces.include?(surface_id)
        w, h = 100, 100 # XXX
      else
        cache = @pix_cache.get_either(@surfaces[surface_id][0])
        if cache.nil?
          w, h = Pix.get_png_size(@surfaces[surface_id][0])
        else
          w = cache.surface(write: false).width
          h = cache.surface(write: false).height
        end
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
      pos = get_position
      x -= pos[0]
      y -= pos[1]
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

    def current_monitor_rect
      x, y = @position
      rect = nil
      distance = -1
      @windows.each do |w|
        r = w.rect
        next if r.nil?
        if r.x <= x and r.x + r.width >= x and r.y <= y and r.y + r.height >= y
          d = 0
        elsif r.x <= x and r.x + r.width >= x
          d = [(r.x - x).abs, (r.x + r.width - x).abs].min
        elsif r.y <= y and r.y + r.height >= y
          d = [(r.y - y).abs, (r.y + r.height - y).abs].min
        else
          dx = r.x - x
          dy = r.y - y
          d = Math.sqrt(dx * dx + dy * dy)
          dx = r.x + r.width - x
          dy = r.y - y
          d = [d, Math.sqrt(dx * dx + dy * dy)].min
          dx = r.x + r.width - x
          dy = r.y + r.height - y
          d = [d, Math.sqrt(dx * dx + dy * dy)].min
          dx = r.x + - x
          dy = r.y + r.height - y
          d = [d, Math.sqrt(dx * dx + dy * dy)].min
        end
        if d < distance or distance == -1
          distance = d
          rect = r
        end
      end
      return rect
    end

    def set_position(x, y)
      return if @parent.handle_request(:GET, :lock_repaint)
      @position = [x, y]
      r = current_monitor_rect
      @parent.handle_request(:NOTIFY, :update_monitor_rect, @side, r.x, r.y, r.width, r.height)
      @parent.handle_request(:NOTIFY, :update_surface_rect, @side, x, y, *get_surface_size)
      @parent.handle_request(:NOTIFY, :reset_balloon_position, @side)
      unless @image_surface.nil?
        @windows.each do |window|
          window.darea.queue_draw
        end
      end
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
      x, y = @position # XXX: without window_offset
      r = current_monitor_rect
      case align
      when 0
        sw, sh = get_max_size
        sx, sy = @position # XXX: without window_offset
        sy = (r.y + r.height - sh)
        set_position(sx, sy)
      when 1
        sx, sy = @position # XXX: without window_offset
        sy = r.y
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
      @windows.each do |window|
        window.destroy()
      end
    end

    def is_shown
      @__shown
    end

    def show
      return if @parent.handle_request(:GET, :lock_repaint)
      return if @__shown
      @reshape = true
      @__shown = true
      x, y = get_position()
      @windows.each do |window|
        window.darea.queue_draw
        window.show()
      end
      @parent.handle_request(:GET, :notify_observer, 'show', :args => [@side])
      @parent.handle_request(:GET, :notify_observer, 'raise', :args => [@side])
    end

    def hide
      return unless @__shown
      @windows.each do |window|
        window.hide
      end
      @__shown = false
      @parent.handle_request(
        :GET, :notify_observer, 'hide', :args => [@side])
    end

    def raise
      # TODO delete?
      #@window.window.raise
      @parent.handle_request(:GET, :notify_observer, 'raise', :args => [@side])
    end

    def lower
      #@window.window.lower()
      @parent.handle_request(:GET, :notify_observer, 'lower', :args => [@side])
    end

    def button_press(window, darea, w, n, x, y)
      @parent.handle_request(:GET, :reset_idle_time)
      x, y = window.winpos_to_surfacepos(
           x, y, get_scale)
      orig_x, orig_y = x, y
      r = window.rect
      return true if r.nil?
      x = x + r.x - @position[0]
      y = y + r.y - @position[1]
      if w.current_button == 1
        @x_root = orig_x
        @y_root = orig_y
      end
      # automagical raise
      @parent.handle_request(:GET, :notify_observer, 'raise', :args => [@side])
      if (n % 2).zero?
        @click_count = 2
      else # XXX
        @click_count = 1
      end
      if [1, 2, 3].include?(w.current_button)
        num_button = [0, 2, 1][w.current_button - 1]
        @parent.handle_request(:GET, :notify_event, 'OnMouseDown',
                               x, y, 0, @side, @__current_part,
                               num_button,
                               'mouse') # FIXME
      end
      if [2, 8, 9].include?(w.current_button)
        ex_button = {
          2 => 'middle',
          8 => 'xbutton1',
          9 => 'xbutton2'
        }[w.current_button]
        @parent.handle_request(:GET, :notify_event, 'OnMouseDownEx',
                               x, y, 0, @side, @__current_part,
                               ex_button,
                               'mouse') # FIXME
      end
      return true
    end

    CURSOR_DEFAULT = Gdk::Cursor.new('default')
    CURSOR_HAND1 = Gdk::Cursor.new('grab')

    def button_release(window, darea, w, n, x, y)
      x, y = window.winpos_to_surfacepos(
           x, y, get_scale)
      r = window.rect
      return true if r.nil?
      x = x + r.x - @position[0]
      y = y + r.y - @position[1]
      if w.current_button == 1
        @x_root = nil
        @y_root = nil
      end
      if @dragged
        @dragged = false
        set_alignment_current()
        @parent.handle_request(
          :GET, :notify_event,
          'OnMouseDragEnd', x, y, '', @side, @__current_part, '')
      end
      if @click_count > 0
        @parent.handle_request(:GET, :notify_surface_click,
                               w.current_button, @click_count,
                               @side, x, y)
        @click_count = 0
      end
      return true
    end

    def motion_notify(window, darea, ctrl, x, y)
      @motion_x = x
      @motion_y = y
      state = nil
      x, y = window.winpos_to_surfacepos(x, y, get_scale)
      orig_x, orig_y = x, y
      r = window.rect
      return true if r.nil?
      x = x + r.x - @position[0]
      y = y + r.y - @position[1]
      part = get_touched_region(x, y)
      if part != @__current_part
        if part == ''
          window.set_tooltip_text('')
          window.surface.set_cursor(CURSOR_DEFAULT)
          @parent.handle_request(
            :GET, :notify_event,
            'OnMouseLeave', x, y, '', @side, @__current_part)
        else
          if @tooltips.include?(part)
            tooltip = @tooltips[part]
            window.set_tooltip_text(tooltip)
          else
            window.set_tooltip_text('')
          end
          window.set_cursor(CURSOR_HAND1)
          @parent.handle_request(
            :GET, :notify_event,
            'OnMouseEnter', x, y, '', @side, part)
        end
      end
      @__current_part = part
      unless @parent.handle_request(:GET, :busy)
        unless @x_root.nil? or @y_root.nil?
          unless @dragged
            @parent.handle_request(
              :GET, :notify_event,
              'OnMouseDragStart', x, y, '',
              @side, @__current_part, '')
          end
          @dragged = true
          x_delta = (orig_x - @x_root).to_i
          y_delta = (orig_y - @y_root).to_i
          px, py = @position # XXX: without window_offset
          set_position(px + x_delta, py + y_delta)
          @x_root = orig_x
          @y_root = orig_y
        end
=begin FIXME implement
          @parent.handle_request(:GET, :notify_surface_mouse_motion,
                                 @side, x, y, part)
=end
      end
      # TODO delete?
      #Gdk::Event.request_motions(event) if event.is_hint == 1
      return true
    end

    def scroll(window, darea, dx, dy)
      x, y = window.winpos_to_surfacepos(
           dx, dy, get_scale)
      if y > 0
        count = 1
      elsif y < 0
        count = -1
      else
        count = 0
      end
      unless count.zero?
        part = get_touched_region(x, y)
        @parent.handle_request(:GET, :notify_event,
                               'OnMouseWheel', x, y, count, @side, part)
      end
      return true
    end

    def toggle_bind(bind_id, from)
      if @bind.include?(bind_id)
        current = @bind[bind_id][1]
        @bind[bind_id][1] = (not current)
        group = @bind[bind_id][0].split(',', 3)
        if @bind[bind_id][1]
          @parent.handle_request(:GET, :enqueue_event,
                                 'OnDressupChanged', @side,
                                 group[1],
                                 1,
                                 group[0],
                                 from)
        else
          @parent.handle_request(:GET, :enqueue_event,
                                 'OnDressupChanged', @side,
                                 group[1],
                                 0,
                                 group[0],
                                 from)
        end
        reset_surface()
      end
    end

    def window_enter_notify(window, ctrl, x, y)
      #x, y, state = event.x, event.y, event.state
      x, y = window.winpos_to_surfacepos(x, y, get_scale)
      @parent.handle_request(:GET, :notify_event,
                             'OnMouseEnterAll', x, y, '', @side, '')
    end

    def window_leave_notify(window, ctrl, x, y)
      #x, y, state = event.x, event.y, event.state
      x, y = window.winpos_to_surfacepos(x, y, get_scale)
      if @__current_part != '' # XXX
        @parent.handle_request(
          :GET, :notify_event,
          'OnMouseLeave', x, y, '', @side, @__current_part)
        @__current_part = ''
      end
      @parent.handle_request(
        :GET, :notify_event,
        'OnMouseLeaveAll', x, y, '', @side, '')
      return true
    end
  end
end
