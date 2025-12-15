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

require 'gtk4'
require 'cgi'

require_relative 'home'
require_relative 'pix'
require_relative 'metamagic'

module Balloon

  TYPE_UNKNOWN = 0
  TYPE_TEXT = 1
  TYPE_IMAGE = 2

  TYPE_ABSOLUTE = 0
  TYPE_RELATIVE = 1

  Position = Struct.new(:x, :y, :w, :h)
  Content = Struct.new(:type, :data, :attr)
  Attribute = Struct.new(:height, :color, :bold, :italic, :strike,
                         :underline, :sup, :sub, :inline, :opaque,
                         :use_self_alpha, :clipping, :fixed, :foreground, 
                         :is_sstp_marker)
  Head = Struct.new(:valid, :x, :y)
  Point = Struct.new(:type, :value)
  Data = Struct.new(:pos, :content, :head)
  Link = Struct.new(:buffer_index, :begin_index, :begin_offset, :end_index, :end_offset, :link_id, :args, :raw_text, :text)

  class Post < Array
    attr_reader :name
    def initialize(name)
      @name = name
      super(1) do
        yield
      end
    end
  end

  class BalloonProxy < MetaMagic::Holon
    def initialize
      super("")
      @normal = Balloon.new
      @normal.set_responsible(self)
      @sns = SNSBalloon.new
      @sns.set_responsible(self)
      @ai = Ai.new
      @ai.set_responsible(self)
      @current = @normal
    end

    def new_(desc, *args)
      ai = desc.get('ai')
      if ai.nil? or ai.empty?
        @current = @normal
      elsif ai == 'sns'
        @current = @sns
      else
        @current = @ai
      end
      @current.new_(desc, *args)
    end

    def set_responsible(parent)
      @parent = parent
    end

    def respond_to_missing?(symbol, include_private)
      @current.class.method_defined?(symbol)
    end

    def method_missing(name, *args, **kwarg)
      @current.send(name, *args, **kwarg)
    end
  end

  class Ai < MetaMagic::Holon
    def initialize
      super("") # FIXME
    end

    def reset_user_interaction
    end

    def get_text_count(side)
    end

    def get_window(side)
    end

    def reset_text_count(side)
    end

    def reset_balloon
    end

    def identify_window(win)
    end

    def finalize
    end

    def new_(desc, balloon)
      @desc = desc
      directory = balloon['balloon_dir'][0]
      @ai = desc.get('ai')
      fail if @ai.nil?
      if ENV['AI_PATH'].nil?
        command = @ai
      else
        command = File.join(ENV['AI_PATH'], @ai)
      end
      begin
        @ai_write, @ai_read, @ai_err, @ai_thread = Open3.popen3(command)
      rescue => e
        # TODO error
        p e
        return
      end
      send_event('Initialize', File.join(Home.get_ninix_home, 'balloon', directory, ''))
      send_event('BasewareVersion', 'ninix', Version.NUMBER)
      path, _ao_uuid, ai_uuid = @parent.handle_request(:GET, :endpoint)
      send_event('Endpoint', path, ai_uuid)
      info = []
      @desc.each do |k, v|
        info << [k, v].join(',')
      end
      send_event('Description', *info)
      reset_fonts
    end

    def send_event(event, *args, method: 'NOTIFY')
      request = [
        "#{method} SORAKADO/0.1",
        'Charset: UTF-8',
        "Command: #{event}",
      ].join("\r\n")
      args.each_with_index do |v, i|
        request = [request, "Argument#{i}: #{v}"].join("\r\n")
      end
      request = [request, "\r\n\r\n"].join
      request = [[request.bytesize].pack('L'), request.force_encoding(Encoding::BINARY)].join
      @ai_write.write(request)
      len = nil
      begin
        len = @ai_read.read(4)&.unpack('L').first
      end
      if len.nil?
        # TODO error
        return
      end
      response = @ai_read.read(len)
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

    def add_window(side)
      send_event('Create', side)
    end

    def user_interaction
      false
    end

    def reset_fonts
      font_name = @parent.handle_request(:GET, :get_preference, 'balloon_fonts')
      scale = @parent.handle_request(:GET, :get_preference, 'surface_scale')
      send_event('ConfigurationChanged', "font,#{font_name}", "scale,#{scale}")
    end

    def get_balloon_directory
    end

    def get_balloon_size(side)
    end

    def get_balloon_windowposition(side)
    end

    def set_balloon_default(side: -1)
    end

    def set_balloon(side, num)
      send_event('SetBalloon', side, num)
    end

    def set_position(side, base_x, base_y)
      send_event('Position', side, base_x, base_y)
    end

    def get_position(side)
    end

    def set_autoscroll(flag)
    end

    def is_shown(side)
    end

    def show(side)
      send_event('Show', side)
    end

    def hide_all
    end

    def hide(side)
      send_event('Hide', side)
    end

    def raise_all
    end

    def raise_(side)
    end

    def lower_all
    end

    def lower(side)
    end

    def synchronize(list)
    end

    def set_balloon_direction(side, direction)
      send_event('Direction', side, direction)
    end

    def clear_text_all
    end

    def clear_text(side)
    end

    def new_line(side)
    end

    def set_draw_absolute_x(side, pos)
    end

    def set_draw_absolute_x_char(side, rate)
    end

    def set_draw_relative_x(side, pos)
    end

    def set_draw_relative_x_char(side, rate)
    end

    def set_draw_absolute_y(side, pos)
    end

    def set_draw_absolute_y_char(side, rate, **kwarg)
    end

    def set_draw_relative_y(side, pos)
    end

    def set_draw_relative_y_char(side, rate, **kwarg)
    end

    def append_text(side, text)
    end

    def append_sstp_marker(side)
    end

    def append_link_in(side, label, args)
    end

    def append_link_out(side, label, value, args)
    end

    def append_link(side, label, value, args)
    end

    def append_meta(side, **kwargs)
    end

    def append_image(side, path, **kwargs)
    end

    def show_sstp_message(message, sender)
    end

    def hide_sstp_message
    end

    def open_communicatebox
    end

    def open_teachbox
    end

    def open_inputbox(symbol, limittime: -1, default: nil)
    end

    def open_passwordinputbox(symbol, limittime: -1, default: nil)
    end

    def open_scriptinputbox()
    end

    def close_inputbox(symbol)
    end

    def close_communicatebox
    end

    def close_teachbox
    end

    def destroy_inputbox(symbol)
    end
  end

  class SNSBalloon < MetaMagic::Holon
    attr_reader :user_interaction
    def initialize
      super("") # FIXME
      @handlers = {
        :reset_user_interaction => :reset_user_interaction,
      }
      @user_interaction = false
      @window = nil
      # create communicatebox
      @communicatebox = CommunicateBox.new()
      @communicatebox.set_responsible(self)
      # create teachbox
      @teachbox = TeachBox.new()
      @teachbox.set_responsible(self)
      # create inputbox
      @inputbox = Hash.new do |h, k|
        # configure inputbox
        i = InputBox.new
        i.set_responsible(self)
        h[k] = i
      end
      # create passwordinputbox
      @passwordinputbox = Hash.new do |h, k|
        # configure passwordinputbox
        p = PasswordInputBox.new
        p.set_responsible(self)
        h[k] = p
      end
      # create scriptbox
      @scriptinputbox = ScriptInputBox.new()
      @scriptinputbox.set_responsible(self)
      @text_count = Hash.new do |h, k|
        h[k] = 0
      end
      @side = 0
    end

    def reset_user_interaction
      # TODO stub
    end

    def get_text_count(side)
      @text_count[side]
    end

    def get_window(side)
      # TODO stub
    end

    def reset_text_count(side)
      @text_count[side] = 0
    end

    def reset_balloon
      reset_arrow
      reset_sstp_marker
      reset_message_regions
    end

    def identify_window(win)
      # TODO stub
    end

    def finalize
      @window.destroy
      @window = nil
      @communicatebox.destroy
      @teachbox.destroy
      @inputbox.each.to_a.each do |k, v|
        v.close(k)
      end
      @passwordinputbox.each.to_a.each do |k, v|
        v.close(k)
      end
    end

    def new_(desc, balloon)
      @desc = desc
      @directory = balloon['balloon_dir'][0]
      @balloon = balloon
      @communicate = []
      0.upto(3) do |i|
        key = 'c' + i.to_s
        @communicate[i] = balloon[key] if balloon.include?(key) 
      end

      # create balloon windows
      @cache = Pix::Cache.new
      directory = File.join(Home.get_ninix_home, 'balloon', @directory)
      path = File.join(directory, 'balloon_bg.png')
      begin
        @bg_surface = Pix.surface_new_from_file(path)
      rescue
        Logging::Logging.debug('cannot load balloon bg image')
        @bg_surface = Pix.create_blank_surface(200, 200)
      end
      path = File.join(directory, 'post_top.png')
      begin
        pix = @cache.load(path)
      rescue
        Logging::Logging.debug('cannot load post top image')
        pix = Pix::Data.new(Pix.create_blank_surface(200, 40), Cairo::Region.new, false)
      end
      @post_top_surface = pix.surface(write: false)
      path = File.join(directory, 'post_content.png')
      begin
        pix = @cache.load(path)
      rescue
        Logging::Logging.debug('cannot load post content image')
        pix = Pix::Data.new(Pix.create_blank_surface(200, 200), Cairo::Region.new, false)
      end
      @post_content_surface = pix.surface(write: false)
      path = File.join(directory, 'post_bottom.png')
      begin
        pix = @cache.load(path)
      rescue
        Logging::Logging.debug('cannot load post bottom image')
        pix = Pix::Data.new(Pix.create_blank_surface(200, 20), Cairo::Region.new, false)
      end
      @post_bottom_surface = pix.surface(write: false)
      @window = Gtk::Window.new
      @parent.handle_request(:NOTIFY, :associate_application, @window)
      @window.set_focusable(false)
      @window.signal_connect('close-request') do
        hide_all
      end
      @window.set_decorated(true)
      @window.set_title(@parent.handle_request(:GET, :get_descript, 'name'))
      @width, @height = @bg_surface.width, @bg_surface.height
      @window.set_default_size(@width, @height)
      @darea = Gtk::DrawingArea.new
      @window.set_child(@darea)
      @darea.set_draw_func do |widget, cr, w, h|
        redraw(@window, widget, cr)
        next true
      end
      @darea.show
      button_controller = Gtk::GestureClick.new
      # 全てのボタンをlisten
      button_controller.set_button(0)
      button_controller.signal_connect('pressed') do |w, n, x, y|
        next button_press(@window, @darea, w, n, x, y)
      end
      @darea.add_controller(button_controller)
      motion_controller = Gtk::EventControllerMotion.new
      motion_controller.signal_connect('motion') do |w, x, y|
        next motion_notify(@window, @darea, w, x, y)
      end
      @darea.add_controller(motion_controller)
      scroll_controller = Gtk::EventControllerScroll.new(Gtk::EventControllerScrollFlags::VERTICAL)
      scroll_controller.signal_connect('scroll') do |w, dx, dy|
        next scroll(@window, @darea, dx, dy)
      end
      @darea.add_controller(scroll_controller)

      # configure communicatebox
      @communicatebox.new_(desc, @communicate[1])
      # configure teachbox
      @teachbox.new_(desc, @communicate[2])
      # configure scriptinputbox
      @scriptinputbox.new_(desc, @communicate[3])

      pango_context = Gtk::DrawingArea.new.pango_context
      @layout = Pango::Layout.new(pango_context)
      @sstp_layout = Pango::Layout.new(pango_context)
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
      reset_fonts
      clear_text_all
    end

    def motion_notify(window, widget, ctrl, x, y)
=begin FIXME
      px, py = window.winpos_to_surfacepos(x, y, scale)
=end
      px, py = x, y
      unless @link_buffer.empty?
        if check_link_region(px, py)
          widget.queue_draw
        end
      end
      return true
    end

    def scroll(window, darea, dx, dy)
=begin FIXME
      px, py = window.winpos_to_surfacepos(
            dx, dy, scale)
=end
      px, py = dx, dy
      if py < 0
        if @lineno > 0
          @lineno -= 1
          check_link_region(px, py)
          darea.queue_draw
        end
      elsif py > 0
        if get_bottom_position - @lineno * @line_height > @bg_surface.height * scale / 100.0
          @lineno += 1
          check_link_region(px, py)
          darea.queue_draw
        end
      end
      return true
    end

    def button_press(window, darea, ctrl, n, x, y)
      @parent.handle_request(:GET, :reset_idle_time)
      if @parent.handle_request(:GET, :is_paused)
        @parent.handle_request(:GET, :notify_balloon_click,
                               ctrl.button, 1, @side)
        return true
      end
      # arrows
=begin FIXME
      px, py = window.winpos_to_surfacepos(
            x, y, scale)
=end
      px, py = x, y
      # up arrow
      surface = @arrow0_surface
      w = surface.width
      h = surface.height
      x, y = @arrow[0]
      if x <= px and px <= (x + w) and y <= py and py <= (y + h)
        if @lineno > 0
          @lineno = @lineno - 1
          darea.queue_draw()
        end
        return true
      end
      # down arrow
      surface = @arrow1_surface
      w = surface.width
      h = surface.height
      x, y = @arrow[1]
      if x <= px and px <= (x + w) and y <= py and py <= (y + h)
        if get_bottom_position - @lineno * @line_height > @bg_surface.height * scale / 100.0
          @lineno += 1
          darea.queue_draw
        end
        return true
      end
      # links
      unless @selection.nil?
        link = @link_buffer[@selection]
        @parent.handle_request(:GET, :notify_link_selection,
                               link.link_id, link.raw_text, link.args, @selection)
        return true
      end
      # balloon's background
      @parent.handle_request(:GET, :notify_balloon_click,
                             ctrl.button, 1, @side)
      return true
    end

    def button_release(window, w, n, x, y)
      # nop
      return true
    end

    def get_image_surface(id)
      return nil unless @balloon.include?(id)
      begin
        path, config = @balloon[id]
        use_pna = (not @parent.handle_request(:GET, :get_preference, 'use_pna').zero?)
        surface = @cache.load(path, use_pna: use_pna).surface(write: false)
      rescue
        return nil
      end
      return surface
    end

    def reset_fonts
      unless @parent.nil?
        font_name = @parent.handle_request(:GET, :get_preference, 'balloon_fonts')
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
      reset_arrow
      reset_sstp_marker
      reset_message_regions
      @darea.queue_draw if @__shown
    end

    def config_adjust(name, base, default_value)
      value = @desc.get(name)
      if value.nil?
        value = default_value
      end
      value = value.to_i
      if value < 0
        value = (base + value)
      end
      return value.to_i
    end

    def reset_sstp_marker
      if @side.zero?
        # sstp marker position
        w = @bg_surface.width
        h = @bg_surface.height
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
      fail "assert" if @bg_surface.nil?
      w = @bg_surface.width
      h = @bg_surface.height
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
      @name_x = @desc.get('sns.name.x', default: 0).to_i
      @name_y = @desc.get('sns.name.y', default: 0).to_i
      # font metrics
      @origin_x = @desc.get('origin.x',
          default: @desc.get('zeropoint.x',
              default: @desc.get('validrect.left',
                  default: 14).to_i).to_i).to_i
      @origin_y = 0
      wpx = @desc.get('wordwrappoint.x',
          default: @desc.get('validrect.right',
              default: 14).to_i).to_i
      @valid_rect_bottom = @desc.get('validrect.bottom', default: -14).to_i
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

    def get_balloon_directory
      @directory
    end

    def get_balloon_size(side)
      [@width, @height]
    end

    def add_window(side)
      # nop
    end

    def get_balloon_windowposition(side)
    end

    def set_balloon_default(side: -1)
      # nop
    end

    def set_balloon(side, num)
      # nop
    end

    def set_position(side, base_x, base_y)
      # nop
    end

    def get_position(side)
      [0, 0]
    end

    def set_autoscroll(flag)
      # TODO stub
    end

    def is_shown(side)
      @__shown
    end

    # HACK
    # waylandではshow-hideだとウィンドウの位置がリセットされてしまうので
    # minimize-unminimizeで代用する

    def show(side)
      return if @__shown
      @__shown = true
      @window.show
      @window.unminimize
      @window.present
    end

    def hide_all
      return unless @__shown
      @__shown = false
      @window.minimize
    end

    def hide(side)
      # TODO stub
    end

    def raise_all
      # TODO stub
    end

    def raise_(side)
      # TODO stub
    end

    def lower_all
      # TODO stub
    end

    def lower(side)
      # TODO stub
    end

    def synchronize(list)
      if list.empty?
        @side, @prev_side = @prev_side, @side
      else
        @side, @prev_side = list, @side
        new_buffer
      end
    end

    def clear_text_all
      @side = 0
      @selection = nil
      @lineno = 0
      @text_buffer = ['']
      @text_count.clear
      @line_regions = [[0, 0]]
      @data_buffer = []
      new_buffer
      @meta_buffer = []
      @link_buffer = []
      @images = []
      @sstp_marker = []
      @darea.queue_draw
    end

    def clear_text(side)
      @data_buffer.append
    end

    def new_buffer
      side2key = proc do |x|
        if x == 0
          key = 'sakura.name'
        elsif x == 1
          key = 'kero.name'
        else
          key = "char#{x}.name"
        end
        next key
      end
      if @side.instance_of?(Array)
        name = @side.map do |x|
          @parent.handle_request(:GET, :get_descript, side2key.call(x), default: 'unknown')
        end.join('&')
      else
        name = @parent.handle_request(:GET, :get_descript, side2key.call(@side))
      end
      name = 'unknown' if name.nil?
      @data_buffer << Post.new(name) do
        Data.new(
          pos: Position.new(x: 0, y: 0, w: 0, h: 0),
          content: Content.new(type: TYPE_UNKNOWN,
            data: nil,
            attr: Attribute.new(
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
            )),
          head: Head.new(valid: true,
                         x: Point.new(type: TYPE_ABSOLUTE, value: 0),
                         y: Point.new(type: TYPE_ABSOLUTE, value: 0)
                        )
        )
      end
    end

    def append_data(head = Head.new(valid: true, x: Point.new, y: Point.new), side = nil)
      last = @data_buffer.last
      x, y, h = get_last_cursor_position(last)
      last = last.last
      a = last.content.attr.dup
      # 画像のattrはすべて未指定の状態にする
      a.opaque = false
      a.inline = false
      a.clipping = [0, 0, -1, -1]
      a.fixed = false
      a.foreground = false
      a.is_sstp_marker = false
      @data_buffer.last << Data.new(
        pos: Position.new(x: x, y: y, w: 0, h: 0),
        content: Content.new(type: TYPE_UNKNOWN, attr: a),
        head: head,
      )
    end

    def new_buffer_with_cond(side)
      unless @side.instance_of?(Array)
        if @side != side
          @side = side
          last = @data_buffer.last
          unless last.length == 1 and last.last.content.type == TYPE_UNKNOWN
            new_buffer
          end
        end
      end
    end

    def new_line(side)
      new_buffer_with_cond(side)
      append_data(Head.new(valid: true, x: Point.new, y: Point.new), side)
    end

    def set_draw_absolute_x(side, pos)
      last = @data_buffer.last.last
      last.pos.x = pos
      last.head.x = Point.new(type: TYPE_ABSOLUTE, value: pos)
    end

    def set_draw_absolute_x_char(side, rate)
      set_draw_absolute_x(side, @char_width * rate)
    end

    def set_draw_relative_x(side, pos)
      last = @data_buffer.last.last
      last.pos.x += pos
      last.head.x = Point.new(type: TYPE_RELATIVE, value: pos)
    end

    def set_draw_relative_x_char(side, rate)
      set_draw_relative_x(side, @char_width * rate)
    end

    def set_draw_absolute_y(side, pos)
      last = @data_buffer.last.last
      last.pos.y = pos
      last.head.y = Point.new(type: TYPE_ABSOLUTE, value: pos)
    end

    def set_draw_absolute_y_char(side, rate, use_default_height: true)
      rx, ry, rh = get_last_cursor_position(@data_buffer.last)
      # 最初に\n系が呼ばれたときの処理
      if rh == 0 || use_default_height
        rh = @line_height
      end
      set_draw_absolute_y(side, (rh * rate).to_i)
    end

    def set_draw_relative_y(side, pos)
      last = @data_buffer.last.last
      last.pos.y += pos
      last.head.y = Point.new(type: TYPE_RELATIVE, value: pos)
    end

    def set_draw_relative_y_char(side, rate, use_default_height: true)
      rx, ry, rh = get_last_cursor_position(@data_buffer.last)
      # 最初に\n系が呼ばれたときの処理
      if rh == 0 || use_default_height
        rh = @line_height
      end
      set_draw_relative_y(side, (rh * rate).to_i)
    end

    def append_text(side, text)
      new_buffer_with_cond(side)
      @text_count[side] += text.length
      data = @data_buffer.last.last
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
            append_data
            set_draw_absolute_x(@side, 0)
            set_draw_relative_y_char(@side, 1.0, use_default_height: false)
            return append_text(@side, text)
          end
        end
        w, h = @layout.pixel_size
        data[:pos][:w] = w
        data[:pos][:h] = h
        data[:content][:data] = concat
      when TYPE_IMAGE
        # \nや\_lなどが行われていない場合にここに来るのでheadはfalse
        append_data
        return append_text(@side, text)
      end
      draw_last_line(:column => 0)
    end

    def append_sstp_marker(side)
      return if @sstp_surface.nil?
      unless @data_buffer.last.last[:content][:type] == TYPE_UNKNOWN
        append_data
      end
      data = @data_buffer.last.last
      data[:pos][:w] = @sstp_surface.width
      data[:pos][:h] = @char_height
      data[:content][:type] = TYPE_IMAGE
      data[:content][:data] = @sstp_surface
      data[:content][:attr] = Attribute.new(
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
      )
      @window.show
      @darea.queue_draw
    end

    def append_link_in(side, link_id, args)
      new_buffer_with_cond(side)
      data = @data_buffer.last
      sl = data.length - 1
      sn = if data[-1][:content][:type] == TYPE_TEXT
             data[-1][:content][:data].length
           else
             0
           end
      @link_buffer << Link.new(
        buffer_index: @data_buffer.length - 1,
        begin_index: sl,
        begin_offset: sn,
        end_index: sl,
        end_offset: sn,
        link_id: link_id,
        args: args,
        raw_text: '',
        text: ''
      )
    end

    def append_link_out(side, link_id, text, args)
      return unless text
      raw_text = text
      data = @data_buffer.last
      el = data.length - 1
      data = data.last
      en = if data[:content][:type] == TYPE_TEXT
             data[:content][:data].length
           else
             0
           end
      link = @link_buffer.last
      link.end_index = el
      link.end_offset = en
      link.raw_text = raw_text
      link.text = text
    end

    def append_link(side, label, value, args)
      append_link_in(side, label, args)
      append_text(side, value)
      append_link_out(side, label, value, args)
    end

    def append_meta(side, **kwargs)
      new_buffer_with_cond(side)
      data = @data_buffer.last.last
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
        append_data
      end
      when TYPE_IMAGE
        append_data
      end
      data = @data_buffer.last.last
      a = data[:content][:attr].dup
      kwargs.each do |k, v|
        a[k] = v
      end
      data[:content][:attr] = a
    end

    def append_image(side, path, **kwargs)
      new_buffer_with_cond(side)
      data = @data_buffer.last
      unless data.last[:content][:type] == TYPE_UNKNOWN
        append_data
      end
      data = data.last
      begin
        image_surface = @cache.load(path).surface(write: false)
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
      @window.show
      @darea.queue_draw
    end

    def draw_last_line(column: 0)
      return unless @__shown
      while get_bottom_position - @lineno * @line_height > @bg_surface.height * scale / 100.0
        @lineno += 1
      end
      @darea.queue_draw
    end

    def show_sstp_message(message, sender)
      # TODO stub
    end

    def hide_sstp_message
      # TODO stub
    end

    def open_communicatebox
      @communicatebox.show()
    end

    def open_teachbox
      @parent.handle_request(:GET, :notify_event, 'OnTeachStart')
      @teachbox.show()
    end

    def open_inputbox(symbol, limittime: -1, default: nil)
      @inputbox[symbol].new_(@desc, @communicate[3])
      @inputbox[symbol].set_symbol(symbol)
      @inputbox[symbol].set_limittime(limittime)
      @inputbox[symbol].show(default)
    end

    def open_passwordinputbox(symbol, limittime: -1, default: nil)
      @passwordinputbox[symbol].new_(desc, @communicate[3])
      @passwordinputbox[symbol].set_symbol(symbol)
      @passwordinputbox[symbol].set_limittime(limittime)
      @passwordinputbox[symbol].show(default)
    end

    def open_scriptinputbox()
      @scriptinputbox.show
    end

    def close_inputbox(symbol)
      @inputbox[symbol].close(symbol) if @inputbox.include?(symbol)
      @passwordinputbox[symbol].close(symbol) if @passwordinputbox.include?(symbol)
    end

    def close_communicatebox
      @communicatebox.close
    end

    def close_teachbox
      @teachbox.close
    end

    def destroy_inputbox(symbol)
      @inputbox.delete(symbol) if @inputbox.include?(symbol)
      @passwordinputbox.delete(symbol) if @passwordinputbox.include?(symbol)
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

    def get_last_cursor_position(data)
      x, y, h = 0, 0, 0
      data.reverse_each do |data|
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
      data.reverse_each do |data|
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
        if data[:head][:valid]
          break
        end
      end
      return [x, y, h]
    end

    def get_post_height(data)
      h_max = 0
      data.each do |data|
        case data[:content][:type]
        when TYPE_TEXT
          h_max = [h_max, data[:pos][:y] + data[:pos][:h]].max
        when TYPE_IMAGE
          y = data[:pos][:y]
          unless data[:content][:attr][:inline]
            y -= @origin_y
          end
          h_max = [h_max, y + data[:pos][:h]].max
        end
      end
      h_min = h_max
      data.each do |data|
        case data[:content][:type]
        when TYPE_TEXT
          h_min = [h_min, data[:pos][:y]].min
        when TYPE_IMAGE
          y = data[:pos][:y]
          unless data[:content][:attr][:inline]
            y -= @origin_y
          end
          h_min = [h_min, y + data[:pos][:h]].min
        end
      end
      return h_min, h_max
    end

    def get_bottom_position
      h = 0
      @data_buffer.each do |data|
        h += @post_top_surface.height
        h_min, h_max = get_post_height(data)
        h += ((h_max - h_min).to_f / @post_content_surface.height).ceil * @post_content_surface.height
        h += @post_bottom_surface.height
      end
      return h
    end

    def redraw(window, widget, cr)
      return if @parent.handle_request(:GET, :lock_repaint)
      return true unless @__shown
      fail "assert" if @bg_surface.nil?
      # draw bg
      cr.save
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.set_source(@bg_surface, 0, 0)
      cr.rectangle(0, 0, @bg_surface.width, @bg_surface.height)
      cr.fill
      cr.restore

      cr.translate(0, -@lineno * @line_height)

      cr.save
      @data_buffer.each do |data|
        next if data.all? do |x|
          x.content.type == TYPE_UNKNOWN
        end
        # post top image
        cr.set_operator(Cairo::OPERATOR_OVER) # restore default
        cr.set_source(@post_top_surface, 0, 0)
        cr.mask(@post_top_surface, 0, 0)
        translate_h = @post_top_surface.height

        # post name
        cr.save
        cr.rectangle(@name_x, @name_y, @post_top_surface.width - @name_x, @post_top_surface.height - @name_y)
        cr.clip
        cr.move_to(@name_x, @name_y)
        @layout.set_width(-1)
        @layout.set_indent(0)
        name = CGI.escapeHTML(data.name)
        @layout.set_markup(name)
        cr.set_source_rgb(@text_normal_color)
        cr.show_pango_layout(@layout)
        cr.reset_clip
        cr.restore

        cr.translate(0, translate_h)

        # post content image
        cr.save
        h_min, h_max = get_post_height(data)
        loop_n = ((h_max - h_min).to_f / @post_content_surface.height).ceil
        translate_h = loop_n * @post_content_surface.height
        loop_n.times do |i|
          cr.set_operator(Cairo::OPERATOR_OVER) # restore default
          cr.set_source(@post_content_surface, 0, 0)
          cr.mask(@post_content_surface, 0, 0)
          cr.translate(0, @post_content_surface.height)
        end
        cr.restore

        # post content
        cr.save
        cr.rectangle(@origin_x, 0, @valid_width, @origin_y + @valid_height)
        cr.clip
        # draw background image
        data.each do |data|
          x = data[:pos][:x]
          y = data[:pos][:y] - h_min
          w = data[:pos][:w]
          h = data[:pos][:h]
          unless data[:content][:type] == TYPE_IMAGE and
              not data[:content][:attr][:foreground]
            next
          end
          if data[:content][:attr][:fixed]
            if y + h < 0 or y > @origin_y + @valid_height
              next
            end
          else
            y1 = y
            if data[:content][:attr][:inline]
              y1 += @origin_y
            end
            if y1 + h < 0 or y > @origin_y + @valid_height
              next
            end
          end
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
                cr.set_source(data[:content][:data], @origin_x + x, @origin_y + y + ((@char_height - data[:content][:data].height) / 2).to_i)
              else
                cr.set_source(data[:content][:data], @origin_x + x, @origin_y + y)
              end
            else
              cr.set_source(data[:content][:data], x, y)
            end
          end
          cr.paint
        end
        cr.reset_clip
        # draw text
        cr.rectangle(@origin_x, @origin_y, @valid_width, @origin_y + @valid_height)
        cr.clip
        @layout.set_width(-1)
        data.each do |data|
          x = data[:pos][:x]
          y = data[:pos][:y] - h_min
          w = data[:pos][:w]
          h = data[:pos][:h]
          unless data[:content][:type] == TYPE_TEXT
            next
          end
          y1 = y + @origin_y
          if y1 + h < 0 or y1 > @origin_y + @valid_height
            next
          end
          @layout.set_indent(x * Pango::SCALE)
          markup = set_markup(data[:content][:data], data[:content][:attr])
          @layout.set_markup(markup)
          cr.set_source_rgb(@text_normal_color)
          cr.move_to(@origin_x, @origin_y + y)
          cr.show_pango_layout(@layout)
        end
        cr.reset_clip
        # draw foreground image
        cr.rectangle(@origin_x, 0, @valid_width, @origin_y + @valid_height)
        cr.clip
        data.each do |data|
          x = data[:pos][:x]
          y = data[:pos][:y] - h_min
          w = data[:pos][:w]
          h = data[:pos][:h]
          unless data[:content][:type] == TYPE_IMAGE and
              data[:content][:attr][:foreground]
            next
          end
          if data[:content][:attr][:fixed]
            if y + h < 0 or y > @origin_y + @valid_height
              next
            end
          else
            y1 = y
            if data[:content][:attr][:inline]
              y1 += @origin_y
            end
            if y1 + h < 0 or y > @origin_y + @valid_height
              next
            end
          end
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
        cr.restore

        cr.translate(0, translate_h)

        # post bottom image
        cr.set_operator(Cairo::OPERATOR_OVER) # restore default
        cr.set_source(@post_bottom_surface, 0, 0)
        cr.mask(@post_bottom_surface, 0, 0)
        translate_h = @post_bottom_surface.height

        cr.translate(0, translate_h)
      end
      cr.restore
      update_link_region(widget, cr, @selection) unless @selection.nil?
    end

    def redraw2(window, widget, cr)
      redraw_sstp_message(widget, cr) if @side.zero? and not @sstp_message.nil?
      update_link_region(widget, cr, @selection) unless @selection.nil?
      redraw_arrow0(widget, cr)
      redraw_arrow1(widget, cr)
      return true
    end

    def check_link_region(px, py)
      new_selection = nil
      @link_buffer.each_with_index do |link, selection|
        index = link.buffer_index
        offset_h = -@lineno * @line_height
        index.times do |i|
          data = @data_buffer[i]
          offset_h += @post_top_surface.height
          h_min, h_max = get_post_height(data)
          offset_h += ((h_max - h_min).to_f / @post_content_surface.height).ceil * @post_content_surface.height
          offset_h += @post_bottom_surface.height
        end
        offset_h += @post_top_surface.height
        sl = link.begin_index
        el = link.end_index
        sn = link.begin_offset
        en = link.end_offset
        for n in sl .. el
          data = @data_buffer[index][n]
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
              if @origin_x + x <= px and px < @origin_x + nx and offset_h + @origin_y + y <= py and py < offset_h + @origin_y + y + nh
                new_selection = selection
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
              y = y
            end
            y1 = [y, 0].max
            y2 = [y + h, @origin_y + @valid_height].min
            if data[:content][:attr][:inline]
              y2 = [y + h, @valid_height].min
              x += @origin_x
              y1 += @origin_y
              y2 += @origin_y
            end
            if x <= px and px < x + w and offset_h + y1 <= py and py < offset_h + y2
              new_selection = selection
            end
          else
            # nop
          end
          if new_selection == selection
            break
          end
        end
        if new_selection == selection
          break
        end
      end
      unless @hover_id.nil?
        GLib::Source.remove(@hover_id)
        @hover_id = nil
      end
      unless new_selection.nil?
        link = @link_buffer[new_selection]
        is_anchor = @parent.handle_request(:GET, :is_anchor, link.link_id)
        if @selection != new_selection
          if is_anchor
            @parent.handle_request(
              :GET, :notify_event,
              'OnAnchorEnter', link.raw_text, link.link_id[1], *link.args)
          else
            @parent.handle_request(
              :GET, :notify_event,
              'OnChoiceEnter', link.raw_text, link.link_id, *link.args)
          end
        end
        @hover_id = GLib::Timeout.add(1000) do
          @hover_id = nil
          if is_anchor
            @parent.handle_request(
              :GET, :notify_event,
              'OnAnchorHover', link.raw_text, link.link_id[1], *link.args)
          else
            @parent.handle_request(
              :GET, :notify_event,
              'OnChoiceHover', link.raw_text, link.link_id, *link.args)
          end
        end
      else
        unless @selection.nil?
          link = @link_buffer[@selection]
          is_anchor = @parent.handle_request(:GET, :is_anchor, link.link_id)
          if is_anchor
            @parent.handle_request(:GET, :notify_event, 'OnAnchorEnter')
          else
            @parent.handle_request(:GET, :notify_event, 'OnChoiceEnter')
          end
        end
      end
      if new_selection == @selection
        return false
      else
        @selection = new_selection
        return true # dirty flag
      end
    end

    def update_link_region(widget, cr, index)
      cr.save()
      link = @link_buffer[index]
      sl = link.begin_index
      el = link.end_index
      sn = link.begin_offset
      en = link.end_offset
      offset_h = -@lineno * @line_height
      link.buffer_index.times do |i|
        data = @data_buffer[i]
        offset_h += @post_top_surface.height
        h_min, h_max = get_post_height(data)
        offset_h += ((h_max - h_min).to_f / @post_content_surface.height).ceil * @post_content_surface.height
        offset_h += @post_bottom_surface.height
      end
      offset_h += @post_top_surface.height
      cr.translate(0, offset_h)
      cr.rectangle(@origin_x, 0, @valid_width, @origin_y + @valid_height)
      cr.clip
      for n in sl .. el
        data = @data_buffer[link.buffer_index][n]
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
              cr.rectangle(@origin_x + x, @origin_y + y, nx - x, nh)
              cr.fill()
            end
            x = nx
          end
          x = x_bak
          cr.move_to(@origin_x, @origin_y + y)
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
          y = y
          cr.rectangle(x, y, w, h)
          cr.stroke
        else
          # nop
        end
      end
      cr.reset_clip
      cr.restore()
    end

    def scale
      scaling = (not @parent.handle_request(:GET, :get_preference, 'balloon_scaling').zero?)
      scale = @parent.handle_request(:GET, :get_preference, 'surface_scale')
      if scaling
        return scale
      else
        return 100 # [%]
      end
    end

    def set_balloon_direction(side, direction)
      # nop
    end
  end


  class Balloon < MetaMagic::Holon
    attr_accessor :window, :user_interaction

    def initialize
      super("") # FIXME
      @handlers = {
        :reset_user_interaction => :reset_user_interaction,
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
      @inputbox = Hash.new do |h, k|
        # configure inputbox
        i = InputBox.new
        i.set_responsible(self)
        h[k] = i
      end
      # create passwordinputbox
      @passwordinputbox = Hash.new do |h, k|
        # configure passwordinputbox
        p = PasswordInputBox.new
        p.set_responsible(self)
        h[k] = p
      end
      # create scriptbox
      @scriptinputbox = ScriptInputBox.new()
      @scriptinputbox.set_responsible(self)
    end

    def reset_user_interaction
=begin
      visible = true
      visible &&= @communicatebox.visible?
      visible &&= @teachbox.visible?
      visible &&= @inputbox.all? do |k, v|
        v.visible?
      end
      visible &&= @passwordinputbox.all? do |k, v|
        v.visible?
      end
      @user_interaction = visible
=end
    end

    def get_text_count(side)
      return @window[side].get_text_count()
    end

    def get_window(side)
      return @window[side].get_window
    end

    def reset_text_count(side)
      @window[side].reset_text_count()
    end

    def reset_balloon
      for balloon_window in @window.values
        balloon_window.reset_balloon()
      end
    end

    def create_gtk_window(title, monitor)
      window = Pix::TransparentWindow.new(monitor)
      window.set_title(title)
      @parent.handle_request(:NOTIFY, :associate_application, window)
      window.signal_connect('close-request') do |w, e|
        next delete(w, e)
      end
      # FIXME window.realize
      # FIXME delete?
      #window.show
      #window.hide
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
      @inputbox.each.to_a.each do |k, v|
        v.close(k)
      end
      @passwordinputbox.each.to_a.each do |k, v|
        v.close(k)
      end
    end

    def new_(desc, balloon)
      @desc = desc
      @directory = balloon['balloon_dir'][0]
      balloon0 = {}
      balloon1 = {}
      @communicate = []
      0.upto(3) do |i|
        key = 'c' + i.to_s
        @communicate[i] = balloon[key] if balloon.include?(key) 
      end
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
        end
      end
      @balloon0 = balloon0
      @balloon1 = balloon1
      # create balloon windows
      for balloon_window in @window.values
        balloon_window.destroy()
      end
      @window = Hash.new do |hash, key|
        add_window(key)
      end
      add_window(0)
      add_window(1)
      # configure communicatebox
      @communicatebox.new_(desc, @communicate[1])
      # configure teachbox
      @teachbox.new_(desc, @communicate[2])
      # configure scriptinputbox
      @scriptinputbox.new_(desc, @communicate[3])
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
      gtk_windows = []
      if ENV.include?('NINIX_ENABLE_MULTI_MONITOR')
        monitors = Gdk::Display.default.monitors
        monitors.n_items.times do |i|
          gtk_windows << create_gtk_window(name, monitors.get_item(i))
        end
      else
        gtk_windows << create_gtk_window(name, nil)
      end
      balloon_window = BalloonWindow.new(
        gtk_windows, side, @desc, balloon, id_format)
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
      return @window[side].get_balloon_size()
    end

    def get_balloon_windowposition(side)
      return @window[side].get_balloon_windowposition()
    end

    def set_balloon_default(side: -1)
      default_id = @parent.handle_request(:GET, :get_balloon_default_id)
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
      @window[side].set_balloon(num)
    end

    def set_position(side, base_x, base_y)
      @window[side].set_position(base_x, base_y)
    end

    def get_position(side)
      return @window[side].get_position()
    end

    def set_autoscroll(flag)
      for side in @window.keys
        @window[side].set_autoscroll(flag)
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
        @window[side].raise_()
      end
    end

    def raise_(side)
      @window[side].raise_()
    end

    def lower_all
      for side in @window.keys
        @window[side].lower()
      end
    end

    def lower(side)
      @window[side].lower()
    end

    def synchronize(list)
      @synchronized = list
    end

    def set_balloon_direction(side, direction)
      @window[side].direction = direction
    end

    def clear_text_all
      for side in @window.keys
        clear_text(side)
      end
    end

    def clear_text(side)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].clear_text()
        end
      else
        @window[side].clear_text()
      end
    end

    def new_line(side)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].new_line
        end
      else
        @window[side].new_line
      end
    end

    def set_draw_absolute_x(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_absolute_x(pos)
        end
      else
        @window[side].set_draw_absolute_x(pos)
      end
    end

    def set_draw_absolute_x_char(side, rate)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_absolute_x_char(rate)
        end
      else
        @window[side].set_draw_absolute_x_char(rate)
      end
    end

    def set_draw_relative_x(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_relative_x(pos)
        end
      else
        @window[side].set_draw_relative_x(pos)
      end
    end

    def set_draw_relative_x_char(side, rate)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_relative_x(rate)
        end
      else
        @window[side].set_draw_relative_x(rate)
      end
    end

    def set_draw_absolute_y(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_absolute_y(pos)
        end
      else
        @window[side].set_draw_absolute_y(pos)
      end
    end

    def set_draw_absolute_y_char(side, rate, **kwarg)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_absolute_y_char(rate, **kwarg)
        end
      else
        @window[side].set_draw_absolute_y_char(rate, **kwarg)
      end
    end

    def set_draw_relative_y(side, pos)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_relative_y(pos)
        end
      else
        @window[side].set_draw_relative_y(pos)
      end
    end

    def set_draw_relative_y_char(side, rate, **kwarg)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].set_draw_relative_y_char(rate, **kwarg)
        end
      else
        @window[side].set_draw_relative_y_char(rate, **kwarg)
      end
    end

    def append_text(side, text)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].append_text(text)
        end
      else
        @window[side].append_text(text)
      end
    end

    def append_sstp_marker(side)
      @window[side].append_sstp_marker()
    end

    def append_link_in(side, label, args)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].append_link_in(label, args)
        end
      else
        @window[side].append_link_in(label, args)
      end
    end

    def append_link_out(side, label, value, args)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].append_link_out(label, value, args)
        end
      else
        @window[side].append_link_out(label, value, args)
      end
    end

    def append_link(side, label, value, args)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].append_link_in(label, args)
          @window[side].append_text(value)
          @window[side].append_link_out(label, value, args)
        end
      else
        @window[side].append_link_in(label, args)
        @window[side].append_text(value)
        @window[side].append_link_out(label, value, args)
      end
    end

    def append_meta(side, **kwargs)
      unless @synchronized.empty?
        for side in @synchronized
          @window[side].append_meta(**kwargs)
        end
      else
        @window[side].append_meta(**kwargs)
      end
    end

    def append_image(side, path, **kwargs)
      @window[side].append_image(path, **kwargs)
    end

    def show_sstp_message(message, sender)
      @window[0].show_sstp_message(message, sender)
    end

    def hide_sstp_message
      @window[0].hide_sstp_message()
    end

    def open_communicatebox
      #return if @user_interaction
      #@user_interaction = true
      @communicatebox.show()
    end

    def open_teachbox
      #return if @user_interaction
      #@user_interaction = true
      @parent.handle_request(:GET, :notify_event, 'OnTeachStart')
      @teachbox.show()
    end

    def open_inputbox(symbol, limittime: -1, default: nil)
      #return if @user_interaction
      #@user_interaction = true
      @inputbox[symbol].new_(@desc, @communicate[3])
      @inputbox[symbol].set_symbol(symbol)
      @inputbox[symbol].set_limittime(limittime)
      @inputbox[symbol].show(default)
    end

    def open_passwordinputbox(symbol, limittime: -1, default: nil)
      #return if @user_interaction
      #@user_interaction = true
      @passwordinputbox[symbol].new_(desc, @communicate[3])
      @passwordinputbox[symbol].set_symbol(symbol)
      @passwordinputbox[symbol].set_limittime(limittime)
      @passwordinputbox[symbol].show(default)
    end

    def open_scriptinputbox()
      #return if @user_interaction
      #@user_interaction = true
      @scriptinputbox.show
    end

    def close_inputbox(symbol)
      #return unless @user_interaction
      @inputbox[symbol].close(symbol) if @inputbox.include?(symbol)
      @passwordinputbox[symbol].close(symbol) if @passwordinputbox.include?(symbol)
    end

    def close_communicatebox
      #return unless @user_interaction
      @communicatebox.close
    end

    def close_teachbox
      #return unless @user_interaction
      @teachbox.close
    end

    def destroy_inputbox(symbol)
      @inputbox.delete(symbol) if @inputbox.include?(symbol)
      @passwordinputbox.delete(symbol) if @passwordinputbox.include?(symbol)
    end
  end


  class BalloonWindow
    attr_accessor :direction

    def initialize(windows, side, desc, balloon, id_format)
      @windows = windows
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
      @offset = [0, 0]
      @reshape = true
      @pix_cache = Pix::Cache.new
      @raise_id = {}
      @windows.each do |window|
        darea = window.darea
        darea.set_draw_func do |w, e|
          redraw(window, w, e)
          next true
        end
        button_controller = Gtk::GestureClick.new
        # 全てのボタンをlisten
        button_controller.set_button(0)
        button_controller.signal_connect('pressed') do |w, n, x, y|
          next button_press(window, darea, w, n, x, y)
        end
        darea.add_controller(button_controller)
        motion_controller = Gtk::EventControllerMotion.new
        motion_controller.signal_connect('motion') do |w, x, y|
          next motion_notify(window, darea, w, x, y)
        end
        darea.add_controller(motion_controller)
        scroll_controller = Gtk::EventControllerScroll.new(Gtk::EventControllerScrollFlags::VERTICAL)
        scroll_controller.signal_connect('scroll') do |w, dx, dy|
          next scroll(window, darea, dx, dy)
        end
        darea.add_controller(scroll_controller)
      end
      pango_context = Gtk::DrawingArea.new.pango_context
      @layout = Pango::Layout.new(pango_context)
      @sstp_layout = Pango::Layout.new(pango_context)
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

    def set_responsible(parent)
      @parent = parent
    end

    def raise
      #@window.window.raise
    end

    #@property
    def scale
      scaling = (not @parent.handle_request(:GET, :get_preference, 'balloon_scaling').zero?)
      scale = @parent.handle_request(:GET, :get_preference, 'surface_scale')
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
        use_pna = (not @parent.handle_request(:GET, :get_preference, 'use_pna').zero?)
        surface = @pix_cache.load(path, use_pna: use_pna)
      rescue
        return nil
      end
      return surface
    end

    def reset_fonts
      unless @parent.nil?
        font_name = @parent.handle_request(:GET, :get_preference, 'balloon_fonts')
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
          @windows.each do |window|
            window.darea.queue_draw()
          end
        end
      end
    end

    def reset_sstp_marker
      if @side.zero?
        fail "assert" if @balloon_surface.nil?
        surface = @balloon_surface.surface(write: false)
        w = surface.width
        h = surface.height
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
      surface = @balloon_surface.surface(write: false)
      w = surface.width
      h = surface.height
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
      surface = @balloon_surface.surface(write: false)
      @width = surface.width
      @height = surface.height
      @parent.handle_request(:NOTIFY, :update_balloon_rect, @side, x, y, @width, @height)
      @parent.handle_request(:NOTIFY, :update_balloon_offset, @side, *@offset)
      reset_arrow()
      reset_sstp_marker()
      reset_message_regions()
      @parent.handle_request(:NOTIFY, :reset_balloon_position, @side)
      @windows.each do |window|
        window.darea.queue_draw()
      end if @__shown
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
      @windows.each do |window|
        window.darea.queue_draw
      end
    end

    def set_position(base_x, base_y)
      return if @balloon_id.nil?
      px, py = get_balloon_windowposition()
      w, h = get_balloon_size()
      x = (base_x + px)
      y = (base_y + py)
=begin TODO implement
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea, nil)
      if (y + h) > top + scrn_h # XXX
        y = (scrn_h - h)
      end
      if y < top # XXX
        y = top
      end
=end
      @position = [x, y]
      __move()
    end

    def get_position
      @position
    end

    def destroy(finalize: 0)
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
      @__shown = true
      # make sure window is in its position (call before showing the window)
      __move()
      @windows.each do |window|
        window.show()
      end
      # make sure window is in its position (call after showing the window)
      __move()
      raise_()
      @reshape = true
    end

    def hide
      return unless @__shown
      @windows.each do |window|
        window.hide()
      end
      @__shown = false
      @images = []
    end

    def raise_
      return unless @__shown
      # TODO delete?
      #@window.window.raise
      @windows.each do |window|
        @raise_id[window] = window.signal_connect('hide') do |w|
          w.show
          w.signal_handler_disconnect(@raise_id[w])
          @raise_id.delete(w)
        end
        window.hide
      end
    end

    def lower
      return unless @__shown
      #@window.get_window().lower()
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
      @windows.each do |window|
        window.darea.queue_draw()
      end
    end

    def hide_sstp_message
      @sstp_message = nil
      @windows.each do |window|
        window.darea.queue_draw()
      end
    end

    def redraw_sstp_message(widget, cr)
      return if @sstp_message.nil?
      cr.save()
      # draw sstp marker
      unless @sstp_surface.nil?
        x, y = @sstp[0]            
        cr.set_source(@sstp_surface.surface(write: false), x, y)
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
      cr.set_source(@arrow0_surface.surface(write: false), x, y)
      cr.paint()
      cr.restore()
    end

    def redraw_arrow1(widget, cr)
      return if get_bottom_position > @valid_height
      cr.save()
      x, y = @arrow[1]
      cr.set_source(@arrow1_surface.surface(write: false), x, y)
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
        if data[:head][:valid]
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

    def redraw(window, widget, cr)
      return if @parent.handle_request(:GET, :lock_repaint)
      return true unless @__shown
      return true if window.rect.nil?
      fail "assert" if @balloon_surface.nil?
      window.set_surface(cr, @balloon_surface.surface(write: false), scale, @position)
      cr.set_operator(Cairo::OPERATOR_OVER) # restore default
      pos = get_position
      cr.translate(pos[0] - window.rect.x, pos[1] - window.rect.y)
      # FIXME: comment
      cr.rectangle(@origin_x, 0, @valid_width, @origin_y + @valid_height)
      cr.clip
      # draw background image
      for i in 0..(@data_buffer.length - 1)
        data = @data_buffer[i]
        x = data[:pos][:x]
        y = data[:pos][:y]
        w = data[:pos][:w]
        h = data[:pos][:h]
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
              mw = @sstp_surface.surface.width
              mh = @sstp_surface.surface.height
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
      window.set_shape(@balloon_surface.region(write: false), get_position)
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
      pos = get_position
      px -= pos[0]
      py -= pos[1]
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
      unless @hover_id.nil?
        GLib::Source.remove(@hover_id)
        @hover_id = nil
      end
      unless new_selection.nil?
        sl, sn, el, en, link_id, args, raw_text, text =
          @link_buffer[new_selection]
        is_anchor = @parent.handle_request(:GET, :is_anchor, link_id)
        if @selection != new_selection
          if is_anchor
            @parent.handle_request(
              :GET, :notify_event,
              'OnAnchorEnter', raw_text, link_id[1], *args)
          else
            @parent.handle_request(
              :GET, :notify_event,
              'OnChoiceEnter', raw_text, link_id, *args)
          end
        end
        @hover_id = GLib::Timeout.add(1000) do
          @hover_id = nil
          if is_anchor
            @parent.handle_request(
              :GET, :notify_event,
              'OnAnchorHover', raw_text, link_id[1], *args)
          else
            @parent.handle_request(
              :GET, :notify_event,
              'OnChoiceHover', raw_text, link_id, *args)
          end
        end
      else
        unless @selection.nil?
          sl, sn, el, en, link_id, args, raw_text, text =
            @link_buffer[@selection]
          is_anchor = @parent.handle_request(:GET, :is_anchor, link_id)
          if is_anchor
            @parent.handle_request(:GET, :notify_event, 'OnAnchorEnter')
          else
            @parent.handle_request(:GET, :notify_event, 'OnChoiceEnter')
          end
        end
      end
      if new_selection == @selection
        return false
      else
        @selection = new_selection
        return true # dirty flag
      end
    end

    def motion_notify(window, widget, ctrl, x, y)
      state = nil
      px, py = window.winpos_to_surfacepos(x, y, scale)
      unless @link_buffer.empty?
        if check_link_region(px, py)
          widget.queue_draw()
        end
      end
      unless @parent.handle_request(:GET, :busy)
        unless @x_root.nil? or @y_root.nil?
          @dragged = true
          x_delta = ((px - @x_root) * 100 / scale + @x_fractions)
          y_delta = ((py - @y_root) * 100 / scale + @y_fractions)
          @offset[0] += x_delta.to_i
          @offset[1] += y_delta.to_i
          @x_fractions = (x_delta - x_delta.to_i)
          @y_fractions = (y_delta - y_delta.to_i)
          @parent.handle_request(
            :GET, :update_balloon_offset,
            @side, *@offset)
          @x_root = px
          @y_root = py
          set_position(px, py)
        end
      end
      # TODO delete?
      #Gdk::Event.request_motions(event) if event.is_hint == 1
      return true
    end

    def scroll(window, darea, dx, dy)
      px, py = window.winpos_to_surfacepos(
            dx, dy, scale)
      if dy > 0
        if @lineno > 0
          @lineno = @lineno - 1
          check_link_region(px, py)
          darea.queue_draw()
        end
      elsif dy < 0
        if get_bottom_position > @valid_height
          @lineno += 1
          check_link_region(px, py)
          darea.queue_draw()
        end
      end
      return true
    end

    def button_press(window, darea, ctrl, n, x, y)
      @parent.handle_request(:GET, :reset_idle_time)
      if @parent.handle_request(:GET, :is_paused)
        @parent.handle_request(:GET, :notify_balloon_click,
                               ctrl.button, 1, @side)
        return true
      end
      # arrows
      px, py = window.winpos_to_surfacepos(
            x, y, scale)
      if ctrl.button == 1
        @x_root = x
        @y_root = y
      end
      # up arrow
      surface = @arrow0_surface.surface(write: false)
      w = surface.width
      h = surface.height
      x, y = @arrow[0]
      if x <= px and px <= (x + w) and y <= py and py <= (y + h)
        if @lineno > 0
          @lineno = @lineno - 1
          darea.queue_draw()
        end
        return true
      end
      # down arrow
      surface = @arrow1_surface.surface(write: false)
      w = surface.width
      h = surface.height
      x, y = @arrow[1]
      if x <= px and px <= (x + w) and y <= py and py <= (y + h)
        if get_bottom_position > @valid_height
          @lineno += 1
          darea.queue_draw()
        end
        return true
      end
      # links
      unless @selection.nil?
        sl, sn, el, en, link_id, args, raw_text, text = \
        @link_buffer[@selection]
        @parent.handle_request(:GET, :notify_link_selection,
                               link_id, raw_text, args, @selection)
        return true
      end
      # balloon's background
      @parent.handle_request(:GET, :notify_balloon_click,
                             ctrl.button, 1, @side)
      #@x_root = event.x_root
      #@y_root = event.y_root
      return true
    end

    def button_release(window, w, n, x, y)
      x, y = window.winpos_to_surfacepos(
           event.x.to_i, event.y.to_i, scale)
      set_position(x, y) if @dragged
      @dragged = false if @dragged
      @x_root = nil
      @y_root = nil
      @x_fractions = 0
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
        head: {
          valid: true,
          x: {type: TYPE_ABSOLUTE, value: 0},
          y: {type: TYPE_ABSOLUTE, value: 0},
        },
      }]
      @meta_buffer = []
      @link_buffer = []
      @newline_required = false
      @images = []
      @sstp_marker = []
      @windows.each do |window|
        window.darea.queue_draw
      end
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

    def new_buffer(head: {valid: false, x: {}, y: {}})
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
        head: head,
      }
    end

    def new_line
      new_buffer(head: {valid: true, x: {}, y: {}})
    end

    def set_draw_absolute_x(pos)
      data = @data_buffer[-1]
      new = data[:pos].dup
      new[:x] = pos
      @data_buffer[-1] = {
        pos: new,
        content: data[:content],
        head: {
          valid: true,
          x: {type: TYPE_ABSOLUTE, value: pos},
          y: data[:head][:y],
        },
      }
    end

    def set_draw_absolute_x_char(rate)
      set_draw_absolute_x(@char_width * rate)
    end

    def set_draw_relative_x(pos)
      x = @data_buffer[-1][:pos][:x]
      set_draw_absolute_x(x + pos)
      @data_buffer[-1][:head][x] = { type: TYPE_RELATIVE, value: pos }
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
        head: {
          valid: true,
          x: data[:head][:x],
          y: {type: TYPE_ABSOLUTE, value: pos},
        },
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
      @data_buffer[-1][:head][:y] = { type: TYPE_RELATIVE, value: pos }
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
      @text_count += text.length
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
            new_buffer
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
        # \nや\_lなどが行われていない場合にここに来るのでheadはfalse
        new_buffer
        return append_text(text)
      end
      draw_last_line(:column => 0)
    end

    def append_sstp_marker
      return if @sstp_surface.nil?
      unless @data_buffer[-1][:content][:type] == TYPE_UNKNOWN
        new_buffer
      end
      data = @data_buffer[-1]
      data[:pos][:w] = @sstp_surface.surface(write: false).width
      data[:pos][:h] = @char_height
      data[:content][:type] = TYPE_IMAGE
      data[:content][:data] = @sstp_surface.surface(write: false)
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
      @windows.each do |window|
        window.darea.queue_draw
      end
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
        new_buffer
      end
      when TYPE_IMAGE
        new_buffer
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
        new_buffer
      end
      data = @data_buffer[-1]
      begin
        image_surface = @pix_cache.load(path).surface(write: false)
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
      @windows.each do |window|
        window.darea.queue_draw
      end
    end

    def draw_last_line(column: 0)
      return unless @__shown
      while get_bottom_position > @valid_height
        @lineno += 1
      end
      @windows.each do |window|
        window.darea.queue_draw
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
      @window.destroy unless @window.nil?
      @window = Pix::BaseTransparentWindow.new()
      @parent.handle_request(:NOTIFY, :associate_application, @window)
      @__surface_position = [0, 0]
      @window.set_title('communicate')
      @window.signal_connect('close-request') do |w ,e|
        next delete(w, e)
      end
      button_controller = Gtk::GestureClick.new
      button_controller.signal_connect('pressed') do |w, n, x, y|
        next button_press(@window, w, n, x, y)
      end
      button_controller.signal_connect('released') do |w, n, x, y|
        next button_release(@window, w, n, x, y)
      end
      @window.add_controller(button_controller)
      dad_controller = Gtk::DropTarget.new(GLib::Type::INVALID, 0)
      dad_controller.signal_connect('drop') do |widget, context, x, y, data, info, time|
        drag_data_received(@window, context, x, y, data, info, time)
        next true
      end
      @window.add_controller(dad_controller)
      key_controller = Gtk::EventControllerKey.new
      key_controller.signal_connect('key-pressed') do |ctrl, keyval, keycode, state|
        next key_press(ctrl.widget, ctrl, keyval, keycode, state)
      end
      # DnD data types
      dnd_targets = [['text/plain', 0, 0]]
=begin
      @window.drag_dest_set(Gtk::DestDefaults::ALL, dnd_targets,
                            Gdk::DragAction::COPY)
      @window.drag_dest_add_text_targets()
=end
      #@window.set_events(Gdk::EventMask::BUTTON_PRESS_MASK)
      #@window.set_window_position(Gtk::WindowPosition::CENTER)
      # FIXME @window.realize()
      # FIXME delete?
      #@window.show
      #@window.hide
=begin TODO delete?
      @window.override_background_color(
        Gtk::StateFlags::NORMAL, Gdk::RGBA.new(0, 0, 0, 0))
=end
      w = desc.get('communicatebox.width', :default => 250).to_i
      h = desc.get('communicatebox.height', :default => -1).to_i
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea, get_gdk_window)
      @__surface_position = [(scrn_w - w) / 2, (scrn_h - h) / 2] # XXX
      @entry = Gtk::Entry.new
      @entry.signal_connect('activate') do |w|
        next activate(w)
      end
      #@entry.set_inner_border(nil)
      @entry.set_has_frame(false)
      font_desc = Pango::FontDescription.new()
      font_desc.set_size(9 * 3 / 4 * Pango::SCALE) # XXX
      #@entry.override_font(font_desc)
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
          cache = Pix::Cache.new
          surface = cache.load(path)
        rescue
          surface = nil
        end
      end
      unless surface.nil?
        darea = Gtk::DrawingArea.new()
        #darea.set_events(Gdk::EventMask::EXPOSURE_MASK)
        darea.set_draw_func do |w, e|
          redraw(w, e, surface)
          next true
        end
        darea.show()
        x = desc.get('communicatebox.x', :default => 10).to_i
        y = desc.get('communicatebox.y', :default => 20).to_i
        overlay = Gtk::Overlay.new()
        #@entry.set_margin_left(x)
        #@entry.set_margin_top(y)
        @entry.set_halign(Gtk::Align::START)
        @entry.set_valign(Gtk::Align::START)
        overlay.add_overlay(@entry)
        overlay.set_child(darea)
        overlay.show()
        @window.set_child(overlay)
        # FIXME
        #darea.set_size_request(*@window.size) # XXX
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

    def get_gdk_window
      #@window.window
    end

    def drag_data_received(widget, context, x, y, data, info, time)
      @entry.set_text(data.text)
    end

    def get_draw_offset
      return @__surface_position
    end

    def redraw(widget, cr, pix)
      surface = pix.surface(write: false)
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
=begin
      w, h = @window.size
      unless w == surface.width and h == surface.height
        @window.resize(surface.width, surface.height)
      end
=end
      return if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      region = pix.region(write: false)
      # XXX: to avoid losing focus in the text input region
      #x = @entry.margin_left
      #y = @entry.margin_top
      w = @entry.allocated_width
      h = @entry.allocated_height
=begin TODO delete?
      region.union!(x, y, w, h)
      if @window.supports_alpha
        @window.input_shape_combine_region(nil)
        @window.input_shape_combine_region(region)
      else
        @window.shape_combine_region(nil)
        @window.shape_combine_region(region)
      end
=end
    end

    def destroy
      @window.destroy unless @window.nil?
      @window = nil
    end

    def delete(widget, event)
      close(nil)
      cancel
      return true
    end

    def key_press(widget, ctrl, keyval, keycode, state)
      if keyval == Gdk::Keyval::KEY_Escape
        close(nil)
        cancel
        return true
      end
      return false
    end

    def button_press(widget, w, n, x, y)
      if [1, 2].include?(w.button)
=begin TODO stub
        @window.begin_move_drag(
          event.button, w.x_root.to_i, event.y_root.to_i,
          Gtk.current_event_time())
=end
      end
      return true
    end

    def activate(widget)
      enter
      close(nil)
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

    def close(symbol)
      @window.hide
      @parent.handle_request(:GET, :reset_user_interaction)
    end

    def visible?
      @window.visible?
    end
  end


  class CommunicateBox < CommunicateWindow

    NAME = 'communicatebox'
    ENTRY = 'Communicate'

    def new_(desc, balloon)
      super
      @window.set_modal(false)
    end

    def enter
      send(@entry.text)
    end

    def cancel
      @parent.handle_request(:GET, :notify_event,
                             'OnCommunicateInputCancel', '', 'cancel')
    end

    def send(data)
      unless data.nil?
        @parent.handle_request(:GET, :notify_event,
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
      @parent.handle_request(:GET, :notify_event,
                             'OnTeachInputCancel', '', 'cancel')
      @parent.handle_request(:GET, :reset_user_interaction)
    end

    def send(data)
      @parent.handle_request(:GET, :notify_user_teach, data)
      @parent.handle_request(:GET, :reset_user_interaction)
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
      return if symbol != '__SYSTEM_ALL_INPUT__' and @symbol != symbol
      destroy
      @parent.handle_request(:NOTIFY, :destroy_inputbox, @symbol)
    end

    def send(data, cancel: false, timeout: false)
      GLib.source_remove(@timeout_id) unless @timeout_id.nil?
      data = '' if data.nil?
      ## CHECK: symbol
      if cancel
        @parent.handle_request(:GET, :notify_event,
                               'OnUserInputCancel', '', 'cancel')
      elsif timeout and \
        not @parent.handle_request(:GET, :notify_event,
                                   'OnUserInputCancel', '', 'timeout').nil?
        # pass
      elsif @symbol == 'OnUserInput' and \
            not @parent.handle_request(:GET, :notify_event, 'OnUserInput', data).nil?
        # pass
      elsif not @parent.handle_request(:GET, :notify_event, @symbol, data).nil?
        # pass
      elsif not @parent.handle_request(:GET, :notify_event,
                                       'OnUserInput', @symbol, data).nil?
        # pass
      end
      @symbol = nil
      @parent.handle_request(:GET, :reset_user_interaction)
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

  class ScriptInputBox < CommunicateWindow

    NAME = 'scriptbox'
    ENTRY = 'ScriptInput'

    def new_(desc, balloon)
      super
    end

    def show
      super(:default => '')
    end

    def cancel
      @parent.handle_request(:GET, :reset_user_interaction)
    end

    def enter
      send(@entry.text)
    end

    def send(data)
      return if data.nil? or data.empty?
      @parent.handle_request(:GET, :reset_script, reset_all: true)
      @parent.handle_request(:GET, :stand_by, false)
      @parent.handle_request(:GET, :start_script, data)
      @parent.handle_request(:GET, :reset_user_interaction)
    end
  end
end
