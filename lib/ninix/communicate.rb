# -*- coding: utf-8 -*-
#
#  communicate.py - ghost-to-ghost communication mechanism
#  Copyright (C) 2002-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#


module Communicate

  class Communicate

    def initialize
      @ghosts = {}
    end

    def rebuild_ghostdb(sakura, name='', s0=0, s1=10)
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
      return temp.join('\x01')
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
        side, new_id, new_w, new_h = references[2].split(',')
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
            flags = flags + ','
            flags = flags + 'break'
          end
          if sstp != nil ## FIXME: owned, remote
            if flags
              flags = flags + ','
            end
            flags = flags + 'sstp-send'
          end
          if notranslate
            if flags
              flags = flags + ','
          end
            flags = flags + 'notranslate'
          end
        end
        ## FIXME: plugin-script, plugin-event
        refs = []
        for value in references
          refs << value.to_s
        end
        refs = refs.join('\x01')
        #logging.debug("NOTIFY OTHER: {}, {}, {}, {}, {}, {}, {}".format(
        #        on_other_event, name, self_name, flags, event, script, refs))
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
          elsif communicate.include('\x01')
            to = name.split('\x01')
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

  class DUMMY_SAKURA

    def initialize(name)
      @name = name
    end

    def is_listening(event)
      return true
    end

    def enqueue_event(event, *references)
      print("NAME: ", @name, "\n")
      print("EVENT: ", event, "\n")
      print("REF: ", references, "\n")
    end

    def key
      return @name
    end
  end

  class TEST

    TEST_DATA = [['Sakura', 0, 10], 
                 ['Naru', 8, 11],
                 ['Busuko', 6666, 1212]]
    def initialize
      ghosts = []
      communicate = Communicate.new
      for ghost in TEST_DATA
        sakura = DUMMY_SAKURA.new(ghost[0])
        ghosts << [sakura, ghost]
        communicate.rebuild_ghostdb(sakura, *ghost)
      end
      print("COMMUNICATE:",
            communicate.get_otherghostname(ghosts.sample[1][0]), "\n")
      communicate.notify_all('TEST', [1, 'a', {22 => 'test'}])
      from = ghosts.sample
      to = ghosts.sample ## FIXME
      communicate.notify_other(from[1][0],
                               'OnOtherTest', to[1][0], from[1][0], '',
                               false, nil,
                               nil, false, '\h\s[10]test\e', [1, 2, 3, 'a'])
      communicate.notify_other(from[1][0],
                               'OnOtherTest', to[1][0], from[1][0], '',
                               false, '__SYSTEM_ALL_GHOST__',
                               nil, false, '\h\s[10]test\e', [1, 2, 3, 'a'])
    end
  end
end

Communicate::TEST.new
