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

require_relative "pix"


module Balloon

  class Balloon
    attr_accessor :window, :user_interaction

    def initialize
      @parent = nil
      @synchronized = []
      @user_interaction = false
      @window = []
      # create communicatebox
      @communicatebox = CommunicateBox.new()
      @communicatebox.set_responsible(self)
      # create teachbox
      @teachbox = TeachBox.new()
      @teachbox.set_responsible(self)
      # create inputbox
      @inputbox = InputBox.new()
      @inputbox.set_responsible(self)
      # create passwordinputbox
      @passwordinputbox = PasswordInputBox.new()
      @passwordinputbox.set_responsible(self)
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      raise "assert" unless ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
        'reset_user_interaction' => 'reset_user_interaction',
      }
      if not handlers.include?(event)
        result = @parent.handle_request(
          event_type, event, *arglist)
      else
        result = method(handlers[event]).call(*arglist)
      end
      if event_type == 'GET'
        return result
      end
    end

    def reset_user_interaction
      @user_interaction = false
    end

    def get_text_count(side)
      if @window.length > side
        return @window[side].get_text_count()
      else
        return 0
      end
    end

    def get_window(side)
      if @window.length > side
        return @window[side].get_window
      else
        return nil
      end
    end

    def reset_text_count(side)
      if @window.length > side
        @window[side].reset_text_count()
      end
    end

    def reset_balloon
      for balloon_window in @window
        balloon_window.reset_balloon()
      end
    end

    def create_gtk_window(title)
      window = Pix::TransparentWindow.new()
      window.set_title(title)
      window.set_skip_pager_hint(false)
      window.set_skip_taskbar_hint(true)
      window.signal_connect('delete_event') do |w, e|
        delete(w, e)
        next true
      end
      window.realize()
      return window
    end

    def identify_window(win)
      for balloon_window in @window
        if win == balloon_window.get_window.window
          return true
        end
      end
      return false
    end

    def delete(window, event)
      return true
    end

    def finalize
      for balloon_window in @window
        balloon_window.destroy()
      end
      @window = []
      @communicatebox.destroy()
      @teachbox.destroy()
      @inputbox.destroy()
      @passwordinputbox.destroy()
    end

    def new_(desc, balloon)
      @desc = desc
      @directory = balloon['balloon_dir'][0]
      balloon0 = {}
      balloon1 = {}
      communicate0 = nil
      communicate1 = nil
      communicate2 = nil
      communicate3 = nil
      for key in balloon.keys
        value = balloon[key]
        if ['arrow0', 'arrow1'].include?(key)
          balloon0[key] = value
          balloon1[key] = value
        elsif key == 'sstp'
          balloon0[key] = value  # sstp marker
        elsif key.start_with?('s')
          balloon0[key] = value  # Sakura
        elsif key.start_with?('k')
          balloon1[key] = value  # Unyuu
        elsif key == 'c0'
          communicate0 = value # send box
        elsif key == 'c1'
          communicate1 = value # communicate box
        elsif key == 'c2'
          communicate2 = value # teach box
        elsif key == 'c3'
          communicate3 = value # input box
        end
      end
      @balloon0 = balloon0
      @balloon1 = balloon1
      # create balloon windows
      for balloon_window in @window
        balloon_window.destroy()
      end
      @window = []
      add_window(0)
      add_window(1)
      # configure communicatebox
      @communicatebox.new_(desc, communicate1)
      # configure teachbox
      @teachbox.new_(desc, communicate2)
      # configure inputbox
      @inputbox.new_(desc, communicate3)
      # configure passwordinputbox
      @passwordinputbox.new_(desc, communicate3)
    end

    def add_window(side)
      raise "assert" unless @window.length == side
      if side == 0
        name = 'balloon.sakura'
        id_format = 's'
        balloon = @balloon0
      elsif side == 1
        name = 'balloon.kero'
        id_format = 'k'
        balloon = @balloon1
      else
        name = 'balloon.char' + side.to_s
        id_format = 'k'
        balloon = @balloon1
      end
      gtk_window = create_gtk_window(name)
      balloon_window = BalloonWindow.new(
        gtk_window, side, @desc, balloon, id_format)
      balloon_window.set_responsible(self)
      @window << balloon_window
    end

    def reset_fonts
      for window in @window
        window.reset_fonts()
      end
    end

    def get_balloon_directory
      return @directory
    end

    def get_balloon_size(side)
      if @window.length > side
        return @window[side].get_balloon_size()
      else
        return [0, 0]
      end
    end

    def get_balloon_windowposition(side)
      if @window.length > side
        return @window[side].get_balloon_windowposition()
      else
        return [0, 0]
      end
    end

    def set_balloon_default
      default_id = @parent.handle_request('GET', 'get_balloon_default_id')
      begin
        default_id = Integer(default_id)
      rescue
        default_id = 0
      end
      for side in 0..@window.length-1
        @window[side].set_balloon(default_id)
      end
    end

    def set_balloon(side, num)
      if @window.length > side
        @window[side].set_balloon(num)
      end
    end

    def set_position(side, base_x, base_y)
      if @window.length > side
        @window[side].set_position(base_x, base_y)
      end
    end

    def get_position(side)
      if @window.length > side
        return @window[side].get_position()
      else
        return [0, 0]
      end
    end

    def set_autoscroll(flag)
      for side in 0..@window.length-1
        @window[side].set_autoscroll(flag)
      end
    end

    def is_shown(side)
      if @window.length <= side
        return false
      else
        return @window[side].is_shown()
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
        @window[side].raise_()
      end
    end

    def raise_(side)
      if @window.length > side
        @window[side].raise_()
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

    def synchronize(list)
      @synchronized = list
    end

    def clear_text_all
      for side in 0..@window.length-1
        clear_text(side)
      end
    end

    def clear_text(side)
      if not @synchronized.empty?
        for side in @synchronized
          if @window.length > side
            @window[side].clear_text()
          end
        end
      else
        if @window.length > side
          @window[side].clear_text()
        end
      end
    end

    def append_text(side, text)
      if not @synchronized.empty?
        for side in @synchronized
          if @window.length > side
            @window[side].append_text(text)
          end
        end
      else
        if @window.length > side
          @window[side].append_text(text)
        end
      end
    end

    def append_sstp_marker(side)
      if @window.length > side
        @window[side].append_sstp_marker()
      end
    end

    def append_link_in(side, label)
      if not @synchronized.empty?
        for side in @synchronized
          if @window.length > side
            @window[side].append_link_in(label)
          end
        end
      else
        if @window.length > side
          @window[side].append_link_in(label)
        end
      end
    end

    def append_link_out(side, label, value)
      if not @synchronized.empty?
        for side in @synchronized
          if @window.length > side
            @window[side].append_link_out(label, value)
          end
        end
      else
        if @window.length > side
          @window[side].append_link_out(label, value)
        end
      end
    end

    def append_link(side, label, value, newline_required: false)
      if not @synchronized.empty?
        for side in @synchronized
          if @window.length > side
            @window[side].append_link_in(label)
            @window[side].append_text(value)
            @window[side].append_link_out(label, value)
            if newline_required
              @window[side].set_newline()
            end
          end
        end
      else
        if @window.length > side
          @window[side].append_link_in(label)
          @window[side].append_text(value)
          @window[side].append_link_out(label, value)
          if newline_required
            @window[side].set_newline()
          end
        end
      end
    end

    def append_meta(side, tag)
      if not @synchronized.empty?
        for side in @synchronized
          if @window.length > side
            @window[side].append_meta(tag)
          end
        end
      else
        if @window.length > side
          @window[side].append_meta(tag)
        end
      end
    end

    def append_image(side, path, x, y)
      if @window.length > side
        @window[side].append_image(path, x, y)
      end
    end

    def show_sstp_message(message, sender)
      @window[0].show_sstp_message(message, sender)
    end

    def hide_sstp_message
      @window[0].hide_sstp_message()
    end

    def open_communicatebox
      if not @user_interaction
        @user_interaction = true
        @communicatebox.show()
      end
    end

    def open_teachbox
      if not @user_interaction
        @user_interaction = true
        @parent.handle_request('NOTIFY', 'notify_event', 'OnTeachStart')
        @teachbox.show()
      end
    end

    def open_inputbox(symbol, limittime: -1, default: nil)
      if not @user_interaction
        @user_interaction = true
        @inputbox.set_symbol(symbol)
        @inputbox.set_limittime(limittime)
        @inputbox.show(default)
      end
    end

    def open_passwordinputbox(symbol, limittime: -1, default: nil)
      if not @user_interaction
        @user_interaction = true
        @passwordinputbox.set_symbol(symbol)
        @passwordinputbox.set_limittime(limittime)
        @passwordinputbox.show(default)
      end
    end

    def close_inputbox(symbol)
      if not @user_interaction
        return
      end
      @inputbox.close(symbol)
      @passwordinputbox.close(symbol)
    end
  end


  class BalloonWindow
    attr_accessor :direction

    def initialize(window, side, desc, balloon, id_format)
      @window = window
      @side = side
      @parent = nil
      @desc = desc
      @balloon = balloon
      @balloon_id = nil
      @id_format = id_format
      @num = 0
      @__shown = false
      @sstp_marker = []
      @sstp_region = nil
      @sstp_message = nil
      @images = []
      @width = 0
      @height = 0
      @__font_name = ''
      @text_count = 0
      @balloon_surface = nil
      @autoscroll = true
      @dragged = false
      @x_root = nil
      @y_root = nil
      @x_fractions = 0
      @y_fractions = 0
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
        button_press(w, e)
        next true
      end
      @darea.signal_connect('button_release_event') do |w, e|
        button_release(w, e)
        next true
      end
      @darea.signal_connect('motion_notify_event') do |w, e|
        motion_notify(w, e)
        next true
      end
      @darea.signal_connect('scroll_event') do |w, e|
        scroll(w, e)
        next true
      end
      @layout = Pango::Layout.new(@darea.pango_context)
      @sstp_layout = Pango::Layout.new(@darea.pango_context())
      mask_r = desc.get('maskcolor.r', :default => 128).to_i
      mask_g = desc.get('maskcolor.g', :default => 128).to_i
      mask_b = desc.get('maskcolor.b', :default => 128).to_i
      @cursor_color = [mask_r / 255.0, mask_g / 255.0, mask_b / 255.0]
      text_r = desc.get(['font.color.r', 'fontcolor.r'], :default => 0).to_i
      text_g = desc.get(['font.color.g', 'fontcolor.g'], :default => 0).to_i
      text_b = desc.get(['font.color.b', 'fontcolor.b'], :default => 0).to_i
      @text_normal_color = [text_r / 255.0, text_g / 255.0, text_b / 255.0]
      if desc.get('maskmethod').to_i == 1
        text_r = 255 - text_r
        text_g = 255 - text_g
        text_b = 255 - text_b
      end
      @text_active_color = [text_r / 255.0, text_g / 255.0, text_b / 255.0]
      sstp_r = desc.get('sstpmessage.font.color.r', :default => text_r).to_i
      sstp_g = desc.get('sstpmessage.font.color.g', :default => text_g).to_i
      sstp_b = desc.get('sstpmessage.font.color.b', :default => text_b).to_i
      @sstp_message_color = [sstp_r / 255.0, sstp_g / 255.0, sstp_b / 255.0]
      # initialize
      @__direction = [side, 1].min ## kluge: multi character
      @position = [0, 0]
      reset_fonts()
      clear_text()
    end

    def get_window
      return @window
    end

    def set_responsible(parent)
      @parent = parent
    end

    #@property
    def scale
      scaling = (@parent.handle_request('GET', 'get_preference', 'balloon_scaling') != 0)
      scale = @parent.handle_request('GET', 'get_preference', 'surface_scale')
      if scaling
        return scale
      else
        return 100 # [%]
      end
    end

    def direction
      return @__direction
    end

    def direction=(value)
      if @__direction != value
        @__direction = value # 0: left, 1: right
        reset_balloon()
      end
    end

    def get_balloon_windowposition
      x = __get_with_scaling('windowposition.x', 0).to_i
      y = __get_with_scaling('windowposition.y', 0).to_i
      return x, y
    end

    def get_image_surface(balloon_id)
      if not @balloon.include?(balloon_id)
        return nil
      end
      begin
        path, config = @balloon[balloon_id]
        use_pna = (@parent.handle_request('GET', 'get_preference', 'use_pna') != 0)
        surface = Pix.create_surface_from_file(path, :use_pna => use_pna)
      rescue
        return nil
      end
      return surface
    end

    def reset_fonts
      if @parent != nil
        font_name = @parent.handle_request('GET', 'get_preference', 'balloon_fonts')
      else
        font_name = nil
      end
      if @__font_name == font_name
        return
      end
      @font_desc = Pango::FontDescription.new(font_name)
      pango_size = @font_desc.size
      if pango_size == 0
        default_size = 12 # for Windows environment
        size = @desc.get(['font.height', 'font.size'], :default => default_size).to_i
        pango_size = size * 3 / 4 # convert from Windows to GTK+
        pango_size *= Pango::SCALE
      end
      @font_desc.set_size(pango_size)
      @__font_name = font_name
      @layout.set_font_description(@font_desc)
      @layout.set_wrap(Pango::WRAP_CHAR) # XXX
      # font for sstp message
      if @side == 0
        @sstp_font_desc = Pango::FontDescription.new(font_name)
        pango_size = @sstp_font_desc.size
        if pango_size == 0
          default_size = 10 # for Windows environment
          size = @desc.get('sstpmessage.font.height', :default => default_size).to_i
          pango_size = size * 3 / 4 # convert from Windows to GTK+
          pango_size *= Pango::SCALE
        end
        @sstp_font_desc.set_size(pango_size)
        @sstp_layout.set_font_description(@sstp_font_desc)
        @sstp_layout.set_wrap(Pango::WRAP_CHAR)
      end
      if @balloon_id != nil
        reset_message_regions()
        if @__shown
          @darea.queue_draw()
        end
      end
    end

    def reset_sstp_marker
      if @side == 0
        raise "assert" unless @balloon_surface != nil
        w = @balloon_surface.width
        h = @balloon_surface.height
        # sstp marker position
        @sstp = []
        x = config_adjust('sstpmarker.x', w,  30)
        y = config_adjust('sstpmarker.y', h, -20)
        @sstp << [x, y] # sstp marker
        x = config_adjust('sstpmessage.x', w,  50)
        y = config_adjust('sstpmessage.y', h, -20)
        @sstp << [x, y] # sstp message
      end
      # sstp marker surface (not only for @side == 0)
      @sstp_surface = get_image_surface('sstp')
    end

    def reset_arrow
      # arrow positions
      @arrow = []
      raise "assert" unless @balloon_surface != nil
      w = @balloon_surface.width
      h = @balloon_surface.height
      x = config_adjust('arrow0.x', w, -10)
      y = config_adjust('arrow0.y', h,  10)
      @arrow << [x, y]
      x = config_adjust('arrow1.x', w, -10)
      y = config_adjust('arrow1.y', h, -20)
      @arrow << [x, y]
      # arrow surfaces and sizes
      @arrow0_surface = get_image_surface('arrow0')
      @arrow1_surface = get_image_surface('arrow1')
    end

    def reset_message_regions
      w, h = @layout.pixel_size
      @font_height = h
      @line_space = 1
      @layout.set_spacing(@line_space)
      # font metrics
      origin_x = __get('origin.x',
                       __get('zeropoint.x',
                             __get('validrect.left', 14).to_i).to_i).to_i
      origin_y = __get('origin.y',
                       __get('zeropoint.y',
                             __get('validrect.top', 14).to_i).to_i).to_i
      wpx = __get('wordwrappoint.x',
                  __get('validrect.right', -14).to_i).to_i
      if wpx > 0
        line_width = wpx - origin_x
      elsif wpx < 0
        line_width = @width - origin_x + wpx
      else
        line_width = @width - origin_x * 2
      end
      wpy = __get('validrect.bottom', -14).to_i
      if wpy > 0
        text_height = [wpy, @height].min - origin_y
      elsif wpy < 0
        text_height = @height - origin_y + wpy
      else
        text_height = @height - origin_y * 2
      end
      line_height = @font_height + @line_space
      @lines = (text_height / line_height).to_i
      @line_regions = []
      y = origin_y
      for _ in 0..@lines
        @line_regions << [origin_x, y, line_width, line_height]
        y = y + line_height
      end
      @line_width = line_width
      # sstp message region
      if @side == 0
        w, h = @sstp_layout.pixel_size
        x, y = @sstp[1]
        w = line_width + origin_x - x
        @sstp_region = [x, y, w, h]
      end
    end

    def update_line_regions(offset, new_y)
      origin_y = __get('origin.y',
                       __get('zeropoint.y',
                             __get('validrect.top', 14).to_i).to_i).to_i
      wpy = __get('validrect.bottom', -14).to_i
      if wpy > 0
        text_height = [wpy, @height].min - origin_y
      elsif wpy < 0
        text_height = @height - origin_y + wpy
      else
        text_height = @height - origin_y * 2
      end
      line_height = @font_height + @line_space
      origin_x, y, line_width, line_height = @line_regions[offset]
      @lines = offset + ((text_height - new_y) / line_height).to_i
      y = new_y
      for i in offset..(@line_regions.length - 1)
        @line_regions[i] = [origin_x, y, line_width, line_height]
        y += line_height
      end
      for i in @line_regions.length..@lines
        @line_regions << [origin_x, y, line_width, line_height]
        y += line_height
      end
    end

    def get_balloon_size(scaling: true)
      w = @width
      h = @height
      if scaling
        w = (w * scale / 100.0).to_i
        h = (h * scale / 100.0).to_i
      end
      return w, h
    end

    def reset_balloon
      set_balloon(@num)
    end

    def set_balloon(num)
      @num = num
      balloon_id = @id_format + (num * 2 + @__direction).to_i.to_s
      @balloon_surface = get_image_surface(balloon_id)
      if @balloon_surface == nil
        balloon_id = @id_format + (0 + @__direction).to_i.to_s
        @balloon_surface = get_image_surface(balloon_id)
      end
      raise "assert" unless @balloon_surface != nil
      @balloon_id = balloon_id
      # change surface and window position
      x, y = @position
      @width = @balloon_surface.width
      @height = @balloon_surface.height
      w = (@width * scale / 100.0).to_i
      h = (@height * scale / 100.0).to_i
      @window.update_size(w, h)
      reset_arrow()
      reset_sstp_marker()
      reset_message_regions()
      @parent.handle_request('NOTIFY', 'position_balloons')
      if @__shown
        @darea.queue_draw()
      end
    end

    def set_autoscroll(flag)
      @autoscroll = flag
    end

    def config_adjust(name, base, default_value)
      path, config = @balloon[@balloon_id]
      value = config.get(name).to_i
      if value == nil
        value = @desc.get(name).to_i
      end
      if value == nil
        value = default_value
      end
      if value < 0
        value = base + value
      end
      return value.to_i
    end

    def __get(name, default_value)
      path, config = @balloon[@balloon_id]
      value = config.get(name)
      if value == nil
        value = @desc.get(name)
        if value == nil
          value = default_value
        end
      end
      return value
    end

    def __get_with_scaling(name, default_value)
      path, config = @balloon[@balloon_id]
      value = config.get(name)
      if value == nil
        value = @desc.get(name)
        if value == nil
          value = default_value
        end
      end
      return (value.to_f * scale / 100)
    end

    def __move
      x, y = get_position()
      @window.move(x, y)
    end

    def set_position(base_x, base_y)
      if @balloon_id == nil
        return
      end
      px, py = get_balloon_windowposition()
      w, h = get_balloon_size()
      if @__direction == 0
        x = base_x + px - w
      else
        x = base_x + px
      end
      y = base_y + py
      left, top, scrn_w, scrn_h = Pix.get_workarea()
      if y + h > scrn_h # XXX
        y = scrn_h - h
      end
      if y < top # XXX
        y = top
      end
      @position = [x, y]
      __move()
    end

    def get_position
      return @position
    end

    def destroy(finalize: 0)
      @window.destroy()
    end

    def is_shown
      return @__shown
    end

    def show
      if @parent.handle_request('GET', 'lock_repaint')
        return
      end
      if @__shown
        return
      end
      @__shown = true
      # make sure window is in its position (call before showing the window)
      __move()
      @window.show()
      # make sure window is in its position (call after showing the window)
      __move()
      raise_()
    end

    def hide
      if not @__shown
        return
      end
      @window.hide()
      @__shown = false
      @images = []
    end

    def raise_
      if @__shown
        @window.window.raise
      end
    end

    def lower
      if @__shown
        @window.get_window().lower()
      end
    end

    def show_sstp_message(message, sender)
      if @sstp_region == nil
        show()
      end
      @sstp_message = message.to_s + " (" + sender.to_s + ")"
      x, y, w, h = @sstp_region
      @sstp_layout.set_text(@sstp_message)
      message_width, message_height = @sstp_layout.pixel_size
      if message_width > w
        @sstp_message = '... (' + sender + ')'
        i = 0
        while true
          i += 1
          s = message[0, i] + '... (' + sender + ')'
          @sstp_layout.set_text(s)
          message_width, message_height = \
          @sstp_layout.pixel_size
          if message_width > w
            break
          end
          @sstp_message = s
        end
      end
      @darea.queue_draw()
    end

    def hide_sstp_message
      @sstp_message = nil
      @darea.queue_draw()
    end

    def redraw_sstp_message(widget, cr)
      if @sstp_message == nil
        return
      end
      cr.save()
      # draw sstp marker
      if @sstp_surface != nil
        x, y = @sstp[0]            
        cr.set_source(@sstp_surface, x, y)
        cr.paint()
      end
      # draw sstp message
      x, y, w, h = @sstp_region
      @sstp_layout.set_text(@sstp_message)
      cr.set_source_rgb(@sstp_message_color)
      cr.move_to(x, y)
      cr.show_pango_layout(@sstp_layout)
      cr.restore()
    end

    def redraw_arrow0(widget, cr)
      if @lineno <= 0
        return
      end
      cr.save()
      x, y = @arrow[0]
      cr.set_source(@arrow0_surface, x, y)
      cr.paint()
      cr.restore()
    end

    def redraw_arrow1(widget, cr)
      if @lineno + @lines >= @text_buffer.length
        return
      end
      cr.save()
      x, y = @arrow[1]
      cr.set_source(@arrow1_surface, x, y)
      cr.paint()
      cr.restore()
    end

    def markup_escape_text(markup_string) ## FIXME: GLib::Markup.escape_text
      escaped_string = markup_string.dup
      {
        '<' => '&lt;',
        '>' => '&gt;',
        '&' => '&amp;'
      }.each do |pattern, replace|
        escaped_string.gsub!(pattern, replace)
      end
      return escaped_string
    end

    def set_markup(index, text)
      tags_ = ['sup', 'sub', 's', 'u']
      count_ = {}
      for tag_ in tags_
        count_[tag_] = 0
      end
      markup_list = []
      for sl, sn, tag in @meta_buffer
        if sl == index
          markup_list << [sn, tag]
        end
      end
      if markup_list.empty?
        return markup_escape_text(text)
      end
      markup_list.sort()
      markup_list.reverse()
      pn = text.length
      for sn, tag in markup_list
        text = [text[0, sn], tag,
                markup_escape_text(text[sn, pn]),
                text[pn, text.length]].join('')
        pn = sn
        if tag[1] == '/'
          tag_ = tag[2, tag.length - 1]
          raise "assert" unless tags_.include?(tag_)
          count_[tag_] -= 1
          if count_[tag_] < 0
            text = ['<', tag_, '>', text].join('')
            count_[tag_] += 1
          end
        else
          tag_ = tag[1, tag.length - 1]
          raise "assert" unless tags_.include?(tag_)
          count_[tag_] += 1
          if count_[tag_] > 0
            text = [text, '</', tag_, '>'].join('')
            count_[tag_] -= 1
          end
        end
      end
      return text
    end

    def redraw(widget, cr)
      if @parent.handle_request('GET', 'lock_repaint')
        return
      end
      if not @__shown
        return true
      end
      raise "assert" unless @balloon_surface != nil
      @window.set_surface(cr, @balloon_surface, scale)
      cr.set_operator(Cairo::OPERATOR_OVER) # restore default
      cr.translate(*@window.get_draw_offset) # XXX
      # draw images
      for i in 0..(@images.length - 1)
        image_surface, (x, y) = @images[i]
        w = image_surface.width
        h = image_surface.height
        if x == 'centerx'
          bw, bh = get_balloon_size(:scaling => false)
          x = (bw - w) / 2
        else
          begin
            x = Integer(x)
          rescue
            next
          end
        end
        if y == 'centery'
          bw, bh = get_balloon_size(:scaling => false)
          y = (bh - h) / 2
        else
          begin
            y = Integer(y)
          rescue
            next
          end
        end
        cr.set_source(image_surface, x, y)
        cr.paint()
      end
      # draw text
      i = @lineno
      j = @text_buffer.length
      line = 0
      while line < @lines
        if i >= j
          break
        end
        x, y, w, h = @line_regions[line]
        if @text_buffer[i].end_with?('\n[half]')
          temp = @text_buffer[i]
          new_y = y
          while temp.end_with?('\n[half]')
            new_y += ((@font_height + @line_space) / 2).to_i
            temp = temp[0..-9]
          end
          markup = set_markup(i, temp)
        else
          new_y = (y + @font_height + @line_space).to_i
          markup = set_markup(i, @text_buffer[i])
        end
        update_line_regions(line + 1, new_y)
        @layout.set_markup(markup, -1)
        cr.set_source_rgb(@text_normal_color)
        cr.move_to(x, y)
        cr.show_pango_layout(@layout)
        if @sstp_surface != nil
          for l, c in @sstp_marker
            if l == i
              mw = @sstp_surface.width
              mh = @sstp_surface.height
              @layout.set_text(@text_buffer[i][0, c])
              text_w, text_h = @layout.pixel_size
              mx = x + text_w
              my = y + (@font_height + @line_space) / 2
              my = my - mh / 2
              cr.set_source(@sstp_surface, mx, my)
              cr.paint()
            end
          end
        end
        i += 1
        line += 1
      end
      if @side == 0 and @sstp_message != nil
        redraw_sstp_message(widget, cr)
      end
      if @selection != nil
        update_link_region(widget, cr, @selection)
      end
      redraw_arrow0(widget, cr)
      redraw_arrow1(widget, cr)
      @window.set_shape(cr)
      return false
    end

    def update_link_region(widget, cr, index)
      cr.save()
      sl = @link_buffer[index][0]
      el = @link_buffer[index][2]
      if @lineno <= sl and sl <= @lineno + @lines
        sn = @link_buffer[index][1]
        en = @link_buffer[index][3]
        for n in sl..el
          if n - @lineno >= @line_regions.length
            break
          end
          x, y, w, h = @line_regions[n - @lineno]
          if sl == el
            markup = set_markup(n, @text_buffer[n][0, sn])
            @layout.set_markup(markup, -1)
            text_w, text_h =  @layout.pixel_size
            x += text_w
            markup = set_markup(n, @text_buffer[n][sn, en])
            @layout.set_markup(markup, -1)
            text_w, text_h = @layout.pixel_size
            w = text_w
            start = sn
            end_ = en
          elsif n == sl
            markup = set_markup(n, @text_buffer[n][0, sn])
            @layout.set_markup(markup, -1)
            text_w, text_h = @layout.pixel_size
            x += text_w
            markup = set_markup(n, @text_buffer[n][sn, @text_buffer.length])
            @layout.set_markup(markup, -1)
            text_w, text_h = @layout.pixel_size
            w = text_w
            start = sn
            end_ = @text_buffer[n].length
          elsif n == el
            markup = set_markup(n, @text_buffer[n][0, en])
            @layout.set_markup(markup, -1)
            text_w, text_h = @layout.pixel_size
            w = text_w
            start = 0
            end_ = en
          else
            markup = set_markup(n, @text_buffer[n])
            @layout.set_markup(markup, -1)
            text_w, text_h = @layout.pixel_size
            w = text_w
            start = 0
            end_ = @text_buffer[n].length
          end
          markup = set_markup(n, @text_buffer[n][start, end_])
          @layout.set_markup(markup, -1)
          cr.set_source_rgb(@cursor_color)
          cr.rectangle(x, y, w, h)
          cr.fill()
          cr.move_to(x, y)
          cr.set_source_rgb(@text_active_color)
          cr.show_pango_layout(@layout)
        end
      end
      cr.restore()
    end

    def check_link_region(px, py)
      new_selection = nil
      for i in 0..(@link_buffer.length - 1)
        sl = @link_buffer[i][0]
        el = @link_buffer[i][2]
        if @lineno <= sl and sl <= @lineno + @lines
          sn = @link_buffer[i][1]
          en = @link_buffer[i][3]
          for n in sl..el
            if n - @lineno >= @line_regions.length
              break
            end
            x, y, w, h = @line_regions[n - @lineno]
            if n == sl
              markup = set_markup(n, @text_buffer[n][0, sn])
              @layout.set_markup(markup, -1)
              text_w, text_h = @layout.pixel_size
              x += text_w
            end
            if n == sl and n == el
              markup = set_markup(n, @text_buffer[n][sn, en])
            elsif n == el
              markup = set_markup(n, @text_buffer[n][0, en])
            else
              markup = set_markup(n, @text_buffer[n])
            end
            @layout.set_markup(markup, -1)
            text_w, text_h = @layout.pixel_size
            w = text_w
            if x <= px and px < x + w and y <= py and py < y + h
              new_selection = i
              break
            end
          end
        end
      end
      if new_selection != nil
        if @selection != new_selection
          sl, sn, el, en, link_id, raw_text, text = \
          @link_buffer[new_selection]
          @parent.handle_request(
            'NOTIFY', 'notify_event',
            'OnChoiceEnter', raw_text, link_id, @selection)
        end
      else
        if @selection != nil
          @parent.handle_request('NOTIFY', 'notify_event', 'OnChoiceEnter')
        end
      end
      if new_selection == @selection
        return false
      else
        @selection = new_selection
        return true # dirty flag
      end
    end

    def motion_notify(widget, event)
      if event.is_hint == 1
        _, x, y, state = widget.window.get_device_position(event.device)
      else
        x, y, state = event.x, event.y, event.state
      end
      px, py = @window.winpos_to_surfacepos(x, y, scale)
      if not @link_buffer.empty?
        if check_link_region(px, py)
          widget.queue_draw()
        end
      end
      if not @parent.handle_request('GET', 'busy')
        if (state & Gdk::ModifierType::BUTTON1_MASK).nonzero?
          if @x_root != nil and \
            @y_root != nil
            @dragged = true
            x_delta = (event.x_root - @x_root) * 100 / scale + @x_fractions
            y_delta = (event.y_root - @y_root) * 100 / scale + @y_fractions
            @x_fractions = x_delta - x_delta.to_i
            @y_fractions = y_delta - y_delta.to_i
            @parent.handle_request(
              'NOTIFY', 'update_balloon_offset',
              @side, x_delta.to_i, y_delta.to_i)
            @x_root = event.x_root
            @y_root = event.y_root
          end
        end
      end
      return true
    end

    def scroll(darea, event)
      px, py = @window.winpos_to_surfacepos(
            event.x.to_i, event.y.to_i, scale)
      if event.direction == Gdk::ScrollDirection::UP
        if @lineno > 0
          @lineno = [@lineno - 2, 0].max
          check_link_region(px, py)
          @darea.queue_draw()
        end
      elsif event.direction == Gdk::ScrollDirection::DOWN
        if @lineno + @lines < @text_buffer.length
          @lineno = [@lineno + 2,
                     @text_buffer.length - @lines].min
          check_link_region(px, py)
          @darea.queue_draw()
        end
      end
      return true
    end

    def button_press(darea, event)
      @parent.handle_request('NOTIFY', 'reset_idle_time')
      if event.event_type == Gdk::EventType::BUTTON_PRESS
        click = 1
      else
        click = 2
      end
      if @parent.handle_request('GET', 'is_paused')
        @parent.handle_request('NOTIFY', 'notify_balloon_click',
                               event.button, click, @side)
        return true
      end
      # arrows
      px, py = @window.winpos_to_surfacepos(
            event.x.to_i, event.y.to_i, scale)
      # up arrow
      w = @arrow0_surface.width
      h = @arrow0_surface.height
      x, y = @arrow[0]
      if x <= px and px <= x + w and y <= py and py <= y + h
        if @lineno > 0
          @lineno = [@lineno - 2, 0].max
          @darea.queue_draw()
        end
        return true
      end
      # down arrow
      w = @arrow1_surface.width
      h = @arrow1_surface.height
      x, y = @arrow[1]
      if x <= px and px <= x + w and y <= py and py <= y + h
        if @lineno + @lines < @text_buffer.length
          @lineno = [@lineno + 2,
                     @text_buffer.length - @lines].min
          @darea.queue_draw()
        end
        return true
      end
      # links
      if @selection != nil
        sl, sn, el, en, link_id, raw_text, text = \
        @link_buffer[@selection]
        @parent.handle_request('NOTIFY', 'notify_link_selection',
                               link_id, raw_text, @selection)
        return true
      end
      # balloon's background
      @parent.handle_request('NOTIFY', 'notify_balloon_click',
                             event.button, click, @side)
      @x_root = event.x_root
      @y_root = event.y_root
      return true
    end

    def button_release(window, event)
      x, y = @window.winpos_to_surfacepos(
           event.x.to_i, event.y.to_i, scale)
      if @dragged
        @dragged = false
      end
      @x_root = nil
      @y_root = nil
      @y_fractions = 0
      @y_fractions = 0
      return true
    end

    def clear_text
      @selection = nil
      @lineno = 0
      @text_buffer = []
      @meta_buffer = []
      @link_buffer = []
      @newline_required = false
      @images = []
      @sstp_marker = []
      @darea.queue_draw()
    end

    def get_text_count
      return @text_count
    end

    def reset_text_count
      @text_count = 0
    end

    def set_newline
      @newline_required = true
    end

    def append_text(text)
      if @text_buffer.empty?
        s = ''
        column = 0
        index = 0
      elsif @newline_required
        s = ''
        column = 0
        @newline_required = false
        index = @text_buffer.length
      else
        index = @text_buffer.length - 1
        s = @text_buffer.pop
        column = s.length
      end
      i = s.length
      text = [s, text].join('')
      j = text.length
      @text_count += j
      p = 0
      while true
        if i >= j
          @text_buffer << text[p..i-1]
          draw_last_line(:column => column)
          break
        end
        if text[i, 2] == '\n'
          if j >= i + 8 and text[i, 8] == '\n[half]'
            @text_buffer << [text[p..i-1], '\n[half]'].join('')
            p = i = i + 8
          else
            if i == 0
              @text_buffer << ""
            else
              @text_buffer << text[p..i-1]
            end
            p = i = i + 2
          end
          draw_last_line(:column => column)
          column = 0
          next
        end
        n = i + 1
        if not @__shown
          show()
        end
        markup = set_markup(index, text[p..n-1])
        @layout.set_markup(markup, -1)
        text_width, text_height =  @layout.pixel_size
        if text_width > @line_width
          @text_buffer << text[p..i-1]
          draw_last_line(:column => column)
          column = 0
          p = i
        end
        i = n
      end
    end

    def append_sstp_marker
      if @sstp_surface != nil
        return
      end
      if @text_buffer.empty?
        line = 0
        offset = 0
      else
        line = @text_buffer.length - 1
        offset = @text_buffer[-1].length
      end
      if @newline_required
        line = line + 1
        offset = 0
      end
      @sstp_marker << [line, offset]
      w = @sstp_surface.width
      h = @sstp_surface.height
      i = 1
      while true
        space = "\u3000" * i # XXX
        @layout.set_text(space)
        text_w, text_h = @layout.pixel_size
        if text_w > w
          break
        else
          i += 1
        end
      end
      append_text(space)
      draw_last_line(:column => offset)
    end

    def append_link_in(link_id)
      if @text_buffer.empty?
        sl = 0
        sn = 0
      else
        sl = @text_buffer.length - 1
        sn = @text_buffer[-1].length
      end
      @link_buffer << [sl, sn, sl, sn, link_id, '', '']
    end

    def append_link_out(link_id, text)
      if not text
        return
      end
      raw_text = text
      if @text_buffer.empty?
        el = 0
        en = 0
      else
        el = @text_buffer.length - 1
        en = @text_buffer[-1].length
      end
      for i in 0..@link_buffer.length-1
        if @link_buffer[i][4] == link_id
          sl = @link_buffer[i][0]
          sn = @link_buffer[i][1]
          @link_buffer.slice!(i)
          @link_buffer.insert(i, [sl, sn, el, en, link_id, raw_text, text])
          break
        end
      end
    end

    def append_meta(tag)
      if tag == nil
        return
      end
      if @text_buffer.empty?
        sl = 0
        sn = 0
      else
        sl = @text_buffer.length - 1
        sn = @text_buffer[-1].length
      end
      @meta_buffer << [sl, sn, tag]
    end

    def append_image(path, x, y)
      begin
        image_surface = Pix.create_surface_from_file(path)
      rescue
        return
      end
      show()
      @images << [image_surface, [x, y]]
      @darea.queue_draw()
    end

    def draw_last_line(column: 0)
      if not @__shown
        return
      end
      line = @text_buffer.length - 1
      if @lineno <= line and line < @lineno + @lines
        x, y, w, h = @line_regions[line - @lineno]
        if @text_buffer[line].end_with?('\n[half]')
          offset = line - @lineno + 1
          new_y = (y + (@font_height + @line_space) / 2).to_i
          update_line_regions(offset, new_y)
        else
          @darea.queue_draw()
        end
        if @sstp_surface != nil
          for l, c in @sstp_marker
            if l == line
              mw = @sstp_surface.width
              mh = @sstp_surface.height
              @layout.set_text(@text_buffer[l][0, c])
              text_w, text_h = @layout.pixel_size
              mx = x + text_w
              my = y + (@font_height + @line_space) / 2
              my = my - mh / 2
              cr = @darea.get_window().cairo_create()
              cr.set_source(@sstp_surface, mx, my)
              cr.paint()
            end
          end
        end
      else
        @darea.queue_draw()
        if @autoscroll
          while line >= @lineno + @lines
            @lineno += 1
            @darea.queue_draw()
          end
        end
      end
    end
  end


  class CommunicateWindow

    NAME = ''
    ENTRY = ''

    def initialize
      @parent = nil
      @window = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def new_(desc, balloon)
      if @window != nil
        @window.destroy()
      end
      @window = Pix::BaseTransparentWindow.new()
      @window.set_title('communicate')
      @window.signal_connect('delete_event') do |w ,e|
        delete(w, e)
        next true
      end
      @window.signal_connect('key_press_event') do |w, e|
        key_press(w, e)
        next true
      end
      @window.signal_connect('button_press_event') do |w, e|
        button_press(w, e)
        next true
      end
      @window.signal_connect('drag_data_received') do |widget, context, x, y, data, info, time|
        drag_data_received(widget, context, x, y, data, info, time)
        next true
      end
      # DnD data types
      dnd_targets = [['text/plain', 0, 0]]
      @window.drag_dest_set(Gtk::Drag::DestDefaults::ALL, dnd_targets,
                            Gdk::DragAction::COPY)
      @window.drag_dest_add_text_targets()
      @window.set_events(Gdk::EventMask::BUTTON_PRESS_MASK)
      @window.set_modal(true)
      @window.set_window_position(Gtk::Window::Position::CENTER)
      @window.realize()
      w = desc.get('communicatebox.width', :default => 250).to_i
      h = desc.get('communicatebox.height', :default => -1).to_i
      @entry = Gtk::Entry.new
      @entry.signal_connect('activate') do |w|
        activate(w)
        next true
      end
      @entry.set_inner_border(nil)
      @entry.set_has_frame(false)
      font_desc = Pango::FontDescription.new()
      font_desc.set_size(9 * 3 / 4 * Pango::SCALE) # XXX
      @entry.override_font(font_desc)
      @entry.set_size_request(w, h)
      @entry.show()
      surface = nil
      if balloon != nil
        path, config = balloon
        # load pixbuf
        begin
          surface = Pix.create_surface_from_file(path)
        rescue
          surface = nil
        end
      end
      if surface != nil
        darea = Gtk::DrawingArea.new()
        darea.set_events(Gdk::EventMask::EXPOSURE_MASK)
        darea.signal_connect('draw') do |w, e|
          redraw(w, e, surface)
          next true
        end
        darea.show()
        x = desc.get('communicatebox.x', :default => 10).to_i
        y = desc.get('communicatebox.y', :default => 20).to_i
        overlay = Gtk::Overlay.new()
        @entry.set_margin_left(x)
        @entry.set_margin_top(y)
        @entry.set_halign(Gtk::Alignment::Align::START)
        @entry.set_valign(Gtk::Alignment::Align::START)
        overlay.add_overlay(@entry)
        overlay.add(darea)
        overlay.show()
        @window.add(overlay)
        w = surface.width
        h = surface.height
        darea.set_size_request(w, h)
      else
        box = Gtk::Box.new(orientation=Gtk::Orientation::HORIZONTAL, spacing=10)
        box.set_border_width(10)
        if not ENTRY.empty?
          label = Gtk::Label.new(label=ENTRY)
          box.pack_start(label, :expand => false, :fill => true, :padding => 0)
          label.show()
        end
        box.pack_start(@entry, :expand => true, :fill => true, :padding => 0)
        @window.add(box)
        box.show()
      end
    end

    def drag_data_received(widget, context, x, y, data, info, time)
      @entry.set_text(data.text)
    end

    def redraw(widget, cr, surface)
      cr.set_source(surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint()
      w, h = @window.size
      region = Pix.surface_to_region(cr.target.map_to_image)
      # XXX: to avoid losing focus in the text input region
      x = @entry.margin_left
      y = @entry.margin_top
      w = @entry.allocated_width
      h = @entry.allocated_height
      region.union!(x, y, w, h)
      @window.input_shape_combine_region(region)
    end

    def destroy
      if @window != nil
        @window.destroy()
        @window = nil
      end
    end

    def delete(widget, event)
      @window.hide()
      cancel()
      return true
    end

    def key_press(widget, event)
      if event.keyval == Gdk::Keyval::KEY_Escape
        @window.hide()
        cancel()
        return true
      end
      return false
    end

    def button_press(widget, event)
      if [1, 2].include?(event.button)
        @window.begin_move_drag(
          event.button, event.x_root.to_i, event.y_root.to_i,
          Gtk.current_event_time())
      end
      return true
    end

    def activate(widget)
      @window.hide()
      enter()
      return true
    end

    def show(default: '')
      @entry.set_text(default)
      @window.show()
    end

    def enter
      #pass
    end

    def cancel
      #pass
    end
  end


  class CommunicateBox < CommunicateWindow

    NAME = 'communicatebox'
    ENTRY = 'Communicate'

    def new_(desc, balloon)
      super
      @window.set_modal(false)
    end

    def delete(widget, event)
      @window.hide()
      cancel()
      @parent.handle_request('NOTIFY', 'reset_user_interaction')
      return true
    end

    def key_press(widget, event)
      if event.keyval == Gdk::Keyval::KEY_Escape
        @window.hide()
        cancel()
        @parent.handle_request('NOTIFY', 'reset_user_interaction')
        return true
      end
      return false
    end

    def activate(widget)
      enter()
      @entry.set_text('')
      return true
    end

    def enter
      send(@entry.text)
    end

    def cancel
      @parent.handle_request('NOTIFY', 'notify_event',
                             'OnCommunicateInputCancel', '', 'cancel')
    end

    def send(data)
      if data != nil
        @parent.handle_request('NOTIFY', 'notify_event',
                               'OnCommunicate', 'user', data)
      end
    end
  end

  class TeachBox < CommunicateWindow

    NAME = 'teachbox'
    ENTRY = 'Teach'

    def enter
      send(@entry.text)
    end

    def cancel
      @parent.handle_request('NOTIFY', 'notify_event',
                             'OnTeachInputCancel', '', 'cancel')
      @parent.handle_request('NOTIFY', 'reset_user_interaction')
    end

    def send(data)
      @parent.handle_request('NOTIFY', 'notify_user_teach', data)
      @parent.handle_request('NOTIFY', 'reset_user_interaction')
    end
  end


  class InputBox < CommunicateWindow

    NAME = 'inputbox'
    ENTRY = 'Input'

    def new_(desc, balloon)
      super
      @symbol = nil
      @limittime = -1
    end

    def set_symbol(symbol)
      @symbol = symbol
    end
        
    def set_limittime(limittime)
      begin
        limittime = Integer(limittime)
      rescue
        limittime = -1
      end
      @limittime = limittime
    end

    def show(default)
      if default != nil
        begin
          text = default.to_s
        rescue
          text = ''
        end
      else
        text = ''
      end
      if @limittime.to_i < 0
        @timeout_id = nil
      else
        @timeout_id = GLib.timeout_add(@limittime, @timeout)
      end
      super(:default => text)
    end

    def timeout
      @window.hide()
      send('timeout', :timeout => true)
    end

    def enter
      send(@entry.text)
    end

    def cancel
      send(nil, :cancel => true)
    end

    def close(symbol)
      if @symbol == nil
        return
      end
      if symbol != '__SYSTEM_ALL_INPUT__' and @symbol != symbol
        return
      end
      @window.hide()
      cancel()
    end

    def send(data, cancel: false, timeout: false)
      if @timeout_id != nil
        GLib.source_remove(@timeout_id)
      end
      if data == nil
        data = ''
      end
      ## CHECK: symbol
      if cancel
        @parent.handle_request('NOTIFY', 'notify_event',
                               'OnUserInputCancel', '', 'cancel')
      elsif timeout and \
        @parent.handle_request('GET', 'notify_event',
                               'OnUserInputCancel', '', 'timeout') != nil
        # pass
      elsif @symbol == 'OnUserInput' and \
           @parent.handle_request('GET', 'notify_event', 'OnUserInput', data) != nil
        # pass
      elsif @parent.handle_request('GET', 'notify_event',
                                   'OnUserInput', @symbol, data) != nil
        # pass
      elsif @parent.handle_request('GET', 'notify_event', @symbol, data) != nil
        # pass
      end
      @symbol = nil
      @parent.handle_request('NOTIFY', 'reset_user_interaction')
    end
  end

  class PasswordInputBox < InputBox

    NAME = 'passwordinputbox'
    ENTRY = 'PasswordInput'

    def new_(desc, balloon)
      super
      @entry.set_visibility(false)
    end
  end
end
