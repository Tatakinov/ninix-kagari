# -*- coding: utf-8 -*-
#
#  Copyright (C) 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
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

require_relative "metamagic"
require_relative "logging"

module Seriko

  class Controller < MetaMagic::Holon

    DEFAULT_FPS = 30.0 # current default

    def initialize(seriko)
      super("") # FIXME
      @seriko = seriko
      @exclusive_actor = nil
      @base_id = nil
      @timeout_id = nil
      reset_overlays()
      @queue = []
      @fps = DEFAULT_FPS
      @next_tick = 0
      @prev_tick = 0 # XXX
      @active = []
      @move = nil
      @dirty = true
    end

    def set_base_id(window, surface_id)
      case surface_id
      when '-2'
        terminate(window)
        @base_id = window.get_surface_id
      when '-1'
        @base_id = window.get_surface_id
      else
        @base_id = surface_id
      end
      @dirty = true
    end

    def get_base_id()
      @base_id
    end

    def move_surface(xoffset, yoffset)
      @move = [xoffset, yoffset]
    end

    def append_actor(frame, actor)
      @active << [frame, actor]
    end

    def update_frame(window)
      frame, actor = get_actor_next(window)
      last_actor = actor
      while not actor.nil?
        actor.update(window, frame)
        last_actor = actor
        frame, actor = get_actor_next(window)
      end
      if not last_actor.nil? and last_actor.exclusive? and \
        last_actor.terminate? and @exclusive_actor.nil? # XXX
        invoke_restart(window)
      end
    end

    def get_actor_next(window)
      unless @active.empty?
        @active.sort! {|x| x[0]} # (key=lambda {|x| return x[0]})
        return @active.shift if @active[0][0] <= @next_tick
      end
      return nil, nil
    end

    def update(window)
      ## FIXME: use GLib.get_monotonic_time
      current_tick = (Time.now.to_f * 1000000).to_i # [microsec]
      quality = @parent.handle_request('GET', 'get_preference', 'animation_quality')
      @fps = DEFAULT_FPS * quality
      if @prev_tick.zero? ## First time
        delta_tick = (1000.0 / @fps) # [msec]
      else
        delta_tick = ((current_tick - @prev_tick) / 1000) # [msec]
      end
      @next_tick += delta_tick
      @prev_tick = current_tick
      update_frame(window)
      window.update_frame_buffer() if @dirty
      @dirty = false
      window.move_surface(*@move) if not @move.nil?
      @move = nil
      @timeout_id = GLib::Timeout.add((1000.0 / @fps).to_i) { update(window) } # [msec]
      return false
    end

    def lock_exclusive(window, actor)
      fail "assert" unless @exclusive_actor.nil?
      terminate(window)
      @exclusive_actor = actor
      actor.set_post_proc(
        ->(w, a) { unlock_exclusive(w, a) },
        [window, actor])
      @dirty = true # XXX
    end

    def unlock_exclusive(window, actor)
      fail "assert" unless @exclusive_actor == actor
      @exclusive_actor = nil
    end

    def reset_overlays()
      @overlays = {}
      @dirty = true
    end

    def remove_overlay(actor)
      @dirty = true unless @overlays.delete(actor).nil?
    end

    def add_overlay(window, actor, surface_id, x, y, method)
      case surface_id
      when '-2'
        terminate(window)
        remove_overlay(actor)
        return
      when '-1'
        remove_overlay(actor)
        return
      end
      @overlays[actor] = [surface_id, x, y, method]
      @dirty = true
    end

    def invoke_actor(window, actor)
      if not @exclusive_actor.nil?
        interval = actor.get_interval()
        return if interval.include?('talk') or interval.include?('yen-e')
        @queue << actor
        return
      end
      lock_exclusive(window, actor) if actor.exclusive?
      actor.invoke(window, @next_tick)
    end

    def invoke(window, actor_id, update: 0)
      return unless @seriko.include?(@base_id)
      for actor in @seriko[@base_id]
        if actor_id == actor.get_id()
          invoke_actor(window, actor)
          break
        end
      end
    end

    def invoke_yen_e(window, surface_id)
      return unless @seriko.include?(surface_id)
      for actor in @seriko[surface_id]
        interval = actor.get_interval
        if interval.include?('yen-e') and actor.enable
          invoke_actor(window, actor)
          break
        end
      end
    end

    def invoke_talk(window, surface_id, count)
      return false unless @seriko.include?(surface_id)
      interval_count = nil
      for actor in @seriko[surface_id]
        interval = actor.get_interval()
        if interval.include?('talk')
          interval_count = actor.get_factor # XXX
          break
        end
      end
      if not interval_count.nil? and count >= interval_count
        invoke_actor(window, actor)
        return true
      else
        return false
      end
    end

    def invoke_runonce(window)
      return unless @seriko.include?(@base_id)
      for actor in @seriko[@base_id]
        interval = actor.get_interval
        if interval.include?('runonce') and actor.enable
          invoke_actor(window, actor)
        end
      end
    end

    def invoke_always(window)
      return unless @seriko.include?(@base_id)
      for actor in @seriko[@base_id]
        interval = actor.get_interval
        if ['always', 'sometimes', 'rarely', 'random', 'periodic'].any? do |e|
            interval.include?(e)
          end
          invoke_actor(window, actor)
        end
      end
    end

    def invoke_bind(window)
      return unless @seriko.include?(@base_id)
      @seriko[@base_id].each do |actor|
        interval = actor.get_interval
        if interval == ['bind']
          invoke_actor(window, actor)
        elsif interval.include?('runonce')
          invoke_actor(window, actor)
        end
      end
    end

    def invoke_restart(window)
      return unless @seriko.include?(@base_id)
      for actor in @seriko[@base_id]
        if @queue.include?(actor)
          @queue.remove(actor)
          invoke_actor(window, actor)
        end
      end
    end

    def invoke_kinoko(window) # XXX
      return unless @seriko.include?(@base_id)
      for actor in @seriko[@base_id]
        if ['always', 'runonce',
            'sometimes', 'rarely',].include?(actor.get_interval())
          invoke_actor(window, actor)
        end
      end
    end

    def is_playing_animation(actor_id)
      @active.any? do |_, actor|
        next actor.get_id == actor_id
      end
    end

    def clear_animation(actor_id)
      @active.filter! do |_, actor|
        next actor.get_id != actor_id
      end
    end

    def pause_animation(actor_id)
      @active.each do |_, actor|
        actor.pause if actor.get_id == actor_id
      end
    end

    def resume_animation(actor_id)
      @active.each do |_, actor|
        actor.resume if actor.get_id == actor_id
      end
    end

    def offset_animation(actor_id, x, y)
      @active.each do |_, actor|
        actor.offset(x, y) if actor.get_id == actor_id
      end
    end

    def reset(window, surface_id)
      @queue = []
      terminate(window)
      @next_tick = 0
      @prev_tick = 0 # XXX
      set_base_id(window, window.get_surface_id)
      if @seriko.include?(surface_id)
        @base_id = surface_id
      else
        @base_id = window.get_surface_id
      end
      @dirty = true # XXX
    end

    def start(window, bind)
      invoke_runonce(window)
      invoke_always(window)
      if @seriko.include?(@base_id)
        @seriko[@base_id].each do |actor|
          if bind.include?(actor.get_id)
            group, enable, option = bind[actor.get_id]
            actor.toggle_bind(enable)
          end
        end
      end
      invoke_bind(window)
      GLib::Source.remove(@timeout_id) if not @timeout_id.nil?
      @timeout_id = GLib::Timeout.add((1000.0 / @fps).to_i) { update(window) } # [msec]
    end

    def terminate(window)
      if @seriko.include?(@base_id)
        for actor in @seriko[@base_id]
          actor.terminate(window)
        end
      end
      reset_overlays()
      @active = []
      @move = nil
      @dirty = true
    end

    def stop_actor(window, actor_id)
      return unless @seriko.include?(@base_id)
      for actor in @seriko[@base_id]
        if actor.get_id() == actor_id
          actor.terminate(window)
        end
      end
    end

    def destroy()
      GLib::Source.remove(@timeout_id) unless @timeout_id.nil?
      @timeout_id = nil
    end

    def iter_overlays()
      actors = @overlays.keys().sort_by do |actor|
        actor.get_id
      end
      result = []
      for actor in actors
        surface_id, x, y, method = @overlays[actor]
        ##Logging::Logging.debug(
        ##  'actor=' + actor.get_id().to_s +
        ##  ', id=' + surface_id.to_s +
        ##  ', x=' + x.to_s +
        ##  ', y=' + y.to_s)
        result << [surface_id, x, y, method]
      end
      return result
    end
  end


  class Actor

    def initialize(actor_id, interval)
      @id = actor_id
      @interval = interval
      @patterns = []
      @remove_overlay = false
      @last_method = nil
      @exclusive = 0
      @post_proc = nil
      @terminate_flag = true
    end

    def terminate?
      @terminate_flag
    end

    def exclusive?
      @exclusive.zero? ? false : true
    end

    def set_post_proc(post_proc, args)
      fail "assert" unless @post_proc.nil?
      @post_proc = [post_proc, args]
    end

    def set_exclusive()
      @exclusive = 1
    end

    def get_id()
      @id
    end

    def get_interval()
      @interval
    end

    def get_patterns()
      @patterns
    end

    def add_pattern(surface, interval, method, args)
      @patterns << [surface, interval, method, args]
    end

    def invoke(window, base_frame)
      @terminate_flag = false
    end

    def update(window, base_frame)
      return false if @terminate_flag
    end

    def terminate(window)
      @terminate_flag = true
      window.remove_overlay(self) unless window.nil?
      unless @post_proc.nil?
        post_proc, args = @post_proc
        @post_proc = nil
        post_proc.call(*args)
      end
    end

    def get_surface_ids()
      surface_ids = []
      for surface, interval, method, args in @patterns
        if method == 'base'
          surface_ids << surface
        end
      end
      return surface_ids
    end

    OVERLAY_SET = ['overlay', 'overlayfast', 'overlaymultiply',
                   'interpolate', 'reduce', 'replace', 'asis',
                   'bind', 'add']

    def show_pattern(window, surface, method, args)
      if @remove_overlay and OVERLAY_SET.include?(method)
        window.remove_overlay(self)
      end
      case method
      when 'move'
        window.get_seriko.move_surface(args[0], args[1])
      when *OVERLAY_SET
        @remove_overlay = true
        window.add_overlay(self, surface, args[0], args[1], method)
      when 'base'
        window.get_seriko.set_base_id(window, surface)
      when 'start'
        window.invoke(args[0], :update => 1)
      when 'alternativestart'
        window.invoke(args.sample, :update => 1)
      when 'stop'
        window.get_seriko.stop_actor(window, args[0])
      when 'alternativestop'
        window.get_seriko.stop_actor(window, args.sample)
      when 'parallelstart'
        for e in args
          window.invoke(e, update: 1)
        end
      when 'parallelstop'
        for e in args
          window.get_seriko.stop_actor(window, e)
        end
      else
        fail RuntimeError, 'unreachable'
      end
      @last_method = method
    end
  end

=begin

  class ActiveActor < Actor # always

    def initialize(actor_id, interval)
      super(actor_id, interval)
      @wait = 0
      @pattern = 0
    end

    def invoke(window, base_frame)
      terminate(window)
      @terminate_flag = false
      @pattern = 0
      update(window, base_frame)
    end

    def update(window, base_frame)
      return false if @terminate_flag
      if @pattern.zero?
        @surface_id = window.get_surface()
      end
      surface, interval, method, args = @patterns[@pattern]
      @pattern += 1
      if @pattern == @patterns.length
        @pattern = 0
      end
      show_pattern(window, surface, method, args)
      window.append_actor(base_frame + interval, self)
      return false
    end
  end

  class RandomActor < Actor # sometimes, rarely, random, periodic

    def initialize(actor_id, interval, wait_min, wait_max)
      super(actor_id, interval)
      @wait_min = wait_min
      @wait_max = wait_max
      reset()
    end

    def reset()
      @wait = rand(@wait_min..@wait_max)
      @pattern = 0
    end

    def invoke(window, base_frame)
      terminate(window)
      @terminate_flag = false
      reset()
      window.append_actor(base_frame + @wait, self)
    end

    def update(window, base_frame)
      return false if @terminate_flag
      if @pattern.zero?
        @surface_id = window.get_surface()
      end
      surface, interval, method, args = @patterns[@pattern]
      @pattern += 1
      if @pattern < @patterns.length
        @wait = interval
      else
        reset()
      end
      show_pattern(window, surface, method, args)
      window.append_actor(base_frame + @wait, self)
      return false
    end
  end


  class OneTimeActor < Actor # runone

    def initialize(actor_id, interval)
      super(actor_id, interval)
      @wait = -1
      @pattern = 0
    end

    def invoke(window, base_frame)
      terminate(window)
      @terminate_flag = false
      @wait = 0
      @pattern = 0
      update(window, base_frame)
    end

    def update(window, base_frame)
      return false if @terminate_flag
      if @pattern.zero?
        @surface_id = window.get_surface()
      end
      surface, interval, method, args = @patterns[@pattern]
      @pattern += 1
      if @pattern < @patterns.length
        @wait = interval
      else
        @wait = -1 # done
        # 最後で-1していない場合はlayerを保持する
        terminate(nil)
      end
      show_pattern(window, surface, method, args)
      if @wait >= 0
        window.append_actor(base_frame + @wait, self)
      end
      return false
    end
  end

  class PassiveActor < Actor # never, yen-e, talk

    def initialize(actor_id, interval)
      super(actor_id, interval)
      @wait = -1
    end

    def invoke(window, base_frame)
      terminate(window)
      @terminate_flag = false
      @wait = 0
      @pattern = 0
      update(window, base_frame)
    end

    def update(window, base_frame)
      return false if @terminate_flag
      if @pattern.zero?
        @surface_id = window.get_surface()
      end
      surface, interval, method, args = @patterns[@pattern]
      @pattern += 1
      if @pattern < @patterns.length
        @wait = interval
      else
        @wait = -1 # done
        # 最後で-1していない場合はlayerを保持する
        terminate(nil)
      end
      show_pattern(window, surface, method, args)
      if @wait >= 0
        window.append_actor(base_frame + @wait, self)
      end
      return false
    end
  end

=end

  class Mayuna < Actor

    def set_exclusive()
    end

    def show_pattern(window, surface, method, args)
    end
  end

  class MultipleActor < Actor
    def initialize(actor_id, interval, factor)
      super(actor_id, interval)
      @factor = factor
      @enable_bind = false
    end

    def get_factor
      return @factor
    end

    def toggle_bind(toggle = nil)
      if toggle.nil?
        @enable_bind = not(@enable_bind)
      else
        @enable_bind = toggle
      end
    end

    def enable
      return true unless @interval.include?('bind')
      return true if @interval.include?('bind') and @enable_bind
      return false
    end

    def invoke(window, base_frame)
      terminate(window)
      @terminate_flag = false
      @pattern = 0
      @resume = true
      @offset = [0, 0]
      update(window, base_frame)
    end

    def pause
      @resume = false
    end

    def resume
      @resume = true
    end

    def offset(x, y)
      @offset = [x, y]
    end

    def update(window, base_frame)
      return false if @terminate_flag
      return false if @interval.include?('bind') and not @enable_bind
      if @interval == ['bind']
        for surface, interval, method, args in @patterns
          if OVERLAY_SET.include?(method)
            x = args[0] + @offset[0]
            y = args[1] + @offset[1]
            args = [x, y]
          end
          show_pattern(window, surface, method, args)
        end
      else
        surface, interval, method, args = @patterns[@pattern]
        if OVERLAY_SET.include?(method)
          x = args[0] + @offset[0]
          y = args[1] + @offset[1]
          args = [x, y]
        end
        if @resume
          @pattern += 1
          if interval.instance_of?(Array)
            wait = rand(interval[0] .. interval[1])
          else
            wait = interval
          end
          if @pattern == @patterns.length
            @pattern = 0
            # random系の秒数決定の乱数(0 < x < 1)
            while (x = rand) == 0
            end
            if @interval.include?('sometimes')
              wait = (-Math.log(2, x)).ceil * 1_000_000
            elsif @interval.include?('rarely')
              wait = (-Math.log(4, x)).ceil * 1_000_000
            elsif @interval.include?('random')
              wait = (-Math.log(@factor, x)).ceil * 1_000_000
            elsif @interval.include?('periodic')
              wait = @factor * 1_000_000
            elsif @interval.include?('always')
              # nop
            elsif ['runonce', 'never', 'yen-e', 'talk'].any? do |e|
                @interval.include?(e)
              end
              wait = -1
              terminate(nil)
            else
              fail RuntimeError, 'unreachable'
            end
          end
        else
          wait = 1
        end
        show_pattern(window, surface, method, args)
        if wait >= 0
          zero = true
          for _, interval, _, _ in @patterns
            if interval.instance_of?(Array) or not interval.zero?
              zero = false
              break
            end
          end
          # wait0のみで構成されるalwaysなanimation対策
          if zero and @pattern == 0 and @interval.include?('always') # wait0のみで構成されるanimation対策
            wait = 1
          end
          window.append_actor(base_frame + wait, self)
        end
      end
      return false
    end
  end

  def self.get_actors(config, version: nil)
    re_seriko_interval = Regexp.new('\A([0-9]+)interval\z')
    re_seriko_interval_value = Regexp.new('\A(bind|sometimes|rarely|random,[0-9]+|always|runonce|yen-e|talk,[0-9]+|never)\z')
    re_seriko_pattern = Regexp.new('\A([0-9]+|-[12])\s*,\s*([+-]?[0-9]+)\s*,\s*(overlay|overlayfast|overlaymultiply|base|move|start|alternativestart|)\s*,?\s*([+-]?[0-9]+)?\s*,?\s*([+-]?[0-9]+(?:-[0-9]+)?)?\s*,?\s*(\[[0-9]+(\.[0-9]+)*\])?\z')
    re_seriko2_interval = Regexp.new('\Aanimation([0-9]+)\.interval\z')
    re_interval = '(bind|sometimes|rarely|random|periodic|always|runonce|yen-e|talk|never)'
    re_seriko2_interval_value = Regexp.new('\A(' + re_interval + '(\+' + re_interval + ')*(,[0-9]+)?)\z')
    re_seriko2_pattern = Regexp.new('\A(overlay|overlayfast|overlaymultiply|interpolate|reduce|replace|asis|bind|add|base|move|start|alternativestart|parallelstart|stop|alternativestop|parallelstop)\s*,\s*([0-9]+|-[12])?\s*,?\s*([+-]?[0-9]+(?:-[0-9]+)?)?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*(\([0-9]+([\.\,][0-9]+)*\))?\z')
    re_pattern = Regexp.new('([+-]?[0-9]+)-([0-9]+)')
    buf = []
    for key, value in config.each_entry
      if version == 1
        match = re_seriko_interval.match(key)
      elsif version == 2
        match = re_seriko2_interval.match(key)
      else
        match1 = re_seriko_interval.match(key)
        match2 = re_seriko2_interval.match(key)
        if not match1.nil?
          version = 1
          match = match1
        elsif not match2.nil?
          version = 2
          match = match2
        else
          next
        end
      end
      next if match.nil?
      next if version == 1 and not re_seriko_interval_value.match(value)
      next if version == 2 and not re_seriko2_interval_value.match(value)
      buf << [match[1].to_i, value]
    end
    actors = []
    for actor_id, interval in buf
      tmp = interval.split(',', 2)
      if tmp.length == 1
        factor = 0
      else
        interval, factor = tmp
        factor = factor.to_i
      end
      interval = interval.split('+')
      count = 0
      for i in ['random', 'periodic', 'talk']
        count += 1 if interval.include?(i)
      end
      if count > 1
        Logging::Logging.error('seriko.rb: too many parameterized interval')
        next
      end
      actor = Seriko::MultipleActor.new(actor_id, interval, factor)
=begin
      if interval == 'always'
        actor = Seriko::ActiveActor.new(actor_id, interval)
      elsif interval == 'sometimes'
        actor = Seriko::RandomActor.new(actor_id, interval, 0, 10000) # 0 to 10 seconds
      elsif interval == 'rarely'
        actor = Seriko::RandomActor.new(actor_id, interval, 20000, 60000)
      elsif interval.start_with?('random')
        actor = Seriko::RandomActor.new(actor_id, interval,
                                        0, 1000 * interval[7, interval.length - 1].to_i)
      elsif interval.start_with?('periodic')
        actor = Seriko::RandomActor.new(actor_id, interval,
                                        1000 * interval[9, interval.length - 1].to_i,
                                        1000 * interval[9, interval.length - 1].to_i)
      elsif interval == 'runonce'
        actor = Seriko::OneTimeActor.new(actor_id, interval)
      elsif interval == 'yen-e'
        actor = Seriko::PassiveActor.new(actor_id, interval)
      elsif interval.start_with?('talk')
        actor = Seriko::PassiveActor.new(actor_id, interval)
      elsif interval == 'never'
        actor = Seriko::PassiveActor.new(actor_id, interval)
      end
=end
      if version == 1
        key = (actor_id.to_s + 'option')
      else
        key = ('animation' + actor_id.to_s + '.option')
      end
      if config.include?(key) and config[key] == 'exclusive'
        actor.set_exclusive()
      end
      begin
        for n in config.each_pattern(actor_id) # up to 128 patterns (0 - 127)
          if version == 1
            key = (actor_id.to_s + 'pattern' + n.to_s)
          else
            key = ('animation' + actor_id.to_s + '.pattern' + n.to_s)
          end
          unless config.include?(key)
            key = (actor_id.to_s + 'patturn' + n.to_s) # only for version 1
            unless config.include?(key)
              key = (actor_id.to_s + 'putturn' + n.to_s) # only for version 1
              next unless config.include?(key) # XXX
            end
          end
          pattern = config[key]
          if version == 1
            match = re_seriko_pattern.match(pattern)
          else
            match = re_seriko2_pattern.match(pattern)
          end
          fail ("unsupported pattern: #{pattern}") if match.nil?
          if version == 1
            surface = match[1].to_i.to_s
            m = re_pattern.match(match[2])
            if m.nil?
              wait = match[2].to_i.abs * 10
            else
              wait = [m[1].to_i.abs * 10, m[2].to_i.abs * 10]
              if wait[0] > wait[1]
                wait = [wait[1], wait[0]]
              end
            end
            method = match[3]
          else
            method = match[1]
            if match[2].nil?
              surface = 0
            else
              surface = match[2].to_i.to_s
            end
            if match[3].nil?
              wait = 0
            else
              m = re_pattern.match(match[3])
              if m.nil?
                wait = match[3].to_i.abs
              else
                wait = [m[1].to_i.abs, m[2].to_i.abs]
                if wait[0] > wait[1]
                  wait = [wait[1], wait[0]]
                end
              end
            end
          end
          if method == ''
            method = 'base'
          end
          if interval == ['bind']
            if ['start', 'stop', 'alternativestart', 'alternativestop', 'parallelstart', 'parallelstop'].include?(method)
              Logging::Logging.error('seriko.rb: start/stop cannot use bind')
              next
            end
          end
          unless interval.include?('bind')
            if ['bind', 'add'].include?(method)
              Logging::Logging.error('seriko.rb: bind/add cannot use in !bind')
              next
            end
          end
          if ['start', 'stop'].include?(method)
            if version == 2
              group = match[2]
              surface = -1 # XXX
            else
              group = match[4]
            end
            if group.nil?
              fail ('syntax error: ' + pattern)
            end
            args = [group.to_i]
          elsif ['alternativestart', 'alternativestop', 'parallelstart', 'parallelstop'].include?(method)
            args = match[6]
            if args.nil?
              fail ('syntax error: ' + pattern)
            end
            t = []
            for x in args[1, args.length - 2].split('.', 0)
              for y in x.split(',', 0)
                t << y
              end
            end
            args = []
            for s in t
              args << s.to_i
            end
          else
            if ['-1', '-2'].include?(surface)
              x = 0
              y = 0
            else
              if match[4].nil?
                x = 0
              else
                x = match[4].to_i
              end
              if match[5].nil?
                y = 0
              else
                y = match[5].to_i
              end
            end
            args = [x, y]
          end
          actor.add_pattern(surface, wait, method, args)
        end
      rescue => e
        Logging::Logging.error('seriko.rb: ' + e.message)
        next
      end
      if actor.get_patterns().empty?
        Logging::Logging.error(
          'seriko.rb: animation group #' + actor_id.to_s + ' has no pattern (ignored)')
        next
      end
      actors << actor
    end
    return actors.sort_by do |actor|
      actor.get_id
    end
  end

  def self.get_mayuna(config)
    return get_actors(config).filter do |a|
      a.get_interval == ['bind']
    end
  end
end
