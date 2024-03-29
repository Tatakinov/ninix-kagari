# -*- coding: utf-8 -*-
#
#  wmove.rb - a wmove.dll compatible Saori module for ninix
#  Copyright (C) 2003-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# - STANDBY, STANDBY_INSIDE


require "gtk3"

require_relative "../dll"
require_relative "../pix"


module Wmove

  class Saori < DLL::SAORI

    def initialize
      super()
      @__sakura = nil
    end

    def need_ghost_backdoor(sakura)
      @__sakura = sakura
    end

    def load(dir: nil)
      @commands = [[], []]
      @timeout_id = nil
      @dir = dir
      result = 0
      if @__sakura.nil?
        #pass
      elsif @loaded == 1
        result = 2
      else
        @sakura_name = @__sakura.get_selfname()
        @kero_name = @__sakura.get_keroname()
        @loaded = 1
        result = 1
      end
      return result
    end

    def finalize
      GLib::Source.remove(@timeout_id) unless @timeout_id.nil?
      @timeout_id = nil
      @commands = [[], []]
      @sakura_name = ''
      @kero_name = ''
      return 1
    end

    def __check_argument(argument)
      name = argument[0]
      result = true
      list_hwnd = [@sakura_name, @kero_name] ## FIXME: HWND support
      case name
      when 'MOVE', 'MOVE_INSIDE', 'MOVETO', 'MOVETO_INSIDE'
        if argument.length != 4 or not list_hwnd.include?(argument[1])
          result = false
        end
      when 'ZMOVE', 'WAIT'
        if argument.length != 3 or not list_hwnd.include?(argument[1])
          result = false
        end
      when 'STANDBY', 'STANDBY_INSIDE'
        if argument.length != 6 or \
          not list_hwnd.include?(argument[1]) or \
          not list_hwnd.include?(argument[2])
          result = false
        end
      when 'GET_POSITION', 'CLEAR'
        if argument.length != 2 or not list_hwnd.include?(argument[1])
          result = false
        end
      when 'GET_DESKTOP_SIZE'
        if argument.length != 1
          result = false
        end
      when 'NOTIFY'
        if argument.length < 3 or argument.length > 8 or \
          not list_hwnd.include?(argument[1])
          result = false
        end
      end
      return result
    end

    def request(req)
      req_type, argument = evaluate_request(req)
      result =
        case req_type
        when nil
          RESPONSE[400]
        when 'GET Version'
          RESPONSE[204]
        when 'EXECUTE'
          execute(argument)
        else
          RESPONSE[400]
        end
      return result
    end

    def execute(args)
      if args.nil? or args.empty?
        result = RESPONSE[400]
      elsif not __check_argument(args)
        result = RESPONSE[400]
      else
        name = args[0]
        if name == 'GET_POSITION'
          if args[1] == @sakura_name ## FIXME: HWND support
            side = 0
          elsif args[1] == @kero_name ## FIXME: HWND support
            side = 1
          else
            return RESPONSE[400]
          end
          begin
            x, y = @__sakura.get_surface_position(side)
            w, h = @__sakura.get_surface_size(side)
            result = ("SAORI/1.0 200 OK\r\n" \
                      + "Result: " + x.to_s + "\r\n" \
                      + "Value0: " + x.to_s + "\r\n" \
                      + "Value1: " + (x + (w / 2).to_i).to_s + "\r\n" \
                      + "Value2: " + (x + w).to_s + "\r\n\r\n")
            result = result.encode('ascii', :invalid => :replace, :undef => :replace)
          rescue
            result = RESPONSE[500]
          end
        elsif name == 'GET_DESKTOP_SIZE'
          begin
            left, top, scrn_w, scrn_h = @__sakura.get_workarea
            result = ("SAORI/1.0 200 OK\r\n" \
                      + "Result: " + scrn_w.to_s + "\r\n" \
                      + "Value0: " + scrn_w.to_s + "\r\n" \
                      + "Value1: " + scrn_h.to_s + "\r\n\r\n")
            result = result.encode('ascii', :invalid => :replace, :undef => :replace)
          rescue
            result = RESPONSE[500]
          end
        else
          enqueue_commands(name, args[1..-1])
          do_idle_tasks() if @timeout_id.nil?
          result = RESPONSE[204]
        end
        return result
      end
    end

    def enqueue_commands(command, args)
      #fail "assert" unless ['MOVE', 'MOVE_INSIDE', 'MOVETO', 'MOVETO_INSIDE',
      #                      'ZMOVE', 'WAIT', 'NOTIFY',
      #                      'STANDBY', 'STANDBY_INSIDE',
      #                      'CLEAR'].include?(command)
      if args[0] == @sakura_name ## FIXME: HWND support
        side = 0
      elsif args[0] == @kero_name ## FIXME: HWND support
        side = 1
      else
        return # XXX
      end
      if command == 'CLEAR'
        @commands[side] = []
      else
        if ['STANDBY', 'STANDBY_INSIDE'].include?(command)
          @commands[0] = []
          @commands[1] = []
        end
        @commands[side] << [command, args[1..-1]]
      end
    end

    def do_idle_tasks
      for side in [0, 1]
        if not @commands[side].empty?
          command, args = @commands[side].shift
          case command
          when 'MOVE', 'MOVE_INSIDE'
            x, y = @__sakura.get_surface_position(side)
            vx = args[0].to_i
            speed = args[1].to_i
            if command == 'MOVE_INSIDE'
              w, h = @__sakura.get_surface_size(side)
              left, top, scrn_w, scrn_h = @__sakura.get_workarea
              if vx < 0 and x + vx <0
                vx = [-x, 0].min
              elsif vx > 0 and x + vx + w > left + scrn_w
                vx = [left + scrn_w - w - x, 0].max
              end
            end
            if vx.abs > speed
              if vx > 0
                @__sakura.set_surface_position(
                  side, x + speed, y)
                @commands[side].insert(
                  0, [command, [(vx - speed).to_s, args[1]]])
              elsif vx < 0
                @__sakura.set_surface_position(
                  side, x - speed, y)
                @commands[side].insert(
                  0, [command, [(vx + speed).to_s, args[1]]])
              end
            else
              @__sakura.set_surface_position(side, x + vx, y)
            end
          when 'MOVETO', 'MOVETO_INSIDE'
            x, y = @__sakura.get_surface_position(side)
            to = args[0].to_i
            speed = args[1].to_i
            if command == 'MOVETO_INSIDE'
              w, h = @__sakura.get_surface_size(side)
              left, top, scrn_w, scrn_h = @__sakura.get_workarea
              if to < 0
                to = 0
              elsif to > left + scrn_w - w
                to = (left + scrn_w - w)
              end
            end
            if (to - x).abs > speed
              if to - x > 0
                @__sakura.set_surface_position(
                  side, x + speed, y)
                @commands[side].insert(0, [command, args])
              elsif to - x < 0
                @__sakura.set_surface_position(
                  side, x - speed, y)
                @commands[side].insert(0, [command, args])
              end
            else
              @__sakura.set_surface_position(side, to, y)
            end
          when 'STANDBY', 'STANDBY_INSIDE'
            #pass ## FIXME: not supported yet
          when 'ZMOVE'
            if args[0] == '1'
              @__sakura.raise_surface(side)
            elsif args[0] == '2'
              @__sakura.lower_surface(side)
            else
              #pass
            end
          when 'WAIT'
            begin
              wait = Integer(args[0]) # ms
            rescue
              wait = 0
            end
            if wait < 25
              #pass
            else
              @commands[side].insert(0, ['WAIT', (wait - 20).to_s])
            end
          when 'NOTIFY'
            @__sakura.notify_event(*args)
          end
        end
        if @commands[0].empty? and @commands[1].empty?
          GLib::Source.remove(@timeout_id) unless @timeout_id.nil?
          @timeout_id = nil
        else
          if @timeout_id.nil?
            @timeout_id = GLib::Timeout.add(20) { do_idle_tasks }
          end
        end
      end
    end
  end
end
