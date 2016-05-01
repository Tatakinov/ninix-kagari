# -*- coding: utf-8 -*-
#
#  hanayu.rb - a "花柚" compatible Saori module for ninix
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# - usetime, line, radar 以外の形式のグラフへの対応.


require "gtk3"

require_relative "../pix"
require_relative "../dll"
require_relative "../logging"


module Hanayu

  class Saori < DLL::SAORI

    DBNAME = 'HANAYU.db'

    def initialize
      super()
      @graphs = {}
      @data = {}
    end

    def setup
      @dbpath = File.join(@dir, DBNAME)
      @graphs = {}
      @data = read_hanayu_txt(@dir)
      if @data != nil and not @data.empty?
        read_db()
        return 1
      else
        return 0
      end
    end

    def read_hanayu_txt(dir)
      graphs = {}
      begin
        open(File.join(dir, 'hanayu.txt'), 'r', :encoding => 'CP932') do |f|
          data = {}
          name = ''
          tmp_name = ''
          for line in f
            line = line.encode('UTF-8', :invalid => :replace, :undef => :replace).strip()
            if line.empty?
              next
            end
            if line.start_with?('//')
              next
            end
            if line.start_with?('[') # bln.txt like format
              graphs[name] = data
              data = {}
              end_ = line.find(']')
              if end_ < 0
                end_ = line.length
                name = line[1..end_-1]
              end
            elsif line == '{' # surfaces.txt like format
              graphs[name] = data
              data = {}
              name = tmp_name ## FIXME
            elsif line == '}' # surfaces.txt like format
              graphs[name] = data
              data = {}
              name = ''
            elsif line.include?(',')
              key, value = line.split(',', 2)
              key.strip!
              value.strip!
              data[key] = value
            elsif not name
              tmp_name = line
            end
          end
          if not data.empty?
            graphs[name] = data
          end
          return graphs
        end
      rescue
        return nil
      end
    end

    def finalize
      for name in @graphs.keys()
        @graphs[name].destroy()
      end
      @graphs = {}
      @data = {}
      write_db()
      return 1
    end

    def time_to_key(base, offset)
      year = base.year
      month = base.month
      day = base.day
      target_time = (Time.new(year, month, day, 0, 0, 0) + offset * 24 *60 * 60)
      year = target_time.year
      month = target_time.month
      day = target_time.day
      key = (year * 10000 + month * 100 + day).to_s
      return key, year, month, day
    end

    def read_db
      @seven_days = []
      current_time = @last_update = Time.now
      for index_ in -6..0
        key, year, month, day = time_to_key(current_time, index_)
        @seven_days << [key, year, month, day, 0.0]
      end
      begin
        open(@dbpath) do |f|
          ver = nil
          for line in f
            line = line.strip()
            if line.empty?
              next
            end
            if ver == nil
              if line == '# Format: v1.0'
                ver = 1
              end
              next
            end
            if not line.include?(',')
              next
            end
            key, value = line.split(',', 2)
            for index_ in 0..6
              if @seven_days[index_][0] == key
                @seven_days[index_][4] = Float(value)
              end
            end
          end
        end
      rescue
        return
      end
    end

    def update_db
      current_time = Time.now
      old_seven_days = []
      old_seven_days.concat(@seven_days)
      @seven_days = []
      for index_ in -6..0
        key, year, month, day = time_to_key(current_time, index_)
        @seven_days << [key, year, month, day, 0.0]
      end
      for i in 0..6
        key = old_seven_days[i][0]
        for j in 0..6
          if @seven_days[j][0] == key
            @seven_days[j][4] = old_seven_days[i][4]
            if j == 6
              @seven_days[j][4] = (@seven_days[j][4] + \
                                   (current_time - \
                                    @last_update) / \
                                   (60.0 * 60.0))
            end
          end
        end
      end
      @last_update = current_time
    end

    def write_db
      update_db()
      begin
        open(@dbpath, 'w') do |f|
          f.write("# Format: v1.0\n")
          for index_ in 0..6
            f.write(@seven_days[index_][0].to_s + ", " + @seven_days[index_][4].to_s + "\n")
          end
        end
      rescue # IOError, SystemCallError
        Logging::Logging.error('HANAYU: cannot write database (ignored)')
      end
    end

    def execute(argument)
      if argument == nil or argument.empty?
        return RESPONSE[400]
      end
      command = argument[0]
      if command == 'show'
        if argument.length >= 2
          name = argument[1]
          if @graphs.include?(name)
            @graphs[name].destroy()
          end
        else
          name = ''
        end
        if not @data.include?(name)
          return RESPONSE[400]
        end
        if @data[name].include?('graph') and \
           ['line', 'bar', 'radar', 'radar2'].include?(@data[name]['graph'])
          graph_type = @data[name]['graph']
        else
          graph_type = 'usetime'
        end
        if graph_type == 'usetime'
          update_db()
          new_args = []
          for index_ in 0..6
            date = [@seven_days[index_][2].to_s,
                    '/',
                    @seven_days[index_][3].to_s].join("")
            new_args << date
            hours = @seven_days[index_][4]
            new_args << hours
          end
          @graphs[name] = Line.new(
            @dir, @data[name], :args => new_args, :limit_min => 0, :limit_max => 24)
        elsif graph_type == 'line'
          @graphs[name] = Line.new(
            @dir, @data[name], :args => argument[2..-1])
        elsif graph_type == 'bar'
          @graphs[name] = Bar.new(
            @dir, @data[name], :args => argument[2..-1])
        elsif graph_type == 'radar'
          @graphs[name] = Radar.new(
            @dir, @data[name], :args => argument[2..-1])
        elsif graph_type == 'radar2'
          @graphs[name] = Radar2.new(
            @dir, @data[name], :args => argument[2..-1])
        end
      elsif command == 'hide'
        if argument.length >= 2
          name = argument[1]
        else
          name = ''
        end
        if @graphs.include?(name)
          @graphs[name].destroy()
        else
          return RESPONSE[400]
        end
      else
        return RESPONSE[400]
      end
      return RESPONSE[204]
    end
  end


  class Graph

    WIDTH = 450
    HEIGHT = 340

    def initialize(dir, data, args: [], limit_min: nil, limit_max: nil)
      @dir = dir
      @data = data
      @args = args
      @min = limit_min
      @max = limit_max
      create_window()
      @window.show()
    end

    def create_window
      @window = Gtk::Window.new
      @window.set_title('花柚') # UTF-8
      @window.set_decorated(false)
      @window.set_resizable(false)
      @window.signal_connect('delete_event') do |w ,e|
        next delete(w, e)
      end
      scrn = Gdk::Screen.default
      left, top = 0, 0 # XXX
      scrn_w = scrn.width - left
      scrn_h = scrn.height - top
      @x = (left + (scrn_w / 2).to_i)
      @y = (top + (scrn_h / 4).to_i)
      @window.move(@x, @y)
      @darea = Gtk::DrawingArea.new
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK|
                        Gdk::EventMask::BUTTON_PRESS_MASK)
      @darea.signal_connect('draw') do |w ,e|
        redraw(w, e)
        next true
      end
      @darea.signal_connect('button_press_event') do |w ,e |
        next button_press(w, e)
      end
      @darea.set_size_request(WIDTH, HEIGHT)
      @darea.show()
      @window.add(@darea)
      @darea.realize()
      @layout = Pango::Layout.new(@darea.pango_context)
      surface = nil
      if @data.include?('background.filename')
        path = File.join(
          @dir, @data['background.filename'].gsub('\\', '/'))
        begin
          surface = Pix.create_surface_from_file(path, is_pnr=0)
        rescue
          surface = nil
        end
        @surface = surface
      end
    end

    def get_color(target)
      fail "assert" unless ['font', 'line', 'frame', 'bar', 'background'].include?(target)
      if target == 'background'
        r = g = b = 255 # white
      else
        r = g = b = 0 # black
      end
      name = [target, '.color'].join("")
      if @data.include?(name)
        r = @data[name][0..1].to_i(16)
        g = @data[name][2..3].to_i(16)
        b = @data[name][4..5].to_i(16)
      else
        name_r = [name, '.r'].join("")
        if @data.include?(name_r)
          r = @data[name_r].to_i
        end
        name_g = [name, '.g'].join("")
        if @data.include?(name_g)
          g = @data[name_g].to_i
        end
        name_b = [name, '.b'].join("")
        if @data.include?(name_b)
          b = @data[name_b].to_i
        end
      end
      return [r / 255.0, g / 255.0, b / 255.0]
    end

    def draw_title(widget, cr)
      if @data.include?('title')
        @title = @data['title']
      end
      font_size = 12 # pixel
      @font_desc = Pango::FontDescription.new
      @font_desc.set_family('Sans')
      @font_desc.set_size(font_size * Pango::SCALE)
      cr.set_source_rgb(*get_color('font'))
      w = widget.allocated_width
      h = widget.allocated_height
      cr.translate(w, 0)
      cr.rotate(Math::PI / 2.0)
      layout = Pango::Layout.new(widget.pango_context)
      layout.set_font_description(@font_desc)
      context = layout.context
      default_gravity = context.base_gravity # XXX
      context.base_gravity = Pango::Gravity::EAST # Vertical Text
      layout.set_text(@title)
      layout.set_wrap(Pango::WRAP_WORD)
      tw, th = layout.pixel_size
      cr.move_to(58, w - 20 - th)
      cr.show_pango_layout(layout)
      context.base_gravity = default_gravity # XXX
    end

    def draw_frame(widget, cr)
      #pass
    end

    def draw_graph(widget, cr)
      #pass
    end

    def redraw(widget, cr)
      cr.save()
      cr.set_source_rgb(*get_color('background'))
      cr.paint()
      if @surface != nil
        width = @surface.width
        height = @surface.height
        xoffset = ((WIDTH - width) / 2).to_i
        yoffset = ((HEIGHT - height) / 2).to_i
        cr.set_source(@surface, xoffset, yoffset)
        cr.set_operator(Cairo::OPERATOR_SOURCE)
        cr.paint()
      end
      cr.restore()
      cr.save()
      draw_title(widget, cr)
      cr.restore()
      cr.save()
      draw_frame(widget, cr)
      cr.restore()
      cr.save()
      draw_graph(widget, cr)
      cr.restore()
    end

    def button_press(window, event)
      if event.event_type == Gdk::EventType::BUTTON_PRESS
        @window.begin_move_drag(
          event.button, event.x_root.to_i, event.y_root.to_i,
          event.time)
      elsif event.event_type == Gdk::EventType::DOUBLE_BUTTON_PRESS # double click
        destroy()
      end
      return true
    end

    def delete(window, event)
      return true
    end

    def destroy
      if @window != nil
        @window.destroy()
        @window = nil
        @timeout_id = nil
      end
    end
  end


  class Line < Graph

    def draw_frame(widget, cr)
      frame_width = 2
      if @data.include?('frame.width')
        frame_width = @data['frame.width'].to_i
      end
      cr.set_line_width(frame_width)
      cr.set_source_rgb(*get_color('frame'))
      cr.move_to(60, 48)
      cr.line_to(60, 260)
      cr.line_to(420, 260)
      cr.stroke()
    end

    def draw_graph(widget, cr)
      cr.set_source_rgb(*get_color('font'))
      num = (@args.length / 2).to_i
      step = (368 / num).to_i
      for index_ in 0..num-1
        @layout.set_text(@args[index_ * 2])
        w, h = @layout.pixel_size
        pos_x = (60 + index_ * step + (step / 2).to_i - (w / 2).to_i)
        pos_y = 268
        cr.move_to(pos_x, pos_y)
        cr.show_pango_layout(@layout)
      end
      if @min != nil
        limit_min = @min
      else
        limit_min = @args[1]
        for index_ in 2..num-1
          if @args[index_ * 2] < limit_min
            limit_min = @args[index_ * 2]
          end
        end
      end
      if @max != nil
        limit_max = @max
      else
        limit_max = @args[1]
        for index_ in 2..num-1
          if @args[index_ * 2] > limit_max
            limit_max = @args[index_ * 2]
          end
        end
      end
      line_width = 2
      if @data.include?('line.width')
        line_width = @data['line.width'].to_i
      end
      cr.set_line_width(line_width)
      cr.set_source_rgb(*get_color('line'))
      for index_ in 1..num-1
        src_x = (60 + (index_ - 1) * step + (step / 2).to_i)
        src_y = (220 - (
          168 * @args[(index_ - 1) * 2 + 1] / (limit_max - limit_min)).to_i)
        dst_x = (60 + index_ * step + (step / 2).to_i)
        dst_y = (220 - (168 * @args[index_ * 2 + 1] / (limit_max - limit_min)).to_i)
        cr.move_to(src_x, src_y)
        cr.line_to(dst_x, dst_y)
        cr.stroke()
      end
      for index_ in 0..num-1
        surface = nil
        if @args[index_ * 2 + 1] == limit_min and \
           @data.include?('mark0.filename')
          path = File.join(
            @dir, @data['mark0.filename'].gsub('\\', '/'))
          if File.exist?(path)
            begin
              surface = Pix.create_surface_from_file(path)
            rescue
              surface = nil
            end
          end
        elsif @args[index_ * 2 + 1] == limit_max and \
              @data.include?('mark2.filename')
          path = File.join(
            @dir, @data['mark2.filename'].gsub('\\', '/'))
          if File.exist?(path)
            begin
              surface = Pix.create_surface_from_file(path)
            rescue
              surface = nil
            end
          end
        elsif @data.include?('mark1.filename')
          path = File.join(
            @dir, @data['mark1.filename'].gsub('\\', '/'))
          if File.exist?(path)
            begin
              surface = Pix.create_surface_from_file(path)
            rescue
              surface = nil
            end
          end
        end
        if surface != nil
          w = surface.width
          h = surface.height
          x = (60 + index_ * step + (step / 2).to_i - (w / 2).to_i)
          y = (220 - (
            168 * @args[index_ * 2 + 1] / (limit_max - limit_min)).to_i - (h / 2).to_i)
          cr.set_source(surface, x, y)
          cr.paint()
        end
      end
    end
  end


  class Bar < Graph

    def draw_frame(widget, cr)
      frame_width = 2
      if @data.include?('frame.width')
        frame_width = @data['frame.width'].to_i
      end
      cr.set_line_width(frame_width)
      cr.set_source_rgb(*get_color('frame'))
      cr.move_to(60, 48)
      cr.line_to(60, 260)
      cr.line_to(420, 260)
      cr.stroke()
    end

    def draw_graph(widget, cr) ## FIXME
      cr.set_source_rgb(*get_color('bar'))
      bar_with = 20 ## FIXME
      if @data.include?('bar.width')
        bar_width = @data['bar.width'].to_i
      end
      ### NOT YET ###
    end
  end


  class Radar < Graph

    WIDTH = 288
    HEIGHT = 288

    def initialize(dir, data, args: [])
      super(dir, data, args)
    end

    def draw_frame(widget, cr)
      frame_width = 2
      if @data.include?('frame.width')
        frame_width = @data['frame.width'].to_i
      end
      cr.set_line_width(frame_width)
      cr.set_source_rgb(*get_color('frame'))
      num = (@args.length / 2).to_i
      for index_ in 0..num-1
        x = (146 + (Math.cos(Math::PI * (0.5 - 2.0 * index_ / num)) * 114).to_i)
        y = (146 - (Math.sin(Math::PI * (0.5 - 2.0 * index_ / num)) * 114).to_i)
        cr.move_to(146, 146,)
        cr.line_to(x, y)
        cr.stroke()
      end
    end

    def draw_graph(widget, cr)
      num = (@args.length / 2).to_i
      for index_ in 0..num-1
        begin
          value = @args[index_ * 2 + 1]
          @args[index_ * 2 + 1] = Float(value)
        rescue
          @args[index_ * 2 + 1] = 0.0
        end
        if @args[index_ * 2 + 1] < 0
          @args[index_ * 2 + 1] = 0.0
        end
      end
      limit_min = @args[1]
      for index_ in 0..num-1
        if @args[index_ * 2 + 1] < limit_min
          limit_min = @args[index_ * 2 + 1]
        end
      end
      limit_max = @args[1]
      for index_ in 0..num-1
        if @args[index_ * 2 + 1] > limit_max
          limit_max = @args[index_ * 2 + 1]
        end
      end
      line_width = 2
      if @data.include?('line.width')
        line_width = @data['line.width'].to_i
      end
      cr.set_line_width(line_width)
      cr.set_source_rgb(*get_color('line'))
      if limit_max > 0
        value = (@args[(num - 1) * 2 + 1] / limit_max)
      else
        value = 1.0
      end
      src_x = (146 + (Math.cos(
                       Math::PI * (0.5 - 2.0 * (num - 1) / num)) * value * 100).to_i)
      src_y = (146 - (Math.sin(
                       Math::PI * (0.5 - 2.0 * (num - 1) / num)) * value * 100).to_i)
      cr.move_to(src_x, src_y)
      for index_ in 0..num-1
        if limit_max > 0
          value = (@args[index_ * 2 + 1] / limit_max)
        else
          value = 1.0
        end
        dst_x = (146 + (
          Math.cos(Math::PI * (0.5 - 2.0 * index_ / num)) * value * 100).to_i)
        dst_y = (146 - (
          Math.sin(Math::PI * (0.5 - 2.0 * index_ / num)) * value * 100).to_i)
        cr.line_to(dst_x, dst_y)
      end
      cr.stroke()
      font_size = 9 # pixel
      @font_desc.set_size(font_size * Pango::SCALE)
      @layout.set_font_description(@font_desc)
      cr.set_source_rgb(*get_color('font'))
      for index_ in 0..num-1
        ##if limit_max > 0
        ##  value = (@args[index_ * 2 + 1] / limit_max)
        ##else
        ##  value = 1.0
        ##end
        value = 1.2 # XXX
        x = (146 + (Math.cos(
                    Math::PI * (0.5 - 2.0 * index_ / num)) * value * 100).to_i)
        y = (146 - (Math.sin(
                    Math::PI * (0.5 - 2.0 * index_ / num)) * value * 100).to_i)
        @layout.set_text(@args[index_ * 2])
        w, h = @layout.pixel_size
        x -= (w / 2).to_i
        y -= (h / 2).to_i
        cr.move_to(x, y)
        cr.show_pango_layout(@layout)
      end
    end
  end


  class Radar2 < Graph

    WIDTH = 288
    HEIGHT = 288

    def initialize(dir, data, args: [])
      super(dir, data, args)
    end
  end
end
