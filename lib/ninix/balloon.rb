# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"
require "cgi"

require_relative "pix"
require_relative "metamagic"

module Balloon

  TYPE_UNKNOWN = 0
  TYPE_TEXT = 1
  TYPE_IMAGE = 2

  class Balloon < MetaMagic::Holon
    attr_accessor :window, :user_interaction

    def initialize
      super("") # FIXME
      @handlers = {
        'reset_user_interaction' => 'reset_user_interaction',
      }
      @synchronized = []
      @user_interaction = false
      @window = {}
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

    def reset_user_interaction
      @user_interaction = false
    end

    def get_text_count(side)
      add_window(side) unless @window.include?(side)
      return @window[side].get_text_count()
    end

    def get_window(side)
      add_window(side) unless @window.include?(side)
      return @window[side].get_window
    end

    def reset_text_count(side)
      add_window(side) unless @window.include?(side)
      @window[side].reset_text_count()
    end

    def reset_balloon
      for balloon_window in @window.values
        balloon_window.reset_balloon()
      end
    end

    def create_gtk_window(title)
      window = Pix::TransparentWindow.new()
      window.set_title(title)
      window.set_skip_pager_hint(false)
      window.set_skip_taskbar_hint(true)
      window.signal_connect('delete_event') do |w, e|
        next delete(w, e)
      end
      window.realize()
      return window
    end

    def identify_window(win)
      for balloon_window in @window.values
        return true if win == balloon_window.get_window.window
      end
      return false
    end

    def delete(window, event)
      return true
    end

    def finalize
      for balloon_window in @window.values
        balloon_window.destroy()
      end
      @window = {}
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
      for balloon_window in @window.values
        balloon_window.destroy()
      end
      @window = {}
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
      return if @window.include?(side)
      case side
      when 0
        name = 'balloon.sakura'
        id_format = 's'
        balloon = @balloon0
      when 1
        name = 'balloon.kero'
        id_format = 'k'
        balloon = @balloon1
      else
        name = ('balloon.char' + side.to_s)
        id_format = 'k'
        balloon = @balloon1
      end
      gtk_window = create_gtk_window(name)
      balloon_window = BalloonWindow.new(
        gtk_window, side, @desc, balloon, id_format)
      balloon_window.set_responsible(self)
      balloon_window.reset_fonts()
      @window[side] = balloon_window
    end

    def reset_fonts
      for window in @window.values
        window.reset_fonts()
      end
    end

    def get_balloon_directory
      @directory
    end

    def get_balloon_size(side)
      add_window(side) unless @window.include?(side)
      return @window[side].get_balloon_size()
    end

    def get_balloon_windowposition(side)
      add_window(side) unless @window.include?(side)
      return @window[side].get_balloon_windowposition()
    end

    def set_balloon_default(side: -1)
      default_id = @parent.handle_request('GET', 'get_balloon_default_id')
      begin
        default_id = Integer(default_id)
      rescue
        default_id = 0
      end
      if side >= 0
        @window[side].set_balloon_default(default_id)
      else
        for side in @window.keys
          @window[side].set_balloon(default_id)
        end
      end
    end

    def set_balloon(side, num)
      add_window(side) unless @window.include?(side)
      @window[side].set_balloon(num)
    end

    def set_position(side, base_x, base_y)
      add_window(side) unless @window.include?(side)
      @window[side].set_position(base_x, base_y)
    end

    def get_position(side)
      add_window(side) unless @window.include?(side)
      return @window[side].get_position()
    end

    def set_autoscroll(flag)
      for side in @window.keys
        @window[side].set_autoscroll(flag)
      end
    end

    def is_shown(side)
      add_window(side) unless @window.include?(side)
      return @window[side].is_shown()
    end

    def show(side)
      add_window(side) unless @window.include?(side)
      @window[side].show()
    end

    def hide_all
      for side in @window.keys
        @window[side].hide()
      end
    end

    def hide(side)
      add_window(side) unless @window.include?(side)
      @window[side].hide()
    end

    def raise_all
      for side in @window.keys
        @window[side].raise_()
      end
    end

    def raise_(side)
      add_window(side) unless @window.include?(side)
      @window[side].raise_()
    end

    def lower_all
      for side in @window.keys
        @window[side].lower()
      end
    end

    def lower(side)
      add_window(side) unless @window.include?(side)
      @window[side].lower()
    end

    def synchronize(list)
      @synchronized = list
    end

    def clear_text_all
      for side in @window.keys
        clear_text(side)
      end
    end

    def clear_text(side)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].clear_text()
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].clear_text()
      end
    end

    def new_line(side)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].new_line
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].new_line
      end
    end

    def set_draw_absolute_x(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_absolute_x(pos)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_absolute_x(pos)
      end
    end

    def set_draw_absolute_x_char(side, rate)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_absolute_x_char(rate)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_absolute_x_char(rate)
      end
    end

    def set_draw_relative_x(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_relative_x(pos)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_relative_x(pos)
      end
    end

    def set_draw_relative_x_char(side, rate)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_relative_x(rate)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_relative_x(rate)
      end
    end

    def set_draw_absolute_y(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_absolute_y(pos)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_absolute_y(pos)
      end
    end

    def set_draw_absolute_y_char(side, rate, **kwarg)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_absolute_y_char(rate, **kwarg)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_absolute_y_char(rate, **kwarg)
      end
    end

    def set_draw_relative_y(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_relative_y(pos)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_relative_y(pos)
      end
    end

    def set_draw_relative_y_char(side, rate, **kwarg)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].set_draw_relative_y_char(rate, **kwarg)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].set_draw_relative_y_char(rate, **kwarg)
      end
    end

    def append_text(side, text)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].append_text(text)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].append_text(text)
      end
    end

    def append_sstp_marker(side)
      add_window(side) unless @window.include?(side)
      @window[side].append_sstp_marker()
    end

    def append_link_in(side, label, args)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].append_link_in(label, args)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].append_link_in(label, args)
      end
    end

    def append_link_out(side, label, value, args)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].append_link_out(label, value, args)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].append_link_out(label, value, args)
      end
    end

    def append_link(side, label, value, args)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].append_link_in(label, args)
          @window[side].append_text(value)
          @window[side].append_link_out(label, value, args)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].append_link_in(label, args)
        @window[side].append_text(value)
        @window[side].append_link_out(label, value, args)
      end
    end

    def append_meta(side, **kwargs)
      unless @synchronized.empty?
        for side in @synchronized
          add_window(side) unless @window.include?(side)
          @window[side].append_meta(**kwargs)
        end
      else
        add_window(side) unless @window.include?(side)
        @window[side].append_meta(**kwargs)
      end
    end

    def append_image(side, path, **kwargs)
      add_window(side) unless @window.include?(side)
      @window[side].append_image(path, **kwargs)
    end

    def show_sstp_message(message, sender)
      @window[0].show_sstp_message(message, sender)
    end

    def hide_sstp_message
      @window[0].hide_sstp_message()
    end

    def open_communicatebox
      return if @user_interaction
      @user_interaction = true
      @communicatebox.show()
    end

    def open_teachbox
      return if @user_interaction
      @user_interaction = true
      @parent.handle_request('NOTIFY', 'notify_event', 'OnTeachStart')
      @teachbox.show()
    end

    def open_inputbox(symbol, limittime: -1, default: nil)
      return if @user_interaction
      @user_interaction = true
      @inputbox.set_symbol(symbol)
      @inputbox.set_limittime(limittime)
      @inputbox.show(default)
    end

    def open_passwordinputbox(symbol, limittime: -1, default: nil)
      return if @user_interaction
      @user_interaction = true
      @passwordinputbox.set_symbol(symbol)
      @passwordinputbox.set_limittime(limittime)
      @passwordinputbox.show(default)
    end

    def close_inputbox(symbol)
      return unless @user_interaction
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
      @reshape = true
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
        #button_release(w, e)
        next true
      end
      @darea.signal_connect('motion_notify_event') do |w, e|
        next motion_notify(w, e)
      end
      @darea.signal_connect('scroll_event') do |w, e|
        next scroll(w, e)
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
        text_r = (255 - text_r)
        text_g = (255 - text_g)
        text_b = (255 - text_b)
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
      @window
    end

    def set_responsible(parent)
      @parent = parent
    end

    #@property
    def scale
      scaling = (not @parent.handle_request('GET', 'get_preference', 'balloon_scaling').zero?)
      scale = @parent.handle_request('GET', 'get_preference', 'surface_scale')
      if scaling
        return scale
      else
        return 100 # [%]
      end
    end

    def direction
      @__direction
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
      return nil unless @balloon.include?(balloon_id)
      begin
        path, config = @balloon[balloon_id]
        use_pna = (not @parent.handle_request('GET', 'get_preference', 'use_pna').zero?)
        surface = Pix.create_surface_from_file(path, :use_pna => use_pna)
      rescue
        return nil
      end
      return surface
    end

    def reset_fonts
      unless @parent.nil?
        font_name = @parent.handle_request('GET', 'get_preference', 'balloon_fonts')
      else
        font_name = nil
      end
      return if @__font_name == font_name
      @font_desc = Pango::FontDescription.new(font_name)
      pango_size = @font_desc.size
      if pango_size.zero?
        default_size = 12 # for Windows environment
        size = @desc.get(['font.height', 'font.size'], :default => default_size).to_i
        pango_size = (size * 3 / 4) # convert from Windows to GTK+
        pango_size *= Pango::SCALE
      end
      @font_desc.set_size(pango_size)
      @__font_name = font_name
      @layout.set_font_description(@font_desc)
      @layout.set_wrap(Pango::WrapMode::CHAR)
      # font for sstp message
      if @side.zero?
        @sstp_font_desc = Pango::FontDescription.new(font_name)
        pango_size = @sstp_font_desc.size
        if pango_size.zero?
          default_size = 10 # for Windows environment
          size = @desc.get('sstpmessage.font.height', :default => default_size).to_i
          pango_size = (size * 3 / 4) # convert from Windows to GTK+
          pango_size *= Pango::SCALE
        end
        @sstp_font_desc.set_size(pango_size)
        @sstp_layout.set_font_description(@sstp_font_desc)
        @sstp_layout.set_wrap(Pango::WrapMode::CHAR)
      end
      unless @balloon_id.nil?
        reset_message_regions()
        if @__shown
          @darea.queue_draw()
        end
      end
    end

    def reset_sstp_marker
      if @side.zero?
        fail "assert" if @balloon_surface.nil?
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
      # sstp marker surface (not only for @side.zero?)
      @sstp_surface = get_image_surface('sstp')
    end

    def reset_arrow
      # arrow positions
      @arrow = []
      fail "assert" if @balloon_surface.nil?
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
      @char_width = w
      @char_height = h
      fd = @layout.font_description
      if fd.size_is_absolute?
        @font_height = fd.size
      else
        @font_height = (fd.size / Pango::SCALE).to_i
      end
      @line_space = 0
      @layout.set_spacing(@line_space)
      # font metrics
      @origin_x = __get('origin.x',
                       __get('zeropoint.x',
                             __get('validrect.left', 14).to_i).to_i).to_i
      @origin_y = __get('origin.y',
                       __get('zeropoint.y',
                             __get('validrect.top', 14).to_i).to_i).to_i
      wpx = __get('wordwrappoint.x',
                  __get('validrect.right', -14).to_i).to_i
      @valid_rect_bottom = __get('validrect.bottom', -14).to_i
      if wpx > 0
        line_width = (wpx - @origin_x)
      elsif wpx < 0
        line_width = (@width - @origin_x + wpx)
      else
        line_width = (@width - @origin_x * 2)
      end
      vrb = @valid_rect_bottom
      if vrb > 0
        text_height = ([vrb, @height].min - @origin_y)
      elsif vrb < 0
        text_height = (@height - @origin_y + vrb)
      else
        text_height = (@height - @origin_y * 2)
      end
      @line_height = (@char_height + @line_space)
      @layout.set_width(line_width * Pango::SCALE)
      @valid_width = line_width
      @valid_height = text_height
      @lines = (text_height / @line_height).to_i
      y = @origin_y
      @line_width = line_width
      # sstp message region
      if @side.zero?
        w, h = @sstp_layout.pixel_size
        x, y = @sstp[1]
        w = (line_width + @origin_x - x)
        @sstp_region = [x, y, w, h]
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

    def set_balloon_default(num)
      set_balloon(num) if @balloon_id.nil?
    end

    def set_balloon(num)
      @num = num
      balloon_id = (@id_format + (num * 2 + @__direction).to_i.to_s)
      @balloon_surface = get_image_surface(balloon_id)
      if @balloon_surface.nil?
        balloon_id = (@id_format + (0 + @__direction).to_i.to_s)
        @balloon_surface = get_image_surface(balloon_id)
      end
      fail "assert" if @balloon_surface.nil?
      @balloon_id = balloon_id
      # change surface and window position
      x, y = @position
      @width = @balloon_surface.width
      @height = @balloon_surface.height
      reset_arrow()
      reset_sstp_marker()
      reset_message_regions()
      @parent.handle_request('NOTIFY', 'position_balloons')
      @darea.queue_draw() if @__shown
      @reshape = true
    end

    def set_autoscroll(flag)
      @autoscroll = flag
    end

    def config_adjust(name, base, default_value)
      path, config = @balloon[@balloon_id]
      value = config.get(name)
      if value.nil?
        value = @desc.get(name)
      end
      if value.nil?
        value = default_value
      end
      value = value.to_i
      if value < 0
        value = (base + value)
      end
      return value.to_i
    end

    def __get(name, default_value)
      path, config = @balloon[@balloon_id]
      value = config.get(name)
      if value.nil?
        value = @desc.get(name)
        if value.nil?
          value = default_value
        end
      end
      return value
    end

    def __get_with_scaling(name, default_value)
      path, config = @balloon[@balloon_id]
      value = config.get(name)
      if value.nil?
        value = @desc.get(name)
        if value.nil?
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
      return if @balloon_id.nil?
      px, py = get_balloon_windowposition()
      w, h = get_balloon_size()
      x = (base_x + px - w)
      y = (base_y + py)
      left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
      if (y + h) > scrn_h # XXX
        y = (scrn_h - h)
      end
      if y < top # XXX
        y = top
      end
      @position = [x, y]
      __move()
    end

    def get_position
      @position
    end

    def destroy(finalize: 0)
      @window.destroy()
    end

    def is_shown
      @__shown
    end

    def show
      return if @parent.handle_request('GET', 'lock_repaint')
      return if @__shown
      @__shown = true
      # make sure window is in its position (call before showing the window)
      __move()
      @window.show()
      # make sure window is in its position (call after showing the window)
      __move()
      raise_()
      @reshape = true
    end

    def hide
      return unless @__shown
      @window.hide()
      @__shown = false
      @images = []
    end

    def raise_
      return unless @__shown
      @window.window.raise
    end

    def lower
      return unless @__shown
      @window.get_window().lower()
    end

    def show_sstp_message(message, sender)
      show() if @sstp_region.nil?
      @sstp_message = (message.to_s + " (" + sender.to_s + ")")
      x, y, w, h = @sstp_region
      @sstp_layout.set_text(@sstp_message)
      message_width, message_height = @sstp_layout.pixel_size
      if message_width > w
        @sstp_message = ('... (' + sender + ')')
        i = 0
        while true
          i += 1
          s = (message[0, i] + '... (' + sender + ')')
          @sstp_layout.set_text(s)
          message_width, message_height = \
          @sstp_layout.pixel_size
          break if message_width > w
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
      return if @sstp_message.nil?
      cr.save()
      # draw sstp marker
      unless @sstp_surface.nil?
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
      return if @lineno <= 0
      cr.save()
      x, y = @arrow[0]
      cr.set_source(@arrow0_surface, x, y)
      cr.paint()
      cr.restore()
    end

    def redraw_arrow1(widget, cr)
      return if get_bottom_position < @valid_height
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

    def set_markup(text, a)
      text = CGI.escapeHTML(text)
      unless a[:height].nil? or a[:height] == @font_height
        text = ['<span size="', a[:height], 'pt">', text, '</span>'].join
      end
      unless a[:color].empty?
        text = ['<span color="', a[:color], '">', text, '</span>'].join
      end
      {bold: 'b', italic: 'i', strike: 's', underline: 'u', sub: 'sub', sup: 'sup'}.each do |k, v|
        if a[k]
          text = ['<', v, '>', text, '</', v, '>'].join
        end
      end
      return text
    end

    def get_last_cursor_position
      x, y, h = 0, 0, 0
      (@data_buffer.length - 1).downto(0) do |i|
        data = @data_buffer[i]
        if data[:content][:type] == TYPE_IMAGE and
            not data[:content][:attr][:inline]
          next
        end
        case data[:content][:type]
        when TYPE_UNKNOWN
          x = data[:pos][:x]
        when TYPE_TEXT
          x = data[:pos][:x] + data[:pos][:w]
        when TYPE_IMAGE
          x = data[:pos][:x] + data[:pos][:w]
        else
          fail "unreachable"
        end
        y = data[:pos][:y]
        break
      end
      (@data_buffer.length - 1).downto(0) do |i|
        data = @data_buffer[i]
        if data[:content][:type] == TYPE_IMAGE and
            not data[:content][:attr][:inline]
          next
        end
        case data[:content][:type]
        when TYPE_UNKNOWN
          h = [h, 0].max
        when TYPE_TEXT
          @layout.set_indent(data[:pos][:x] * Pango::SCALE)
          markup = set_markup(data[:content][:data], data[:content][:attr])
          @layout.set_markup(markup)
          _, h1 = @layout.pixel_size
          h = [h, h1].max
        when TYPE_IMAGE
          if data[:content][:attr][:is_sstp_marker]
            h = [h, @char_height].max
          else
            h = [h, data[:content][:data].height].max
          end
        else
          fail "unreachable"
        end
        if data[:is_head]
          break
        end
      end
      return [x, y, h]
    end

    def get_bottom_position()
      h = 0
      (@data_buffer.length - 1).downto(0) do |i|
        data = @data_buffer[i]
        unless data[:content][:type] == TYPE_TEXT or
            not data[:content][:attr][:fixed]
          next
        end
        case data[:content][:type]
        when TYPE_TEXT
          h = [h, data[:pos][:y] + data[:pos][:h]].max
        when TYPE_IMAGE
          y = data[:pos][:y]
          unless data[:content][:attr][:inline]
            y -= @origin_y
          end
          h = [h, y + data[:pos][:h]].max
        end
      end
      return h - @lineno * @line_height
    end

    def redraw(widget, cr)
      return if @parent.handle_request('GET', 'lock_repaint')
      return true unless @__shown
      fail "assert" if @balloon_surface.nil?
      @window.set_surface(cr, @balloon_surface, scale, @reshape)
      cr.set_operator(Cairo::OPERATOR_OVER) # restore default
      cr.translate(*@window.get_draw_offset) # XXX
      # FIXME: comment
      cr.rectangle(@origin_x, 0, @valid_width, @origin_y + @valid_height)
      cr.clip
      # draw background image
      for i in 0..(@data_buffer.length - 1)
        data = @data_buffer[i]
        unless data[:content][:type] == TYPE_IMAGE and
            not data[:content][:attr][:foreground]
          next
        end
        if data[:content][:attr][:fixed]
          if y + h < 0 or y > @origin_y + @valid_height
            next
          end
        else
          y1 = y - @lineno * @line_height
          if data[:content][:attr][:inline]
            y1 += @origin_y
          end
          if y1 + h < 0 or y > @origin_y + @valid_height
            next
          end
        end
        x = data[:pos][:x]
        y = data[:pos][:y]
        w = data[:pos][:w]
        h = data[:pos][:h]
        if x == 'centerx'
          bw, bh = get_balloon_size(:scaling => false)
          x = ((bw - w) / 2)
        else
          begin
            x = Integer(x)
          rescue
            next
          end
        end
        if y == 'centery'
          bw, bh = get_balloon_size(:scaling => false)
          y = ((bh - h) / 2)
        else
          begin
            y = Integer(y)
          rescue
            next
          end
        end
        if data[:content][:attr][:fixed]
          cr.set_source(data[:content][:data], x, y)
        else
          if data[:content][:attr][:inline]
            if data[:content][:attr][:is_sstp_marker]
              cr.set_source(data[:content][:data], @origin_x + x, @origin_y + y + ((@char_height - data[:content][:data].height) / 2).to_i - @lineno * @line_height)
            else
              cr.set_source(data[:content][:data], @origin_x + x, @origin_y + y - @lineno * @line_height)
            end
          else
            cr.set_source(data[:content][:data], x, y - @lineno * @line_height)
          end
        end
        cr.paint()
      end
      cr.reset_clip
      # draw text
      cr.rectangle(@origin_x, @origin_y, @valid_width, @origin_y + @valid_height)
      cr.clip
      @layout.set_width(-1)
      for i in 0..(@data_buffer.length - 1)
        data = @data_buffer[i]
        unless data[:content][:type] == TYPE_TEXT
          next
        end
        y1 = data[:pos][:y] + @origin_y - @lineno * @line_height
        if y1 + data[:pos][:h] < 0 or y1 > @origin_y + @valid_height
          next
        end
        @layout.set_indent(data[:pos][:x] * Pango::SCALE)
        markup = set_markup(data[:content][:data], data[:content][:attr])
        @layout.set_markup(markup)
        cr.set_source_rgb(@text_normal_color)
        cr.move_to(@origin_x, @origin_y + data[:pos][:y] - @lineno * @line_height)
        cr.show_pango_layout(@layout)
      end
      cr.reset_clip
      # draw foreground image
      cr.rectangle(@origin_x, 0, @valid_width, @origin_y + @valid_height)
      cr.clip
      for i in 0..(@data_buffer.length - 1)
        data = @data_buffer[i]
        unless data[:content][:type] == TYPE_IMAGE and
            data[:content][:attr][:foreground]
          next
        end
        if data[:content][:attr][:fixed]
          if y + h < 0 or y > @origin_y + @valid_height
            next
          end
        else
          y1 = y - @lineno * @line_height
          if data[:content][:attr][:inline]
            y1 += @origin_y
          end
          if y1 + h < 0 or y > @origin_y + @valid_height
            next
          end
        end
        x = data[:pos][:x]
        y = data[:pos][:y]
        w = data[:content][:data].width
        h = data[:content][:data].height
        if x == 'centerx'
          bw, bh = get_balloon_size(:scaling => false)
          x = ((bw - w) / 2)
        else
          begin
            x = Integer(x)
          rescue
            next
          end
        end
        if y == 'centery'
          bw, bh = get_balloon_size(:scaling => false)
          y = ((bh - h) / 2)
        else
          begin
            y = Integer(y)
          rescue
            next
          end
        end
        if data[:content][:attr][:inline]
          cr.set_source(data[:content][:data], @origin_x + x, @origin_y + y)
        else
          cr.set_source(data[:content][:data], x, y)
        end
        cr.paint()
      end
      cr.reset_clip
=begin
      # FIXME
      # draw images
      for i in 0..(@images.length - 1)
        image_surface, (x, y) = @images[i]
        w = image_surface.width
        h = image_surface.height
        if x == 'centerx'
          bw, bh = get_balloon_size(:scaling => false)
          x = ((bw - w) / 2)
        else
          begin
            x = Integer(x)
          rescue
            next
          end
        end
        if y == 'centery'
          bw, bh = get_balloon_size(:scaling => false)
          y = ((bh - h) / 2)
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
      cr.rectangle(@origin_x, @origin_y, @valid_width, @valid_height)
      cr.clip
      for i in 0 .. @text_buffer.length - 1
        sx, sy = @line_regions[i]
        if @text_buffer.empty?
          next
        end
        markup = set_markup(i, @text_buffer[i])
        @layout.set_indent(sx * Pango::SCALE)
        @layout.set_markup(markup)
        cr.set_source_rgb(@text_normal_color)
        cr.move_to(@origin_x, @origin_y + sy - @lineno * @line_height)
        cr.show_pango_layout(@layout)
        t = @layout.text
        strong, weak = @layout.get_cursor_pos(t.bytesize)
        x = (strong.x / Pango::SCALE).to_i
        y = (strong.y / Pango::SCALE).to_i
        h = (strong.height / Pango::SCALE).to_i
        unless @sstp_surface.nil?
          for l, c in @sstp_marker
            if l == i
              mw = @sstp_surface.width
              mh = @sstp_surface.height
              @layout.set_text(@text_buffer[i][0, c])
              text_w, text_h = @layout.pixel_size
              mx = (x + text_w)
              my = (y + (@font_height + @line_space) / 2)
              my = (my - mh / 2)
              cr.set_source(@sstp_surface, mx, my)
              cr.paint()
            end
          end
        end
      end
      cr.reset_clip()
=end
      redraw_sstp_message(widget, cr) if @side.zero? and not @sstp_message.nil?
      update_link_region(widget, cr, @selection) unless @selection.nil?
      redraw_arrow0(widget, cr)
      redraw_arrow1(widget, cr)
      @window.set_shape(cr, @reshape)
      @reshape = false
      return false
    end

    def update_link_region(widget, cr, index)
      cr.save()
      sl = @link_buffer[index][0]
      el = @link_buffer[index][2]
      sn = @link_buffer[index][1]
      en = @link_buffer[index][3]
      cr.rectangle(@origin_x, 0, @valid_width, @origin_y + @valid_height)
      cr.clip
      for n in sl .. el
        data = @data_buffer[n]
        case data[:content][:type]
        when TYPE_TEXT
          x, y = data[:pos][:x], data[:pos][:y]
          if n == sl
            @layout.set_indent(x * Pango::SCALE)
            markup = set_markup(data[:content][:data][0, sn], data[:content][:attr])
            @layout.set_markup(markup)
            t = @layout.text
            strong, weak = @layout.get_cursor_pos(t.bytesize)
            x = (strong.x / Pango::SCALE).to_i
          end
          text = ''
          if sl == el
            text = data[:content][:data][sn, en - sn]
          elsif n == sl
            text = data[:content][:data][sn .. -1]
          elsif n == el
            text = data[:content][:data][0, en]
          else
            text = data[:content][:data]
          end
          @layout.set_indent(x * Pango::SCALE)
          markup = set_markup(text, data[:content][:attr])
          @layout.set_markup(markup)
          cr.set_source_rgb(@cursor_color)
          t = @layout.text
          x_bak = x
          for i in 0 .. t.bytesize
            strong, weak = @layout.get_cursor_pos(i)
            nx = (strong.x / Pango::SCALE).to_i
            ny = (strong.y / Pango::SCALE).to_i
            nh = (strong.height / Pango::SCALE).to_i
            if nx > x
              cr.rectangle(@origin_x + x, @origin_y + y - @lineno * @line_height, nx - x, nh)
              cr.fill()
            end
            x = nx
          end
          x = x_bak
          cr.move_to(@origin_x, @origin_y + y - @lineno * @line_height)
          cr.set_source_rgb(@text_active_color)
          cr.show_pango_layout(@layout)
        when TYPE_IMAGE
          x = data[:pos][:x]
          y = data[:pos][:y]
          w = data[:content][:data].width
          h = data[:content][:data].height
          if x == 'centerx'
            bw, bh = get_balloon_size(:scaling => false)
            x = ((bw - w) / 2)
          else
            begin
              x = Integer(x)
            rescue
              next
            end
          end
          if y == 'centery'
            bw, bh = get_balloon_size(:scaling => false)
            y = ((bh - h) / 2)
          else
            begin
              y = Integer(y)
            rescue
              next
            end
          end
          if data[:content][:attr][:inline]
            x += @origin_x
            y += @origin_y
          end
          y = y - @lineno * @line_height
          cr.rectangle(x, y, w, h)
          cr.stroke
        else
          # nop
        end
      end
      cr.reset_clip
      cr.restore()
    end

    def check_link_region(px, py)
      new_selection = nil
      for index in 0..(@link_buffer.length - 1)
        sl = @link_buffer[index][0]
        el = @link_buffer[index][2]
        sn = @link_buffer[index][1]
        en = @link_buffer[index][3]
        for n in sl .. el
          data = @data_buffer[n]
          case data[:content][:type]
          when TYPE_TEXT
            x, y = data[:pos][:x], data[:pos][:y]
            if n == sl
              @layout.set_indent(x * Pango::SCALE)
              markup = set_markup(data[:content][:data][0, sn], data[:content][:attr])
              @layout.set_markup(markup)
              t = @layout.text
              strong, weak = @layout.get_cursor_pos(t.bytesize)
              x = (strong.x / Pango::SCALE).to_i
            end
            text = ''
            if sl == el
              text = data[:content][:data][sn, en - sn]
            elsif n == sl
              text = data[:content][:data][sn .. -1]
            elsif n == el
              text = data[:content][:data][0, en]
            else
              text = data[:content][:data]
            end
            @layout.set_indent(x * Pango::SCALE)
            markup = set_markup(text, data[:content][:attr])
            @layout.set_markup(markup)
            t = @layout.text
            for i in 0 .. t.bytesize
              strong, weak = @layout.get_cursor_pos(i)
              nx = (strong.x / Pango::SCALE).to_i
              ny = (strong.y / Pango::SCALE).to_i
              nh = (strong.height / Pango::SCALE).to_i
              if @origin_x + x <= px and px < @origin_x + nx and @origin_y + y - @lineno * @line_height <= py and py < @origin_y + y + nh - @lineno * @line_height
                new_selection = index
                break
              end
              x = nx
            end
          when TYPE_IMAGE
            # FIXME
            x = data[:pos][:x]
            y = data[:pos][:y]
            w = data[:content][:data].width
            h = data[:content][:data].height
            if x == 'centerx'
              bw, bh = get_balloon_size(:scaling => false)
              x = ((bw - w) / 2)
            else
              begin
                x = Integer(x)
              rescue
                next
              end
            end
            if y == 'centery'
              bw, bh = get_balloon_size(:scaling => false)
              y = ((bh - h) / 2)
            else
              begin
                y = Integer(y)
              rescue
                next
              end
            end
            unless data[:content][:attr][:fixed]
              y = y - @lineno * @line_height
            end
            y1 = [y, 0].max
            y2 = [y + h, @origin_y + @valid_height].min
            if data[:content][:attr][:inline]
              y2 = [y + h, @valid_height].min
              x += @origin_x
              y1 += @origin_y
              y2 += @origin_y
            end
            if x <= px and px < x + w and y1 <= py and py < y2
              new_selection = index
            end
          else
            # nop
          end
          if new_selection == index
            break
          end
        end
        if new_selection == index
          break
        end
      end
      unless new_selection.nil?
        if @selection != new_selection
          sl, sn, el, en, link_id, args, raw_text, text = \
          @link_buffer[new_selection]
          @parent.handle_request(
            'NOTIFY', 'notify_event',
            'OnChoiceEnter', raw_text, link_id, @selection)
        end
      else
        unless @selection.nil?
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
      x, y, state = event.x, event.y, event.state
      px, py = @window.winpos_to_surfacepos(x, y, scale)
      unless @link_buffer.empty?
        if check_link_region(px, py)
          widget.queue_draw()
        end
      end
      unless @parent.handle_request('GET', 'busy')
        if (state & Gdk::ModifierType::BUTTON1_MASK).nonzero?
          unless @x_root.nil? or @y_root.nil?
            @dragged = true
            x_delta = ((event.x_root - @x_root) * 100 / scale + @x_fractions)
            y_delta = ((event.y_root - @y_root) * 100 / scale + @y_fractions)
            @x_fractions = (x_delta - x_delta.to_i)
            @y_fractions = (y_delta - y_delta.to_i)
            @parent.handle_request(
              'NOTIFY', 'update_balloon_offset',
              @side, x_delta.to_i, y_delta.to_i)
            @x_root = event.x_root
            @y_root = event.y_root
          end
        end
      end
      Gdk::Event.request_motions(event) if event.is_hint == 1
      return true
    end

    def scroll(darea, event)
      px, py = @window.winpos_to_surfacepos(
            event.x.to_i, event.y.to_i, scale)
      case event.direction
      when Gdk::ScrollDirection::UP
        if @lineno > 0
          @lineno = @lineno - 1
          check_link_region(px, py)
          @darea.queue_draw()
        end
      when Gdk::ScrollDirection::DOWN
        if get_bottom_position > @valid_height
          @lineno += 1
          check_link_region(px, py)
          @darea.queue_draw()
        end
      end
      return true
    end

    def button_press(darea, event)
      @parent.handle_request('NOTIFY', 'reset_idle_time')
      click = event.event_type == Gdk::EventType::BUTTON_PRESS ? 1 : 2
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
      if x <= px and px <= (x + w) and y <= py and py <= (y + h)
        if @lineno > 0
          @lineno = @lineno - 1
          @darea.queue_draw()
        end
        return true
      end
      # down arrow
      w = @arrow1_surface.width
      h = @arrow1_surface.height
      x, y = @arrow[1]
      if x <= px and px <= (x + w) and y <= py and py <= (y + h)
        if get_bottom_position > @valid_height
          @lineno += 1
          @darea.queue_draw()
        end
        return true
      end
      # links
      unless @selection.nil?
        sl, sn, el, en, link_id, args, raw_text, text = \
        @link_buffer[@selection]
        @parent.handle_request('NOTIFY', 'notify_link_selection',
                               link_id, raw_text, args, @selection)
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
      @dragged = false if @dragged
      @x_root = nil
      @y_root = nil
      @y_fractions = 0
      @y_fractions = 0
      return true
    end

    def clear_text
      @selection = nil
      @lineno = 0
      @text_buffer = ['']
      @line_regions = [[0, 0]]
      @data_buffer = [{
        pos: {x: 0, y: 0, w: 0, h: 0},
        content: {type: TYPE_UNKNOWN, data: nil, attr: {
          height: @font_height,
          color: '',
          bold: false,
          italic: false,
          strike: false,
          underline: false,
          sup: false,
          sub: false,
          inline: false,
          opaque: false,
          use_self_alpha: false,
          clipping: [0, 0, -1, -1],
          fixed: false,
          foreground: false,
          is_sstp_marker: false,
        }},
        is_head: true
      }]
      @meta_buffer = []
      @link_buffer = []
      @newline_required = false
      @images = []
      @sstp_marker = []
      @darea.queue_draw()
    end

    def get_text_count
      @text_count
    end

    def reset_text_count
      @text_count = 0
    end

    def set_newline
      @newline_required = true
    end

    def new_buffer(is_head: nil)
      x, y, h = get_last_cursor_position
      prev = @data_buffer[-1]
      a = prev[:content][:attr].dup
      # 画像のattrはすべて未指定の状態にする
      {
        opaque: false,
        inline: false,
        clipping: [0, 0, -1, -1],
        fixed: false,
        foreground: false,
        is_sstp_marker: false,
      }.each do |k, v|
        a[k] = v
      end
      @data_buffer << {
        pos: {x: x, y: y, w: 0, h: 0},
        content: {type: TYPE_UNKNOWN, data: nil, attr: a},
        is_head: is_head,
      }
    end

    def new_line
      new_buffer(is_head: true)
    end

    def set_draw_absolute_x(pos)
      data = @data_buffer[-1]
      new = data[:pos].dup
      new[:x] = pos
      @data_buffer[-1] = {
        pos: new,
        content: data[:content],
        is_head: data[:is_head],
      }
    end

    def set_draw_absolute_x_char(rate)
      set_draw_absolute_x(@char_width * rate)
    end

    def set_draw_relative_x(pos)
      x = @data_buffer[-1][:pos][:x]
      set_draw_absolute_x(x + pos)
    end

    def set_draw_relative_x_char(rate)
      set_draw_relative_x(@char_width * rate)
    end

    def set_draw_absolute_y(pos)
      data = @data_buffer[-1]
      new = data[:pos].dup
      new[:y] = pos
      @data_buffer[-1] = {
        pos: new,
        content: data[:content],
        is_head: data[:is_head],
      }
    end

    def set_draw_absolute_y_char(rate, use_default_height: true)
      rx, ry, rh = get_last_cursor_position
      # 最初に\n系が呼ばれたときの処理
      if rh == 0 || use_default_height
        rh = @line_height
      end
      set_draw_absolute_y((rh * rate).to_i)
    end

    def set_draw_relative_y(pos)
      y = @data_buffer[-1][:pos][:y]
      set_draw_absolute_y(y + pos)
    end

    def set_draw_relative_y_char(rate, use_default_height: true)
      rx, ry, rh = get_last_cursor_position
      # 最初に\n系が呼ばれたときの処理
      if rh == 0 || use_default_height
        rh = @line_height
      end
      set_draw_relative_y((rh * rate).to_i)
    end

    def append_text(text)
      data = @data_buffer[-1]
      case data[:content][:type]
      when TYPE_UNKNOWN
        @layout.set_width(-1)
        @layout.set_indent(data[:pos][:x] * Pango::SCALE)
        w, h = 0, 0
        # XXX: 空白だけのmarkupだとなぜかlayoutの幅が半分になるので
        # 適当な文字を足して空白のみの状況を避ける
        if text =~ /\A *\z/
          markup = set_markup([text, 'o'].join, data[:content][:attr])
          @layout.set_markup(markup)
          w1, h = @layout.pixel_size
          markup = set_markup('-', data[:content][:attr])
          @layout.set_markup(markup)
          w2, _ = @layout.pixel_size
          w = w1 - w2
        else
          markup = set_markup(text, data[:content][:attr])
          @layout.set_markup(markup)
          w, h = @layout.pixel_size
        end
        data[:pos][:w] = w
        data[:pos][:h] = h
        data[:content][:type] = TYPE_TEXT
        data[:content][:data] = text
      when TYPE_TEXT
        @layout.set_width(@valid_width * Pango::SCALE)
        @layout.set_indent(data[:pos][:x] * Pango::SCALE)
        concat = [data[:content][:data], text].join('')
        markup = set_markup(concat, data[:content][:attr])
        @layout.set_markup(markup)
        t = @layout.text
        strong, weak = @layout.get_cursor_pos(t.bytesize)
        x = (strong.x / Pango::SCALE).to_i
        prev_x = x
        t.bytesize.downto(0) do |i|
          strong, weak = @layout.get_cursor_pos(i)
          x = (strong.x / Pango::SCALE).to_i
          if prev_x < x
            new_buffer(is_head: false)
            set_draw_absolute_x(0)
            set_draw_relative_y_char(1.0, use_default_height: false)
            return append_text(text)
          end
        end
        w, h = @layout.pixel_size
        data[:pos][:w] = w
        data[:pos][:h] = h
        data[:content][:data] = concat
      when TYPE_IMAGE
        # \nや\_lなどが行われていない場合にここに来るのでis_headはfalse
        new_buffer(is_head: false)
        return append_text(text)
      end
      draw_last_line(:column => 0)
    end

    def append_sstp_marker
      return if @sstp_surface.nil?
      unless @data_buffer[-1][:content][:type] == TYPE_UNKNOWN
        new_buffer(is_head: false)
      end
      data = @data_buffer[-1]
      data[:pos][:w] = @sstp_surface.width
      data[:pos][:h] = @char_height
      data[:content][:type] = TYPE_IMAGE
      data[:content][:data] = @sstp_surface
      data[:content][:attr] = {
        height: @font_height,
        color: '',
        bold: false,
        italic: false,
        strike: false,
        underline: false,
        sub: false,
        sup: false,
        opaque: false,
        inline: true,
        clipping: [0, 0, -1, -1],
        fixed: false,
        foreground: false,
        is_sstp_marker: true,
      }
      show
      @darea.queue_draw
    end

    def append_link_in(link_id, args)
      sl = @data_buffer.length - 1
      sn = if @data_buffer[-1][:content][:type] == TYPE_TEXT
             @data_buffer[-1][:content][:data].length
           else
             0
           end
      @link_buffer << [sl, sn, sl, sn, link_id, args, '', '']
    end

    def append_link_out(link_id, text, args)
      return unless text
      raw_text = text
      el = @data_buffer.length - 1
      en = if @data_buffer[-1][:content][:type] == TYPE_TEXT
             @data_buffer[-1][:content][:data].length
           else
             0
           end
      sl = @link_buffer[-1][0]
      sn = @link_buffer[-1][1]
      @link_buffer[-1] = [sl, sn, el, en, link_id, args, raw_text, text]
    end

    def append_meta(**kwargs)
      data = @data_buffer[-1]
      # default -> 数値へ変更。
      kwargs.each do |k, v|
        if v == 'default'
          case k
          when :height
            kwargs[k] = [@font_height, false, false]
          when :color
            kwargs[k] = ''
          when :bold
            kwargs[k] = false
          when :italic
            kwargs[k] = false
          when :strike
            kwargs[k] = false
          when :underline
            kwargs[k] = false
          when :sub
            kwargs[k] = false
          when :sup
            kwargs[k] = false
          end
        elsif v == "disable"
          # TODO stub
        end
      end
      # heightは特殊な処理が必要。
      unless kwargs[:height].nil?
        v, relative, rate = kwargs[:height]
        if rate
          v = (data[:content][:attr][:height] * v / 100.0).to_i
        end
        if relative
          v = data[:content][:attr][:height] + v
        end
        kwargs[:height] = v
      end
      case data[:content][:type]
      when TYPE_UNKNOWN
        # nop
      when TYPE_TEXT
      is_changed = false
      kwargs.each do |k, v|
        unless data[:content][:attr][k] == v
          is_changed = true
          break
        end
      end
      if is_changed
        new_buffer(is_head: false)
      end
      when TYPE_IMAGE
        new_buffer(is_head: false)
      end
      data = @data_buffer[-1]
      a = data[:content][:attr].dup
      kwargs.each do |k, v|
        a[k] = v
      end
      data[:content][:attr] = a
    end

    def append_image(path, **kwargs)
      unless @data_buffer[-1][:content][:type] == TYPE_UNKNOWN
        new_buffer(is_head: false)
      end
      data = @data_buffer[-1]
      begin
        image_surface = Pix.create_surface_from_file(path)
      rescue
        return
      end
      data[:pos][:w] = image_surface.width
      data[:pos][:h] = image_surface.height
      data[:content][:type] = TYPE_IMAGE
      data[:content][:data] = image_surface
      data[:content][:attr][:is_sstp_marker] = false
      unless kwargs[:x].nil? or kwargs[:y].nil?
        data[:pos][:x] = kwargs[:x]
        data[:pos][:y] = kwargs[:y]
      end
      kwargs.each do |k, v|
        if [:opaque, :inline, :clipping, :fixed, :foreground].include?(k)
          data[:content][:attr][k] = v
        end
      end
      show
      @darea.queue_draw
    end

    def draw_last_line(column: 0)
      return unless @__shown
      while get_bottom_position > @valid_height
        @lineno += 1
      end
      @darea.queue_draw()
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
      @window.destroy unless @window.nil?
      @window = Pix::BaseTransparentWindow.new()
      @__surface_position = [0, 0]
      @window.set_title('communicate')
      @window.signal_connect('delete_event') do |w ,e|
        next delete(w, e)
      end
      @window.signal_connect('key_press_event') do |w, e|
        next key_press(w, e)
      end
      @window.signal_connect('button_press_event') do |w, e|
        next button_press(w, e)
      end
      @window.signal_connect('drag_data_received') do |widget, context, x, y, data, info, time|
        drag_data_received(widget, context, x, y, data, info, time)
        next true
      end
      # DnD data types
      dnd_targets = [['text/plain', 0, 0]]
      @window.drag_dest_set(Gtk::DestDefaults::ALL, dnd_targets,
                            Gdk::DragAction::COPY)
      @window.drag_dest_add_text_targets()
      @window.set_events(Gdk::EventMask::BUTTON_PRESS_MASK)
      #@window.set_window_position(Gtk::WindowPosition::CENTER)
      @window.realize()
      @window.override_background_color(
        Gtk::StateFlags::NORMAL, Gdk::RGBA.new(0, 0, 0, 0))
      w = desc.get('communicatebox.width', :default => 250).to_i
      h = desc.get('communicatebox.height', :default => -1).to_i
      left, top, scrn_w, scrn_h = @parent.handle_request('GET', 'get_workarea')
      @__surface_position = [(scrn_w - w) / 2, (scrn_h - h) / 2] # XXX
      @entry = Gtk::Entry.new
      @entry.signal_connect('activate') do |w|
        next activate(w)
      end
      @entry.set_inner_border(nil)
      @entry.set_has_frame(false)
      font_desc = Pango::FontDescription.new()
      font_desc.set_size(9 * 3 / 4 * Pango::SCALE) # XXX
      @entry.override_font(font_desc)
      @entry.set_size_request(w, h)
      text_r = desc.get(['font.color.r', 'fontcolor.r'], :default => 0).to_i
      text_g = desc.get(['font.color.g', 'fontcolor.g'], :default => 0).to_i
      text_b = desc.get(['font.color.b', 'fontcolor.b'], :default => 0).to_i
      provider = Gtk::CssProvider.new
      context = @entry.style_context
      context.add_provider(provider, Gtk::StyleProvider::PRIORITY_USER)
      provider.load(data: ["entry {\n",
                            'color: #',
                            sprintf('%02x', text_r),
                            sprintf('%02x', text_g),
                            sprintf('%02x', text_b),
                            ";\n",
                            "}"
                          ].join)
      @entry.set_name('entry')
      @entry.show()
      surface = nil
      unless balloon.nil?
        path, config = balloon
        # load pixbuf
        begin
          surface = Pix.create_surface_from_file(path)
        rescue
          surface = nil
        end
      end
      unless surface.nil?
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
        @entry.set_halign(Gtk::Align::START)
        @entry.set_valign(Gtk::Align::START)
        overlay.add_overlay(@entry)
        overlay.add(darea)
        overlay.show()
        @window.add(overlay)
        darea.set_size_request(*@window.size) # XXX
      else
        box = Gtk::Box.new(orientation=Gtk::Orientation::HORIZONTAL, spacing=10)
        box.set_border_width(10)
        unless ENTRY.empty?
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

    def get_draw_offset
      return @__surface_position
    end

    def redraw(widget, cr, surface)
      cr.save()
      # clear
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.set_source_rgba(0, 0, 0, 0)
      cr.paint
      cr.set_source(surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      # copy rectangle on the destination
      cr.rectangle(0, 0, surface.width, surface.height)
      cr.fill()
      cr.restore()
      w, h = @window.size
      unless w == surface.width and h == surface.height
        @window.resize(surface.width, surface.height)
      end
      return if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      s = cr.target.map_to_image
      s = surface if s.width < surface.width or s.height < surface.height
      region = Pix.surface_to_region(s)
      # XXX: to avoid losing focus in the text input region
      x = @entry.margin_left
      y = @entry.margin_top
      w = @entry.allocated_width
      h = @entry.allocated_height
      region.union!(x, y, w, h)
      if @window.supports_alpha
        @window.input_shape_combine_region(nil)
        @window.input_shape_combine_region(region)
      else
        @window.shape_combine_region(nil)
        @window.shape_combine_region(region)
      end
    end

    def destroy
      @window.destroy unless @window.nil?
      @window = nil
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
      unless data.nil?
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
      unless default.nil?
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
      return if @symbol.nil?
      return if symbol != '__SYSTEM_ALL_INPUT__' and @symbol != symbol
      @window.hide()
      cancel()
    end

    def send(data, cancel: false, timeout: false)
      GLib.source_remove(@timeout_id) unless @timeout_id.nil?
      data = '' if data.nil?
      ## CHECK: symbol
      if cancel
        @parent.handle_request('NOTIFY', 'notify_event',
                               'OnUserInputCancel', '', 'cancel')
      elsif timeout and \
        not @parent.handle_request('GET', 'notify_event',
                                   'OnUserInputCancel', '', 'timeout').nil?
        # pass
      elsif @symbol == 'OnUserInput' and \
            not @parent.handle_request('GET', 'notify_event', 'OnUserInput', data).nil?
        # pass
      elsif not @parent.handle_request('GET', 'notify_event', @symbol, data).nil?
        # pass
      elsif not @parent.handle_request('GET', 'notify_event',
                                       'OnUserInput', @symbol, data).nil?
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
