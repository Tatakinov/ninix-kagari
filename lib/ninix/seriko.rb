# -*- coding: utf-8 -*-
#
#  Copyright (C) 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"

module Seriko

  class Controller

    DEFAULT_FPS = 30.0 # current default

    def initialize(seriko)
      @seriko = seriko
      @parent = nil
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

    def set_responsible(parent)
      @parent = parent
    end
    
    def set_base_id(window, surface_id)
      if surface_id == '-2'
        terminate(window)
        @base_id = window.get_surface_id
      elsif surface_id == '-1'
        @base_id = window.get_surface_id
      else
        @base_id = surface_id
      end
      @dirty = true
    end

    def get_base_id()
      return @base_id
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
      while actor != nil
        actor.update(window, frame)
        last_actor = actor
        frame, actor = get_actor_next(window)
      end
      if last_actor != nil and last_actor.exclusive? and \
        last_actor.terminate? and @exclusive_actor == nil # XXX
        invoke_restart(window)
      end
    end

    def get_actor_next(window)
      if not @active.empty?
        @active.sort {|x| x[0]} # (key=lambda {|x| return x[0]})
        if @active[0][0] <= @next_tick
          return @active.shift
        end
      end
      return nil, nil
    end

    def update(window)
      ##current_tick = GLib.get_monotonic_time() # [microsec]
      ## FIXME: GLib.get_monotonic_time
      current_tick = (Time.now.to_f * 1000000).to_i # [microsec]
      quality = @parent.handle_request('GET', 'get_preference', 'animation_quality')
      @fps = DEFAULT_FPS * quality
      if @prev_tick == 0 ## First time
        delta_tick = 1000.0 / @fps # [msec]
      else
        delta_tick = (current_tick - @prev_tick) / 1000 # [msec]
      end
      @next_tick += delta_tick
      @prev_tick = current_tick
      update_frame(window)
      if @dirty
        window.update_frame_buffer()
        @dirty = false
      end
      if @move != nil
        window.move_surface(*@move)
        @move = nil
      end
      @timeout_id = GLib::Timeout.add((1000.0 / @fps).to_i) { update(window) } # [msec]
      return false
    end

    def lock_exclusive(window, actor)
      #assert @exclusive_actor is nil
      terminate(window)
      @exclusive_actor = actor
      actor.set_post_proc(
        ->(w, a) { unlock_exclusive(w, a) },
        [window, actor])
      @dirty = true # XXX
    end

    def unlock_exclusive(window, actor)
      #assert @exclusive_actor == actor
      @exclusive_actor = nil
    end

    def reset_overlays()
      @overlays = {}
      @dirty = true
    end

    def remove_overlay(actor)
      if @overlays.delete(actor)
        @dirty = true
      end
    end

    def add_overlay(window, actor, surface_id, x, y, method)
      if surface_id == '-2'
        terminate(window)
      end
      if ['-1', '-2'].include?(surface_id)
        remove_overlay(actor)
        return
      end
      @overlays[actor] = [surface_id, x, y, method]
      @dirty = true
    end

    def invoke_actor(window, actor)
      if @exclusive_actor != nil
        interval = actor.get_interval()
        if interval.start_with?('talk') or interval == 'yen-e'
          return
        end
        @queue << actor
        return
      end
      if actor.exclusive?
        lock_exclusive(window, actor)
      end
      actor.invoke(window, @next_tick)
    end

    def invoke(window, actor_id, update=0)
      if not @seriko.include?(@base_id)
        return
      end
      for actor in @seriko[@base_id]
        if actor_id == actor.get_id()
          invoke_actor(window, actor)
          break
        end
      end
    end

    def invoke_yen_e(window, surface_id)
      if not @seriko.include?(surface_id)
        return
      end
      for actor in @seriko[surface_id]
        if actor.get_interval() == 'yen-e'
          invoke_actor(window, actor)
          break
        end
      end
    end

    def invoke_talk(window, surface_id, count)
      if not @seriko.include?(surface_id)
        return false
      end
      interval_count = nil
      for actor in @seriko[surface_id]
        interval = actor.get_interval()
        if interval.start_with?('talk')
          interval_count = interval[5].to_i # XXX
          break
        end
      end
      if interval_count != nil and count >= interval_count
        invoke_actor(window, actor)
        return true
      else
        return false
      end
    end

    def invoke_runonce(window)
      if not @seriko.include?(@base_id)
        return
      end
      for actor in @seriko[@base_id]
        if actor.get_interval() == 'runonce'
          invoke_actor(window, actor)
        end
      end
    end

    def invoke_always(window)
      if not @seriko.include?(@base_id)
        return
      end
      for actor in @seriko[@base_id]
        interval = actor.get_interval()
        if ['always', 'sometimes', 'rarely'].include?(interval) or \
          interval.start_with?('random') or \
          interval.start_with?('periodic')
          invoke_actor(window, actor)
        end
      end
    end

    def invoke_restart(window)
      if not @seriko.include?(@base_id)
        return
      end
      for actor in @seriko[@base_id]
        if @queue.include?(actor)
          @queue.remove(actor)
          invoke_actor(window, actor)
        end
      end
    end

    def invoke_kinoko(window) # XXX
      if not @seriko.include?(@base_id)
        return
      end
      for actor in @seriko[@base_id]
        if ['always', 'runonce',
            'sometimes', 'rarely',].include?(actor.get_interval())
          invoke_actor(window, actor)
        end
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

    def start(window)
      invoke_runonce(window)
      invoke_always(window)
      if @timeout_id != nil
        GLib::Source.remove(@timeout_id)
      end
      @timeout_id = GLib::Timeout.add((1000.0 / @fps).to_i) { update(window) } # [msec]
    end

    def terminate(window)
      if @seriko.include?(@base_id)
        for actor in @seriko[@base_id]
          actor.terminate()
        end
      end
      reset_overlays()
      @active = []
      @move = nil
      @dirty = true
    end

    def stop_actor(actor_id)
      if not @seriko.include?(@base_id)
        return
      end
      for actor in @seriko[@base_id]
        if actor.get_id() == actor_id
          actor.terminate()
        end
      end
    end

    def destroy()
      if @timeout_id != nil
        GLib::Source.remove(@timeout_id)
        @timeout_id = nil
      end
    end

    def iter_overlays()
      actors = @overlays.keys()
      temp = []
      for actor in actors
        temp << [actor.get_id(), actor]
      end
      actors = temp
      actors.sort()
      temp = []
      for actor_id, actor in actors
        temp << actor
      end
      actors = temp
      result = []
      for actor in actors
        surface_id, x, y, method = @overlays[actor]
        ##logging.debug(
        ##    'actor={0:d}, id={1}, x={2:d}, y={3:d}'.format(
        ##        actor.get_id(), surface_id, x, y))
        #yield surface_id, x, y, method
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
      @last_method = nil
      @exclusive = 0
      @post_proc = nil
      @terminate_flag = true
    end

    def terminate?
      return @terminate_flag
    end

    def exclusive?
      if @exclusive != 0
        return true
      else
        return false
      end
    end

    def set_post_proc(post_proc, args)
      #assert @post_proc == nil
      @post_proc = [post_proc, args]
    end

    def set_exclusive()
      @exclusive = 1
    end

    def get_id()
      return @id
    end

    def get_interval()
      return @interval
    end

    def get_patterns()
      return @patterns
    end

    def add_pattern(surface, interval, method, args)
      @patterns << [surface, interval, method, args]
    end

    def invoke(window, base_frame)
      @terminate_flag = false
    end

    def update(window, base_frame)
      if @terminate_flag
        return false
      end
    end

    def terminate()
      @terminate_flag = true
      if @post_proc != nil
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

    OVERLAY_SET = ['overlay', 'overlayfast',
                   'interpolate', 'reduce', 'replace', 'asis']

    def show_pattern(window, surface, method, args)
      if OVERLAY_SET.include?(@last_method)
        window.remove_overlay(self)
      end
      if method == 'move'
        window.get_seriko.move_surface(args[0], args[1]) ## FIXME
      elsif OVERLAY_SET.include?(method)
        window.add_overlay(self, surface, args[0], args[1], method)
      elsif method == 'base'
        window.get_seriko.set_base_id(window, surface) ## FIXME
      elsif method == 'start'
        window.invoke(args[0], update=1)
      elsif method == 'alternativestart'
        window.invoke(args.sample, update=1)
      elsif method == 'stop'
        window.get_seriko.stop_actor(args[0]) ## FIXME
      elsif method == 'alternativestop'
        window.get_seriko.stop_actor(args.sample) ## FIXME
      else
        raise RuntimeError('should not reach here')
      end
      @last_method = method
    end
  end


  class ActiveActor < Actor # always

    def initialize(actor_id, interval)
      super(actor_id, interval)
      @wait = 0
      @pattern = 0
    end

    def invoke(window, base_frame)
      terminate()
      @terminate_flag = false
      @pattern = 0
      update(window, base_frame)
    end

    def update(window, base_frame)
      if @terminate_flag
        return false
      end
      if @pattern == 0
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
      terminate()
      @terminate_flag = false
      reset()
      window.append_actor(base_frame + @wait, self)
    end

    def update(window, base_frame)
      if @terminate_flag
        return false
      end
      if @pattern == 0
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
      terminate()
      @terminate_flag = false
      @wait = 0
      @pattern = 0
      update(window, base_frame)
    end

    def update(window, base_frame)
      if @terminate_flag
        return false
      end
      if @pattern == 0
        @surface_id = window.get_surface()
      end
      surface, interval, method, args = @patterns[@pattern]
      @pattern += 1
      if @pattern < @patterns.length
        @wait = interval
      else
        @wait = -1 # done
        terminate()
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
      terminate()
      @terminate_flag = false
      @wait = 0
      @pattern = 0
      update(window, base_frame)
    end

    def update(window, base_frame)
      if @terminate_flag
        return false
      end
      if @pattern == 0
        @surface_id = window.get_surface()
      end
      surface, interval, method, args = @patterns[@pattern]
      @pattern += 1
      if @pattern < @patterns.length
        @wait = interval
      else
        @wait = -1 # done
        terminate()
      end
      show_pattern(window, surface, method, args)
      if @wait >= 0
        window.append_actor(base_frame + @wait, self)
      end
      return false
    end
  end


  class Mayuna < Actor

    def set_exclusive()
    end

    def show_pattern(window, surface, method, args)
    end
  end


  def self.get_actors(config, version=1)
    re_seriko_interval = Regexp.new('^([0-9]+)interval$')
    re_seriko_interval_value = Regexp.new('^(sometimes|rarely|random,[0-9]+|always|runonce|yesn-e|talk,[0-9]+|never)$')
    re_seriko_pattern = Regexp.new('^([0-9]+|-[12])\s*,\s*([+-]?[0-9]+)\s*,\s*(overlay|overlayfast|base|move|start|alternativestart|)\s*,?\s*([+-]?[0-9]+)?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*(\[[0-9]+(\.[0-9]+)*\])?$')
    re_seriko2_interval = Regexp.new('^animation([0-9]+)\.interval$')
    re_seriko2_interval_value = Regexp.new('^(sometimes|rarely|random,[0-9]+|periodic,[0-9]+|always|runonce|yesn-e|talk,[0-9]+|never)$')
    re_seriko2_pattern = Regexp.new('^(overlay|overlayfast|interpolate|reduce|replace|asis|base|move|start|alternativestart|stop|alternativestop)\s*,\s*([0-9]+|-[12])?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*(\([0-9]+([\.\,][0-9]+)*\))?$')
    buf = []
    for key, value in config.each_entry
      if version == 1
        match = re_seriko_interval.match(key)
      elsif version == 2
        match = re_seriko2_interval.match(key)
      else
        return [] ## should not reach here
      end
      if not match
        next
      end
      if version == 1 and not re_seriko_interval_value.match(value)
        next
      end
      if version == 2 and not re_seriko2_interval_value.match(value)
        next
      end
      buf << [match[1].to_i, value]
    end
    actors = []
    for actor_id, interval in buf
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
      if version == 1
        key = actor_id.to_s + 'option'
      else
        key = 'animation' + actor_id.to_s + '.option'
      end
      if config.include?(key) and config[key] == 'exclusive'
        actor.set_exclusive()
      end
      begin
        for n in 0..127 # up to 128 patterns (0 - 127)
          if version == 1
            key = actor_id.to_s + 'pattern' + n.to_s
          else
            key = 'animation' + actor_id.to_s + '.pattern' + n.to_s
          end
          if not config.include?(key)
            key = actor_id.to_s + 'patturn' + n.to_s # only for version 1
            if not config.include?(key)
              key = actor_id.to_s + 'putturn' + n.to_s # only for version 1
              if not config.include?(key)
                next # XXX
              end
            end
          end
          pattern = config[key]
          if version == 1
            match = re_seriko_pattern.match(pattern)
          else
            match = re_seriko2_pattern.match(pattern)
          end
          if not match
#            raise ValueError('unsupported pattern: {0}'.format(pattern))
#            raise ValueError, 'unsupported pattern: ' + pattern + "\n"
#            raise 'unsupported pattern: ' + pattern + "\n"
            print('unsupported pattern: ' + pattern + "\n")
            next ## FIXME
          end
          if version == 1
            surface = match[1].to_i.to_s
            interval = match[2].to_i.abs * 10
            method = match[3]
          else
            method = match[1]
            if not match[2]
              surface = 0
            else
              surface = match[2].to_i.to_s
            end
            if not match[3]
              interval = 0
            else
              interval = match[3].to_i.abs
            end
          end
          if method == ''
            method = 'base'
          end
          if ['start', 'stop'].include?(method)
            if version == 2
              group = match[2]
              surface = -1 # XXX
            else
              group = match[4]
            end
            if group == nil
#              raise ValueError('syntax error: {0}'.format(pattern))
#              raise ValueError, 'syntax error: ' + pattern + "\n"
#              raise 'syntax error: ' + pattern + "\n"
              print('syntax error: ' + pattern + "\n")
              next ## FIXME
            end
            args = [group.to_i]
          elsif ['alternativestart', 'alternativestop'].include?(method)
            args = match[6]
            if args == nil
#              raise ValueError('syntax error: {0}'.format(pattern))
#              raise ValueError, 'syntax error: ' + pattern + "\n"
#              raise 'syntax error: ' + pattern + "\n"
              print('syntax error: ' + pattern + "\n")
              next ## FIXME
            end
            t = []
            for x in args[1, args.length - 2].split('.')
              for y in x.split(',')
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
              if not match[4]
                x = 0
              else
                x = match[4].to_i
              end
              if not match[5]
                y = 0
              else
                y = match[5].to_i
              end
            end
            args = [x, y]
          end
          actor.add_pattern(surface, interval, method, args)
        end
      rescue # except ValueError as error:
        #logging.error('seriko.py: ' + error.to_s)
        next
      end
      if actor.get_patterns().empty?
#        logging.error(
#                      'seriko.py: animation group #{0:d} has no pattern (ignored)'.format(actor_id))
        print('seriko.py: animation group #', actor_id, ' has no pattern (ignor
ed)', "\n")
        next
      end
      actors << actor
    end
    temp = []
    for actor in actors
      temp << [actor.get_id(), actor]
    end
    actors = temp
    actors.sort()
    temp = []
    for actor_id, actor in actors
      temp << actor
    end
    actors = temp
    return actors
  end

  def self.get_mayuna(config)
    re_mayuna_interval = Regexp.new('^([0-9]+)interval$')
    re_mayuna_interval_value = Regexp.new('^(bind)$')
    re_mayuna_pattern = Regexp.new('^([0-9]+|-[12])\s*,\s*([0-9]+)\s*,\s*(bind|add|reduce|insert)\s*,?\s*([+-]?[0-9]+)?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*(\[[0-9]+(\.[0-9]+)*\])?$')
    re_mayuna2_interval = Regexp.new('^animation([0-9]+)\.interval$')
    re_mayuna2_interval_value = Regexp.new('^(bind)$')
    re_mayuna2_pattern = Regexp.new('^(bind|add|reduce|insert)\s*,\s*([0-9]+|-[12])\s*,\s*([0-9]+)\s*,?\s*([+-]?[0-9]+)?\s*,?\s*([+-]?[0-9]+)?\s*,?\s*(\([0-9]+(\.[0-9]+)*\))?$')
    version = nil
    buf = []
    for key, value in config.each_entry
      if version == 1
        match = re_mayuna_interval.match(key)
      elsif version == 2
        match = re_mayuna2_interval.match(key)
      else
        match1 = re_mayuna_interval.match(key)
        match2 = re_mayuna2_interval.match(key)
        if match1
          version = 1
          match = match1
        elsif match2
          version = 2
          match = match2
        else
          next
        end
      end
      if not match
        next
      end
      if version == 1 and not re_mayuna_interval_value.match(value)
        next
      end
      if version == 2 and not re_mayuna2_interval_value.match(value)
        next
      end
      buf << [match[1].to_i, value]
    end
    mayuna = []
    for mayuna_id, interval in buf
      ##assert interval == 'bind'
      actor = Seriko::Mayuna.new(mayuna_id, interval)
      begin
        for n in 0..127 # up to 128 patterns (0 - 127)
          if version == 1
            key = mayuna_id.to_s + 'pattern' + n.to_s
          else
            key = 'animation' + mayuna_id.to_s + '.pattern' + n.to_s
          end
          if not config.include?(key)
            key = mayuna_id.to_s + 'patturn' + n.to_s # only for version 1
            if not config.include?(key)
              next # XXX
            end
          end
          pattern = config[key]
          if version == 1
            match = re_mayuna_pattern.match(pattern)
          else
            match = re_mayuna2_pattern.match(pattern)
          end
          if not match
#            raise ValueError('unsupported pattern: {0}'.format(pattern))
#            raise ValueError, 'unsupported pattern: ' + pattern + "\n"
#            raise 'unsupported pattern: ' + pattern + "\n"
            print('unsupported pattern: ' + pattern + "\n")
            next ## FIXME
          end
          if version == 1
            surface = match[1].to_i.to_s
            interval = match[2].to_i.abs * 10
            method = match[3]
          else
            method = match[1]
            surface = match[2].to_i.to_s
            interval = match[3].to_i.abs
          end
          if not ['bind', 'add', 'reduce', 'insert'].include?(method)
            next
          else
            if ['-1', '-2'].include?(surface)
              x = 0
              y = 0
            else
              if not match[4]
                x = 0
              else
                x = match[4].to_i
              end
              if not match[5]
                y = 0
              else
                y = match[5].to_i
              end
            end
            args = [x, y]
          end
          actor.add_pattern(surface, interval, method, args)
        end
      rescue # except ValueError as error:
        logging.error('seriko.py: ' + error.to_s)
        next
      end
      if actor.get_patterns().empty?
        ## FIXME
        #logging.error('seriko.py: animation group #{0:d} has no pattern (ignored)'.format(mayuna_id))
        next
      end
      mayuna << actor
    end
    temp = []
    for actor in mayuna
      temp << [actor.get_id(), actor]
    end
    mayuna = temp
    mayuna.sort()
    temp = []
    for actor_id, actor in mayuna
      temp << actor
    end
    mayuna = temp
    return mayuna
  end
end
