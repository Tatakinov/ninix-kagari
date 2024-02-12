# -*- coding: utf-8 -*-
#
#  communicate.rb - ghost-to-ghost communication mechanism
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2024 by Tatakinov
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
      @ghosts.delete(sakura)
      @ghosts[sakura] = [name, s0, s1] if not name.nil?
    end

    def get_otherghostname(name)
      @ghosts.values.select {|value| value[0] != name }.join(1.chr)
    end

    def notify_all(event, references)
      @ghosts.each_key do |sakura|
        sakura.enqueue_event(event, *references)
      end
    end

    def raise_other(ghost_name, sender, *args)
      ghosts_name = []
      if ghost_name.include?(1.chr)
        ghosts_name = ghost_name.split(1.chr, 0)
      end
      for sakura in @ghosts.keys()
        next if sakura.key == sender
        if ghosts_name.include?(@ghosts[sakura][0])
          sakura.enqueue_event(*args)
        elsif ghosts_name.empty?
          if ghost_name == '__SYSTEM_ALL_GHOST__' or ghost_name == @ghosts[sakura][0]
            sakura.enqueue_event(*args)
          end
        end
      end
    end

    ON_OTHER_EVENT = {
      'OnBoot'           => 'OnOtherGhostBooted',
      'OnFirstBoot'      => 'OnOtherGhostBooted',
      'OnClose'          => 'OnOtherGhostClosed',
      'OnGhostChanged'   => 'OnOtherGhostChanged',
      'OnSurfaceChange'  => 'OnOtherSurfaceChange',
      'OnVanishSelected' => 'OnOtherGhostVanished',
      'OnOverlap'        => 'OnOtherOverlap',
      'OnOffscreen'      => 'OnOtherOffscreen'
    }

    def notify_other(sakura_key,
                     event, name, selfname, shell_name,
                     flag_break, communicate,
                     sstp, notranslate, script, references)
      return if script.empty? and not ON_OTHER_EVENT.include?(event)
      on_other_event = nil
      if ON_OTHER_EVENT.include?(event)
        if flag_break and ['OnClose', 'OnVanishSelected'].include?(event)
          # NOP
        else
          on_other_event = ON_OTHER_EVENT[event]
        end
      end
      if on_other_event.nil? and not script.empty?
        on_other_event = 'OnOtherGhostTalk'
      end
      return if on_other_event.nil?
      args =
        case on_other_event
        when 'OnOtherGhostBooted'
          [selfname, script, name]
        when 'OnOtherGhostClosed'
          [selfname, script, name]
        when 'OnOtherGhostChanged'
          [references[0], selfname, references[1], script,
           references[2], name, references[7], shell_name]
        when 'OnOtherSurfaceChange'
          side, new_id, new_w, new_h = references[2].split(',', 4)
          prev_id = references[3]
          [name, selfname, side, new_id, prev_id, references[4]]
        when 'OnOtherGhostVanished'
          [selfname, script, name, shell_name]
        when 'OnOtherOverlap'
          [] ## FIXME
        when 'OnOtherOffscreen'
          [] ## FIXME
        when 'OnOtherGhostTalk'
          flags = ''
          if flag_break
            if !flags.empty?
              flags = (flags + ',')
              flags = (flags + 'break')
            end
          end
          if not sstp.nil? ## FIXME: owned, remote
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
          refs = references.each {|value| value.to_s}.join(1.chr)
          Logging::Logging.debug(
            "NOTIFY OTHER: " \
            "#{on_other_event}, #{name}, #{selfname}, #{flags}, " \
            "#{event}, #{script}, #{refs}")
          [name, selfname, flags, event, script, refs]
        else # XXX: should not reach here
          return
        end
      for sakura in @ghosts.keys()
        next if sakura.key == sakura_key
        if not communicate.nil?
          if communicate == '__SYSTEM_ALL_GHOST__'
            sakura.enqueue_event('OnCommunicate', selfname, script)
            next
          elsif communicate.include?(1.chr)
            to = name.split(1.chr, 0)
            if to.include?(@ghosts[sakura][0])
              sakura.enqueue_event('OnCommunicate',
                                   selfname, script)
              next
            end
          else
            if @ghosts[sakura][0] == communicate
              sakura.enqueue_event('OnCommunicate',
                                   selfname, script)
              next
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
