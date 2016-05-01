# -*- coding: utf-8 -*-
#
#  communicate.rb - ghost-to-ghost communication mechanism
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

require_relative "logging"

module Communicate

  class Communicate

    def initialize
      @ghosts = {}
    end

    def rebuild_ghostdb(sakura, name: '', s0: 0, s1: 10)
      if @ghosts.include?(sakura)
        @ghosts.delete(sakura)
      end
      if name == nil
        return
      else
        @ghosts[sakura] = [name, s0, s1]
      end
    end

    def get_otherghostname(name)
      temp = []
      for value in @ghosts.values()
        if value[0] != name
          temp << value
        end
      end
      return temp.join(1.chr)
    end

    def notify_all(event, references)
      for sakura in @ghosts.keys()
        sakura.enqueue_event(event, *references)
      end
    end

    ON_OTHER_EVENT = {
        'OnBoot' => 'OnOtherGhostBooted',
        'OnFirstBoot' => 'OnOtherGhostBooted',
        'OnClose' => 'OnOtherGhostClosed',
        'OnGhostChanged' => 'OnOtherGhostChanged',
        'OnSurfaceChange' => 'OnOtherSurfaceChange',
        'OnVanishSelected' => 'OnOtherGhostVanished',
        'OnOverlap' => 'OnOtherOverlap',
        'OnOffscreen' => 'OnOtherOffscreen'
        }

    def notify_other(sakura_key,
                     event, name, selfname, shell_name,
                     flag_break, communicate,
                     sstp, notranslate, script, references)
      if script.empty? and not ON_OTHER_EVENT.include?(event)
        return
      end
      on_other_event = nil
      if ON_OTHER_EVENT.include?(event)
        if flag_break and ['OnClose', 'OnVanishSelected'].include?(event)
          # NOP
        else
          on_other_event = ON_OTHER_EVENT[event]
        end
      end
      if on_other_event == nil and not script.empty?
        on_other_event = 'OnOtherGhostTalk'
      end
      if on_other_event == nil
          return
      end
      if on_other_event == 'OnOtherGhostBooted'
        args = [selfname, script, name]
      elsif on_other_event == 'OnOtherGhostClosed'
        args = [selfname, script, name]
      elsif on_other_event == 'OnOtherGhostChanged'
        args = [references[0], selfname, references[1], script,
                references[2], name, references[7], shell_name]
      elsif on_other_event == 'OnOtherSurfaceChange'
        side, new_id, new_w, new_h = references[2].split(',', 4)
        prev_id = references[3]
        args = [name, selfname, side, new_id, prev_id, references[4]]
      elsif on_other_event == 'OnOtherGhostVanished'
        args = [selfname, script, name, shell_name]
      elsif on_other_event == 'OnOtherOverlap'
        args = [] ## FIXME
      elsif on_other_event == 'OnOtherOffscreen'
        args = [] ## FIXME
      elsif on_other_event == 'OnOtherGhostTalk'
        flags = ''
        if flag_break
          if !flags.empty?
            flags = (flags + ',')
            flags = (flags + 'break')
          end
          if sstp != nil ## FIXME: owned, remote
            if !flags.empty?
              flags = (flags + ',')
            end
            flags = (flags + 'sstp-send')
          end
          if notranslate
            if !flags.empty?
              flags = (flags + ',')
          end
            flags = (flags + 'notranslate')
          end
        end
        refs = []
        for value in references
          refs << value.to_s
        end
        refs = refs.join(1.chr)
        Logging::Logging.debug("NOTIFY OTHER: " \
                               + on_other_event.to_s + ", " \
                               + name.to_s + ", " \
                               + selfname.to_s + ", " \
                               + flags.to_s + ", " \
                               + event.to_s + ", " \
                               + script.to_s + ", " \
                               + refs.to_s)
        args = [name, selfname, flags, event, script, refs]
      else # XXX: should not reach here
        return
      end
      for sakura in @ghosts.keys()
        if sakura.key == sakura_key
          next
        end
        if communicate != nil
          if communicate == '__SYSTEM_ALL_GHOST__'
            sakura.enqueue_event('OnCommunicate', selfname, script)
            next
          elsif communicate.include?(1.chr)
            to = name.split(1.chr, 0)
            if to.include?(@ghosts[sakura][0])
              sakura.enqueue_event('OnCommunicate',
                                   selfname, script)
              next
            else
              if @ghosts[sakura][0] == communicate
                sakura.enqueue_event('OnCommunicate',
                                     selfname, script)
                next
              end
            end
          end
        end
        if sakura.is_listening(on_other_event)
          sakura.enqueue_event(on_other_event, *args)
        end
      end
    end
  end
end
