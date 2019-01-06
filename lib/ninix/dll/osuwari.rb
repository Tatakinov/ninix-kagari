# -*- coding: utf-8 -*-
#
#  osuwari.rb - a Osuwari compatible Saori module for ninix
#  Copyright (C) 2006-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#
#

# TODO: MOVE, NOCLIP, FIX, etc.

require "gtk3"

require_relative "../dll"
require_relative "../pix"


module Osuwari

  class Saori < DLL::SAORI

    def initialize
      super()
      @timeout_id = nil
      @settings = {}
      @__sakura = nil
    end

    def need_ghost_backdoor(sakura)
      @__sakura = sakura
    end

    def check_import
      if not @__sakura.nil?
        return 1
      else
        return 0
      end
    end

    def setup
      return 1
    end

    def execute(argument)
      return RESPONSE[400] if argument.nil? or argument.empty?
      if argument[0] == 'START'
        return RESPONSE[400] if argument.length < 7
        begin ## FIXME
          fail "assert" unless ['ACTIVE', 'FIX'].include?(argument[2]) or 
            argument[2].start_with?('@') or 
            argument[2].start_with?('#')
          fail "assert" unless ['TL', 'TR', 'BL', 'BR'].include?(argument[3])
          @settings['hwnd'] = argument[1]
          @settings['target'] = argument[2]
          @settings['position'] = argument[3]
          @settings['offset_x'] = Integer(argument[4])
          @settings['offset_y'] = Integer(argument[5])
          @settings['timeout'] = Integer(argument[6])
          @settings['xmove'] = 0
          @settings['ymove'] = 0
          @settings['noclip'] = 0
          if argument.length > 7
            if argument[7].include?('XMOVE')
              @settings['xmove'] = 1
            end
            if argument[7].include?('YMOVE')
              @settings['ymove'] = 1
            end
            if argument[7].include?('NOCLIP')
              @settings['noclip'] = 1
            end
          end
          @settings['except'] = ['DESKTOP', 'CENTER']
          if argument.length > 8
            #target, position = argument[8].split() # spec
            position, target = argument[8].split(nil, 2) # real world
            fail "assert" unless ['DESKTOP', 'WORKAREA'].include?(target)
            fail "assert" unless ['TOP', 'LEFT', 'RIGHT', 'BOTTOM'].include?(position)
            @settings['except'] = [target, position]
          end
        rescue
          return RESPONSE[400]
        end
        #@timeout_id = GLib::Timeout.add(@settings['timeout']) { do_idle_tasks }
        @timeout_id = GLib::Timeout.add(100) { do_idle_tasks }
        return RESPONSE[204]
      elsif argument[0] == 'STOP'
        GLib::Source.remove(@timeout_id) unless @timeout_id.nil?
        @timeout_id = nil
        @settings = {}
        return RESPONSE[204]
      else
        return RESPONSE[400]
      end
    end

    def do_idle_tasks
      return false if @timeout_id.nil?
      target = @settings['target']
      left, top, scrn_w, scrn_h = @__sakura.get_workarea
      target_flag = [false, false]
      if target == 'ACTIVE'
        active_window = get_active_window()
        unless active_window.nil?
          if @__sakura.identify_window(active_window)
            target_flag[1] = true
          else
            rect = active_window.frame_extents
            target_x = rect.x
            target_y = rect.y
            target_w = rect.width
            target_h = rect.height
            target_flag[0] = true
          end
        else
          target_flag[1] = true
        end
      elsif target == 'FIX' ## FIXME
        target_x = left
        target_y = top
        target_w = scrn_w
        target_h = scrn_h
        target_flag[0] = true
      elsif target.start_with?('@') ## FIXME
        #win = get_window_by_name(target[1..-1])
        #if @__sakura.identify_window(win)
        #  return true
        #end
        #target_x, target_y = active_window.root_origin
        #rect = active_window.frame_extents
        #target_w = rect.width
        #target_h = rect.height
        #pass
      elsif target.start_with?('#') ## FIXME
        #pass
      else
        #pass # should not reach here
      end
      return target_flag[1] unless target_flag[0]
      pos = @settings['position']
      scale = @__sakura.get_surface_scale()
      offset_x = (@settings['offset_x'] * scale / 100).to_i
      offset_y = (@settings['offset_y'] * scale / 100).to_i
      if @settings['hwnd'].start_with?('s')
        begin
          side = Integer(@settings['hwnd'][1..-1])
        rescue
          return false
      end
      else
        begin
          side = Integer(@settings['hwnd'])
        rescue
          return false
        end
      end
      w, h = @__sakura.get_surface_size(side)
      case pos[0]
      when 'T'
        y = (target_y + offset_y)
      when 'B'
        y = (target_y + target_h + offset_y - h)
      else
        return false # should not reach here
      end
      case pos[1]
      when 'L'
        x = (target_x + offset_x)
      when 'R'
        x = (target_x + target_w + offset_x - w)
      else
        return false # should not reach here
      end
      if not @settings['noclip']
        if x < left or x > left+ scrn_w or \
          y < top or y > top + scrn_h
          case @settings['except'][1]
          when 'BOTTOM'
            #pass ## FIXME: not supported yet
          when 'TOP'
            #pass ## FIXME: not supported yet
          when 'LEFT'
            #pass ## FIXME: not supported yet
          when 'RIGTH'
            #pass ## FIXME: not supported yet
          when 'CENTER'
            #pass ## FIXME: not supported yet
          else
            #pass # should not reach here
          end
        end
      end
      @__sakura.set_surface_position(side, x, y)
      @__sakura.raise_surface(side)
      return true
    end

    def get_window_by_name(name) ## FIXME: not supported yet
      return nil
    end

    def get_active_window
      scrn = Gdk::Screen.default
      active_window = scrn.active_window
      return active_window
    end
  end
end
