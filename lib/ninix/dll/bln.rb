# -*- coding: utf-8 -*-
#
#  bln.rb - a easyballoon compatible Saori module for ninix
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# - font.face

require "gtk3"

require_relative "../pix"
require_relative "../script"
require_relative "../dll"


module Bln

  class Saori< DLL::SAORI

    def initialize
      super()
      @blns = {}
      @__sakura = nil
    end

    def need_ghost_backdoor(sakura)
      @__sakura = sakura
    end

    def check_import
      if @__sakura
        return 1
      else
        return 0
      end
    end

    def setup
      @blns = read_bln_txt(@dir)
      if not @blns.empty?
        @__sakura.attach_observer(self)
        return 1
      else
        return 0
      end
    end

    def read_bln_txt(dir)
      blns = {}
      begin
        open(File.join(dir, 'bln.txt'), 'r', :encoding => 'CP932') do |f|
          data = {}
          name = ''
          for line in f
            line = line.strip()
            if line.empty?
              next
            end
            if line.start_with?('//')
              next
            end
            if line.include?('[')
              if not name.empty?
                blns[name] = [data, {}]
              end
              data = {}
              start = line.index('[')
              end_ = line.index(']')
              if end_ < 0
                end_ = line.length
              end
              name = line[start + 1..end_-1]
            else
              if line.include?(',')
                key, value = line.split(',', 2)
                key.strip!
                value.strip!
                data[key] = value
              end
            end
          end
          if not name.empty?
            blns[name] = [data, {}]
          end
          return blns
        end
      rescue
        return {}
      end
    end

    def finalize
      for name in @blns.keys
        data, bln = @blns[name]
        for bln_id in bln.keys
          if bln[bln_id]
            bln[bln_id].destroy()
            bln.delete(bln_id)
          end
        end
      end
      @blns = {}
      @__sakura.detach_observer(self)
      return 1
    end

    def observer_update(event, args) ## FIXME
      if event == 'set scale'
        for name in @blns.keys
          data, bln = @blns[name]
          for bln_id in bln.keys
            if bln[bln_id]
              bln[bln_id].reset_scale()
            end
          end
        end
      end
    end

    def execute(argument)
      if not argument or argument.empty?
        return RESPONSE[400]
      end
      name = argument[0]
      if argument.length >= 2
        text = argument[1]
      else
        text = ''
      end
      if argument.length >= 3
        begin
          offset_x = argument[2].to_i
        rescue
          offset_x = 0
        end
      else
        offset_x = 0
      end
      if argument.length >= 4
        begin
          offset_y = argument[3].to_i
        rescue
          offset_y = 0
        end
      else
        offset_y = 0
      end
      if argument.length >= 5
        bln_id = argument[4]
      else
        bln_id = ''
      end
      if argument.length >= 6 and ['1', '2'].include?(argument[5])
        update = argument[5].to_i
      else
        update = 0
      end
      if @blns.include?(name)
        data, bln = @blns[name]
        if bln.include?(bln_id) and update == 0
          bln[bln_id].destroy()
          bln.delete(bln_id)
        end
        if not text.empty?
          if update == 0 or not bln.include?(bln_id)
            bln[bln_id] = Balloon.new(@__sakura, @dir,
                                      data, text,
                                      offset_x, offset_y, name, bln_id)
          else
            bln[bln_id].update_script(text, update)
          end
        end
        @blns[name] = [data, bln]
      elsif name == 'clear'
        for name in @blns.keys
          data, bln = @blns[name]
          new_bln = {}
          for bln_id in bln.keys
            if bln[bln_id].get_state() == 'orusuban'
              new_bln[bln_id] = bln[bln_id]
              next
            end
            bln[bln_id].destroy()
          end
          @blns[name] = [data, new_bln]
        end
      end
      return nil
    end
  end


  class Balloon

    def initialize(sakura, dir, data,
                   text, offset_x, offset_y, name, bln_id)
      @dir = dir
      @__sakura = sakura
      @name = name
      @id = bln_id
      @timeout_id = nil
      @data = data # XXX
      @window = Pix::TransparentWindow.new()
      @window.set_title(name)
      @window.set_skip_taskbar_hint(true)
      @window.signal_connect('delete_event') do |w, e|
        delete(w, e)
      end
      if data.include?('position')
        @position = data['position']
      else
        @position = 'sakura'
      end
      left, top, scrn_w, scrn_h = Pix.get_workarea()
      # -1: left, 1: right
      if @position == 'sakura'
        s0_x, s0_y, s0_w, s0_h = get_sakura_status('SurfaceSakura')
        if s0_x + (s0_w / 2).to_i > left + (scrn_w / 2).to_i
          @direction = -1
        else
          @direction = 1
        end
      elsif @position == 'kero'
        s1_x, s1_y, s1_w, s1_h = get_sakura_status('SurfaceKero')
        if s1_x + (s1_w / 2).to_i > left + (scrn_w / 2).to_i
          @direction = -1
        else
          @direction = 1
        end
      else
        @direction = 1 # XXX
      end
      if ['sakura', 'kero'].include?(@position)
        default = data['skin']
        if @direction == -1
          if data.include?('skin.left')
            skin = data['skin.left']
          else
            skin = default
          end
        else
          if data.include?('skin.right')
            skin = data['skin.right']
          else
            skin = default
          end
        end
      else
        skin = data['skin']
      end
      if skin == nil
        destroy()
        return
      end
      path = File.join(@dir, skin.gsub("\\", '/'))
      begin
        balloon_surface = Pix.create_surface_from_file(path)
      rescue
        destroy()
        return
      end
      @balloon_surface = balloon_surface
      w = balloon_surface.width
      h = balloon_surface.height
      @x = @y = 0
      if data.include?('offset.x')
        @x += @direction * data['offset.x'].to_i
      end
      if data.include?('offset.y')
        @y += data['offset.y'].to_i
      end
      if data.include?('offset.random')
        @x += data['offset.random'].to_i * Random.rand(-1.0..2.0)
        @y += data['offset.random'].to_i * Random.rand(-1.0..2.0)
      end
      @x += @direction * offset_x.to_i
      @y += offset_y.to_i
      @action_x = 0
      @action_y = 0
      @vx = 0
      @vy = 0
      if data.include?('disparea.left')
        @left = data['disparea.left'].to_i
      else
        @left = 0
      end
      if data.include?('disparea.right')
        @right = data['disparea.right'].to_i
      else
        @right = w.to_i
      end
      if data.include?('disparea.top')
        @top = data['disparea.top'].to_i
      else
        @top = 0
      end
      if data.include?('disparea.bottom')
        @bottom = data['disparea.bottom'].to_i
      else
        @bottom = h.to_i
      end
      @script = nil
      @darea = @window.darea
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK|
                        Gdk::EventMask::BUTTON_PRESS_MASK|
                        Gdk::EventMask::BUTTON_RELEASE_MASK|
                        Gdk::EventMask::POINTER_MOTION_MASK|
                        Gdk::EventMask::LEAVE_NOTIFY_MASK)
      @darea.signal_connect('draw') do |w, e|
        redraw(w, e)
      end
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
      set_skin()
      set_position()
      @layout = nil
      if text != 'noscript' and \
        (@right - @left) > 0 and (@bottom - @top) > 0
        @script = text
        if data.include?('font.color')
          fontcolor_r = data['font.color'][0..1].to_i(16) / 255.0
          fontcolor_g = data['font.color'][2..3].to_i(16) /255.0
          fontcolor_b = data['font.color'][4..5].to_i(16) / 255.0
          @fontcolor = [fontcolor_r, fontcolor_g, fontcolor_b]
        else
          @fontcolor = [0.0, 0.0, 0.0] # XXX
        end
        default_font_size = 12 # for Windows environment
        if data.include?('font.size')
          @font_size = data['font.size'].to_i
        else
          @font_size = default_font_size
        end
        @layout = Pango::Layout.new(@darea.pango_context)
        @font_desc = Pango::FontDescription.new
        @font_desc.set_family('Sans') # FIXME
        if data.include?('font.bold') and data['font.bold'] == 'on'
          @font_desc.set_weight(Pango::WEIGHT_BOLD)
        end
        @layout.set_wrap(Pango::WRAP_CHAR)
        set_layout()
      end
      if data.include?('slide.vx')
        @slide_vx = data['slide.vx'].to_i
      else
        @slide_vx = 0
      end
      if data.include?('slide.vy')
        @slide_vy = data['slide.vy'].to_i
      else
        @slide_vy = 0
      end
      if data.include?('slide.autostop')
        @slide_autostop = data['slide.autostop'].to_i
      else
        @slide_autostop = 0
      end
      if ['sinwave', 'vibrate'].include?(data['action.method'])
        action = data['action.method']
        if data.include?('action.reference0')
          ref0 = data['action.reference0'].to_i
        else
          ref0 = 0
        end
        if data.include?('action.reference1')
          ref1 = data['action.reference1'].to_i
        else
          ref1 = 0
        end
        if data.include?('action.reference2')
          ref2 = data['action.reference2'].to_i
        else
          ref2 = 0
        end
        if data.include?('action.reference3')
          ref3 = data['action.reference3'].to_i
        else
          ref3 = 0
        end
        if ref2 != 0
          @action = {'method' => action,
                     'ref0' => ref0,
                     'ref1' => ref1,
                     'ref2' => ref2,
                     'ref3' => ref3}
        else
          @action = nil
        end
      else
        @action = nil
      end
      @move_notify_time = nil
      @life_time = nil
      @state = ''
      if data.include?('life')
        life = data['life']
      else
        life = 'auto'
      end
      if life == 'auto'
        @life_time = 16000
      elsif ['infinitely', '0'].include?(life)
        #pass
      elsif life == 'orusuban'
        @state = 'orusuban'
      else
        begin
          @life_time = life.to_i
        rescue
          #pass
        end
      end
      @start_time = Time.now
      if data.include?('startdelay')
        @startdelay = data['startdelay'].to_i
      else
        @startdelay = 0
      end
      if data.include?('nooverlap')
        @nooverlap = 1
      else
        @nooverlap = 0
      end
      @talking = get_sakura_is_talking()
      @move_notify_time = Time.new
      @visible = false
      @x_root = nil
      @y_root = nil
      @processed_script = []
      @processed_text = ''
      @text = ''
      @script_wait = nil
      @quick_session = 0
      @script_parser = Script::Parser.new(:error => 'loose')
      begin
        @processed_script = @script_parser.parse(@script)
      rescue Script::ParserError => e
        @processed_script = []
        logging.error('-' * 50)
        logging.error(e.format)
        logging.error(@script.encode('utf-8'))
      end
      @timeout_id = GLib::Timeout.add(10) { do_idle_tasks }
    end

    def set_position
      if @window == nil
        return
      end
      new_x = @base_x + ((@x + @action_x + @vx) * @scale / 100.0).to_i
      new_y = @base_y + ((@y + @action_y + @vy) * @scale / 100.0).to_i
      @window.move(new_x, new_y)
    end

    def set_skin
      if @window == nil
        return
      end
      @scale = get_sakura_status('SurfaceScale') ## FIXME
      w = @balloon_surface.width
      h = @balloon_surface.height
      w = [8, (w * @scale / 100).to_i].max
      h = [8, (h * @scale / 100).to_i].max
      @window.update_size(w, h)
      @base_x, @base_y = get_coordinate(w, h)
    end

    def set_layout
      if @window == nil
        return
      end
      if @layout == nil
        return
      end
      font_size = (@font_size * 3 / 4).to_i # convert from Windows to GTK+
      font_size = font_size * Pango::SCALE
      @font_desc.set_size(font_size)
      @layout.set_font_description(@font_desc)
      @layout.set_width(((@right - @left) * 1024).to_i)
    end

    def reset_scale
      if @window == nil
        return
      end
      set_skin()
      set_position()
    end

    def clickerase
      return (not @data.include?('clickerase') or @data['clickerase'] == 'on') # default: ON
    end

    def dragmove_horizontal
      return (@data.include?('dragmove.horizontal') and @data['dragmove.horizontal'] == 'on')
    end

    def dragmove_vertical
      return (@data.include?('dragmove.vertical') and @data['dragmove.vertical'] == 'on')
    end

    def get_coordinate(w, h)
      left, top, scrn_w, scrn_h = Pix.get_workarea()
      s0_x, s0_y, s0_w, s0_h = get_sakura_status('SurfaceSakura')
      s1_x, s1_y, s1_w, s1_h = get_sakura_status('SurfaceKero')
      b0_x, b0_y, b0_w, b0_h = get_sakura_status('BalloonSakura')
      b1_x, b1_y, b1_w, b1_h = get_sakura_status('BalloonKero')
      x = left
      y = top
      if @position == 'lefttop'
        #pass
      elsif @position == 'leftbottom'
        y = top + scrn_h - h
      elsif @position == 'righttop'
        x = left + scrn_w - w
      elsif @position == 'rightbottom'
        x = left + scrn_w - w
        y = top + scrn_h - h
      elsif @position == 'center'
        x = left + ((scrn_w - w) / 2).to_i
        y = top + ((scrn_h - h) / 2).to_i
      elsif @position == 'leftcenter'
        y = top + ((scrn_h - h) / 2).to_i
      elsif @position == 'rightcenter'
        x = left + scrn_w - w
        y = top + ((scrn_h - h) / 2).to_i
      elsif @position == 'centertop'
        x = left + ((scrn_w - w) / 2).to_i
      elsif @position == 'centerbottom'
        x = left + ((scrn_w - w) / 2).to_i
        y = top + scrn_h - h
      elsif @position == 'sakura'
        if @direction # right
          x = s0_x + s0_w
        else
          x = s0_x - w
        end
        y = s0_y
      elsif @position == 'kero'
        if @direction # right
          x = s1_x + s1_w
        else
          x = s1_x - w
        end
        y = s1_y
      elsif @position == 'sakurab'
        x = b0_x
        y = b0_y
      elsif @position == 'kerob'
        x = b1_x
        y = b1_y
      end
      return x, y
    end

    def update_script(text, mode)
      if @timeout_id == nil # XXX
        return
      end
      if not text
        return
      end
      if mode == 2 and @script != nil
        @script = [@script, text].join("")
      else
        @script = text
      end
      @processed_script = []
      @processed_text = ''
      @text = ''
      @script_wait = nil
      @quick_session = 0
      begin
        @processed_script = @script_parser.parse(@script)
      rescue Script::ParserError => e
        @processed_script = []
        logging.error('-' * 50)
        logging.error(e.format)
        logging.error(@script.encode('utf-8'))
      end
    end

    def get_sakura_is_talking
      talking = false
      begin
        if @__sakura.is_talking()
          talking = true
        else
          talking = false
        end
      rescue
        #pass
      end
      return talking
    end

    def get_sakura_status(key)
      if key == 'SurfaceScale'
        result = @__sakura.get_surface_scale()
      elsif key == 'SurfaceSakura_Shown'
        if @__sakura.surface_is_shown(0)
          result = true
        else
          result = false
        end
      elsif key == 'SurfaceSakura'
        begin
          s0_x, s0_y = @__sakura.get_surface_position(0)
          s0_w, s0_h = @__sakura.get_surface_size(0)
        rescue
          s0_x, s0_y = 0, 0
          s0_w, s0_h = 0, 0
        end
        result = s0_x, s0_y, s0_w, s0_h
      elsif key == 'SurfaceKero_Shown'
        if @__sakura.surface_is_shown(1)
          result = true
        else
          result = false
        end
      elsif key == 'SurfaceKero'
        begin
          s1_x, s1_y = @__sakura.get_surface_position(1)
          s1_w, s1_h = @__sakura.get_surface_size(1)
        rescue
          s1_x, s1_y = 0, 0
          s1_w, s1_h = 0, 0
        end
        result = s1_x, s1_y, s1_w, s1_h
      elsif key == 'BalloonSakura_Shown'
        if @__sakura.balloon_is_shown(0)
          result = true
        else
          result = false
        end
      elsif key == 'BalloonSakura'
        begin
          b0_x, b0_y = @__sakura.get_balloon_position(0)
          b0_w, b0_h = @__sakura.get_balloon_size(0)
        rescue
          b0_x, b0_y = 0, 0
          b0_w, b0_h = 0, 0
        end
        result = b0_x, b0_y, b0_w, b0_h
      elsif key == 'BalloonKero_Shown'
        if @__sakura.balloon_is_shown(1)
          result = true
        else
          result = false
        end
      elsif key == 'BalloonKero'
        begin
          b1_x, b1_y = @__sakura.get_balloon_position(1)
          b1_w, b1_h = @__sakura.get_balloon_size(1)
        rescue
          b1_x, b1_y = 0, 0
          b1_w, b1_h = 0, 0
        end
        result = b1_x, b1_y, b1_w, b1_h
      else
        result = nil
      end
      return result
    end

    def do_idle_tasks
      if not @window
        return nil
      end
      s0_shown = get_sakura_status('SurfaceSakura_Shown')
      s1_shown = get_sakura_status('SurfaceKero_Shown')
      b0_shown = get_sakura_status('BalloonSakura_Shown')
      b1_shown = get_sakura_status('BalloonKero_Shown')
      sakura_talking = get_sakura_is_talking()
      if @state == 'orusuban'
        if @visible
          if s0_shown or s1_shown
            destroy()
            return nil
          end
        else
          if not s0_shown and not s1_shown
            @start_time = Time.now
            @visible = true
            @window.show()
            @life_time = 300000
          end
        end
      else
        if @visible
          if (@position == 'sakura' and not s0_shown) or \
            (@position == 'kero' and not s1_shown) or \
            (@position == 'sakurab' and not b0_shown) or \
            (@position == 'kerob' and not b1_shown) or \
            (@nooverlap and not @talking and sakura_talking)
            destroy()
            return nil
          end
        else
          if Time.now - @start_time >= @startdelay * 0.001
            @start_time = Time.now
            @visible = true
            @window.show()
          end
        end
      end
      if @visible
        if @life_time
          if Time.now - @start_time >= @life_time * 0.001 and \
            not (not @processed_script.empty? or not @processed_text.empty?)
            destroy()
            return nil
          end
        end
        if @action
          if  @action['method'] == 'sinwave'
            offset = @action['ref1'] \
                     * Math.sin(2.0 * Math::PI \
                                * (((Time.now - \
                                     @start_time) * 1000).to_i \
                                   % @action['ref2']).to_f / @action['ref2'])
            if @action['ref0']
              @action_y = offset.to_i
            else
              @action_x = offset.to_i
            end
          elsif @action['method'] == 'vibrate'
            offset = (((Time.now - @start_time) * 1000).to_i / \
                      @action['ref2']).to_i % 2
            @action_x = (offset * @action['ref0']).to_i
            @action_y = (offset * @action['ref1']).to_i
          end
        end
        if (@slide_vx != 0 or @slide_vy != 0) and \
          @slide_autostop > 0 and \
          @slide_autostop * 0.001 + 0.05 <= Time.now - @start_time
          @vx = @direction * ((@slide_autostop / 50.0 + 1) * @slide_vx).to_i
          @slide_vx = 0
          @vy = ((@slide_autostop / 50.0 + 1) * @slide_vy).to_i
          @slide_vy = 0
        end
        if @slide_vx != 0
          @vx = @direction * (((Time.now - @start_time) * @slide_vx) / 50 * 1000.-).to_i
        end
        if @slide_vy != 0
          @vy = (((Time.now - @start_time) * @slide_vy) / 50 * 1000.0).to_i
        end
        set_position()
        if not @processed_script.empty? or not @processed_text.empty?
          interpret_script()
        end
      end
      if @talking and not sakura_talking
        @talking = false
      else
        @talking = sakura_talking
      end
      return true
    end

    def redraw(widget, cr)
      scale = @scale
      cr.scale(scale / 100.0, scale / 100.0)
      cr.set_source(@balloon_surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint()
      cr.set_operator(Cairo::OPERATOR_OVER) # restore default
      if @layout
        cr.set_source_rgb(*@fontcolor)
        cr.move_to(@left.to_i, @top.to_i)
        cr.show_pango_layout(@layout)
      end
    end

    def get_state
      return @state
    end

    def interpret_script
      if @script_wait != nil
        if Time.now < @script_wait
          return
        end
        @script_wait = nil
      end
      if not @processed_text.empty?
        if @quick_session or @state == 'orusuban'
          @text = [@text, @processed_text].join("")
          draw_text(@text)
          @processed_text = ''
        else
          @text = [@text, @processed_text[0]].join("")
          draw_text(@text)
          @processed_text = @processed_text[1..-1]
          @script_wait = Time.now + 0.014
        end
        return
      end
      node = @processed_script.shift
      if node[0] == Script::SCRIPT_TAG
        name, args = node[1], node[2..-1]
        if name == '\n'
          @text = [@text, "\n"].join("")
          draw_text(@text)
        elsif name == '\w'
          if args
            begin
              amount = args[0].to_i * 0.05 - 0.01
            rescue
              amount = 0
            end
          else
            amount = 1 * 0.05 - 0.01
          end
          if amount > 0
            @script_wait = Time.now + amount
          end
        elsif name == '\b'
          if args
            begin
              amount = args[0].to_i
            rescue
              amount = 0
            end
          else
            amount = 1
          end
          if amount > 0
            @text = @text[0..-amount-1]
          end
        elsif name == '\c'
          @text = ''
        elsif name == '\_q'
          @quick_session = (not @quick_session)
        elsif name == '\l'
          @life_time = nil
          update_script('', 2)
        end
      elsif node[0] == Script::SCRIPT_TEXT
        text = ''
        for chunk in node[1]
          text = [text, chunk[1]].join("")
        end
        @processed_text = text
      end
    end

    def draw_text(text)
      @layout.set_text(text)
      @darea.queue_draw()
    end

    def button_press(widget, event)
      @x_root = event.x_root
      @y_root = event.y_root
      if event.event_type == Gdk::EventType::DOUBLE_BUTTON_PRESS
        x, y = @window.winpos_to_surfacepos(
             event.x.to_i, event.y.to_i, @scale)
        @__sakura.notify_event(
          'OnEBMouseDoubleClick', @name, x, y, @id)
      end
      return true
    end

    def button_release(widget, event)
      @x_root = nil
      @y_root = nil
      x, y = @window.winpos_to_surfacepos(
           event.x.to_i, event.y.to_i, @scale)
      if event.event_type == Gdk::EventType::BUTTON_RELEASE
        if event.button == 1
          @__sakura.notify_event(
            'OnEBMouseClick', @name, x, y, @id, 0)
        elsif event.button == 3
          @__sakura.notify_event(
            'OnEBMouseClick', @name, x, y, @id, 1)
        end
      end
      if @clickerase
        destroy()
      end
      return true
    end

    def motion_notify(widget, event)
      if @x_root != nil and \
         @y_root != nil
        x_delta = (event.x_root - @x_root).to_i
        y_delta = (event.y_root - @y_root).to_i
        if event.state & Gdk::ModifierType::BUTTON1_MASK
          if @dragmove_horizontal
            @x += x_delta
          end
          if @dragmove_vertical
            @y += y_delta
          end
          set_position()
          @x_root = event.x_root
          @y_root = event.y_root
        end
      end
      if @move_notify_time == nil or \
         Time.now - @move_notify_time > 500 * 0.001
        x, y = @window.winpos_to_surfacepos(
             event.x.to_i, event.y.to_i, @scale)
        @__sakura.notify_event(
          'OnEBMouseMove', @name, x, y, @id)
        @move_notify_time = Time.now
      end
      return true
    end

    def leave_notify(widget, event)
      @move_notify_time = nil
    end

    def delete(window, event)
      return true
    end

    def destroy
      @visible = false
      if @window
        @window.destroy()
        @window = nil
      end
      if @timeout_id
        GLib::Source.remove(@timeout_id)
        @timeout_id = nil
      end
    end
  end
end
