# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"
require "gst"
require "cgi"
require "uri"

require_relative "surface"
require_relative "balloon"
require_relative "dll"
require_relative "makoto"
require_relative "pix"
require_relative "script"
require_relative "version"
require_relative "update"
require_relative "home"
require_relative "metamagic"
require_relative "logging"

module Sakura

  class ShellMeme < MetaMagic::Meme

    def initialize(key)
      super(key)
      @parent = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def create_menuitem(data)
      shell_name = data[0]
      subdir = data[1]
      base_path = @parent.handle_request('GET', 'get_prefix')
      thumbnail_path = File.join(base_path, 'shell',
                                 subdir, 'thumbnail.png')
      if not File.exist?(thumbnail_path)
        thumbnail_path = nil
      end
      return @parent.handle_request(
        'GET', 'create_shell_menuitem', shell_name, @key,
        thumbnail_path)
    end

    def delete_by_myself()
      @parent.handle_request('NOTIFY', 'delete_shell', @key)
    end
  end

  class Sakura
    attr_reader :key, :cantalk, :last_script

    include GetText

    bindtextdomain("ninix-aya")
    
    BALLOON_LIFE   = 10  # [sec] (0: never closed automatically)
    SELECT_TIMEOUT = 15  # [sec]
    PAUSE_TIMEOUT  = 30  # [sec]
    SILENT_TIME    = 15  # [sec]
    # script modes
    BROWSE_MODE        = 1
    SELECT_MODE        = 2
    PAUSE_MODE         = 3
    WAIT_MODE          = 4 
    PAUSE_NOCLEAR_MODE = 5
    # script origins
    FROM_SSTP_CLIENT = 1
    FROM_GHOST       = 2
 
    def initialize
      @parent = nil
      @sstp_handle = nil
      @sstp_entry_db = nil
      @sstp_request_handler = nil
      # error = 'loose'(default) or 'strict'
      @script_parser = Script::Parser.new(:error => 'loose')
      @char = 2 # 'sakura' and 'kero'
      @script_queue = []
      @script_mode = BROWSE_MODE
      @script_post_proc = []
      @script_finally = []
      @script_position = 0
      @event_queue = []
      @__current_script = ''
      @__balloon_life = 0
      @__surface_life = 0
      @__boot = [false, false]
      @surface_mouse_motion = nil ## FIXME
      @time_critical_session = false
      @lock_repaint = false
      @passivemode = false
      @__running = false
      @anchor = nil
      @clock = [0, 0]
      @synchronized_session = []
      @force_quit = false
      ##
      @old_otherghostname = nil ## FIXME
      # create vanish dialog
      @__vanish_dialog = VanishDialog.new
      @__vanish_dialog.set_responsible(self)
      @cantalk = true
      @__sender = 'ninix-aya'
      @__charset = 'Shift_JIS'
      saori_lib = DLL::Library.new('saori', :sakura => self)
      @__dll = DLL::Library.new('shiori', :saori_lib => saori_lib)
      @__temp_mode = 0
      @__observers = {}
      @__listening = {
        'OnOtherGhostBooted' => true,
        'OnOtherGhostClosed' => true,
        'OnOtherGhostChanged' => true,
        'OnOtherSurfaceChange' => false,
        'OnOtherGhostVanished' => true,
        'OnOtherGhostTalk' => false,
        'OnOtherOverlap' => true,
        'OnOtherOffscreen' => true
      }
      @balloon = Balloon::Balloon.new
      @balloon.set_responsible(self)
      @surface = Surface::Surface.new
      @surface.set_responsible(self)
      keep_silence(false)
      @updateman = Update::NetworkUpdate.new()
      @updateman.set_responsible(self)
      if Gst != nil
        @audio_player = Gst::ElementFactory.make('playbin', 'player')
        fakesink = Gst::ElementFactory.make('fakesink', 'fakesink')
        @audio_player.set_property('video-sink', fakesink)
        bus = @audio_player.bus
        bus.add_signal_watch()
        bus.signal_connect('message') do |bus, message|
          on_audio_message(bus, message)
        end
      else
        @audio_player = nil
      end
      @audio_loop = false
      @reload_event = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      #assert ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
        'lock_repaint' => "get_lock_repaint"
      }
      if not handlers.include?(event)
        if Sakura.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = @parent.handle_request(
            event_type, event, *arglist)
        end
      else
        result = method(handlers[event]).call(*arglist)
      end
      if event_type == 'GET'
        return result
      end
    end

    def get_lock_repaint(*args)
      return @lock_repaint
    end

    def attach_observer(observer)
      if not @__observers.include?(observer)
        @__observers[observer] = 1
      end
    end

    def notify_observer(event, args: nil)
      if not args
        args = []
      end
      for observer in @__observers.keys
        observer.observer_update(event, args)
      end
    end

    def detach_observer(observer)
      if @__observers.include?(observer)
        @__observers.delete(observer)
      end
    end

    def delete_shell(key)
      #assert @shells.include?(key)
      @shells.delete(key)
    end

    def notify_installedshellname()
      installed = []
      for key in @shells.keys
        installed << @shells[key].baseinfo[0]
      end
      notify_event('installedshellname', *installed)
    end

    def get_shell_menu()
      current_key = get_current_shell()
      for key in @shells.keys
        menuitem = @shells[key].menuitem
        menuitem.set_sensitive(key != current_key) # not working
      end
      return @shell_menu
    end

    def new_(desc, shiori_dir, use_makoto, surface_set, prefix,
             shiori_dll, shiori_name) ## FIXME
      @shiori = nil
      @desc = desc
      @shiori_dir = shiori_dir
      @use_makoto = use_makoto
      @prefix = prefix
      @shells = {} # Ordered Hash
      shell_menuitems = {} # Ordered Hash
      for key, value in surface_set
        meme = ShellMeme.new(key)
        meme.set_responsible(self)
        @shells[key] = meme
        meme.baseinfo = value
        shell_menuitems[key] = meme.menuitem
      end
      @shell_menu = @parent.handle_request(
        'GET', 'create_shell_menu', shell_menuitems)
      @shiori_dll = shiori_dll
      @shiori_name = shiori_name
      name = [shiori_dll, shiori_name]
      @shiori = @__dll.request(name)
      char = 2
      while @desc.get(sprintf('char%d.seriko.defaultsurface', char)) != nil
        char += 1
      end
      if char > 2
        @char = char
      end
      # XXX
      if @desc.get('name') == 'BTH小っちゃいってことは便利だねっ'
        set_SSP_mode(true)
      else
        set_SSP_mode(false)
      end
      @last_script = nil
      @status_icon = Gtk::StatusIcon.new
      @status_icon.set_title(get_name(:default => ''))
      @status_icon.set_visible(false)
    end

    def set_SSP_mode(flag) # XXX
      if flag
        @__sender = 'SSP'
      else
        @__sender = 'ninix-aya'
      end
    end

    def save_history()
      path = File.join(get_prefix(), 'HISTORY')
      begin
        open(path, 'w') do |file|
          file.write("time, " + @ghost_time.to_s + "\n")
          file.write("vanished_count, " + @vanished_count.to_s + "\n")
        end
      rescue IOError, SystemCallError => e
        Logging::Logging.error('cannot write ' + path)
      end
    end

    def save_settings()
      path = File.join(get_prefix(), 'SETTINGS')
      begin
        open(path, 'w') do |file|
          if @balloon_directory != nil
            file.write("balloon_directory, " + @balloon_directory + "\n")
          end
          if @shell_directory != nil
            file.write("shell_directory, " + @shell_directory + "\n")
          end
        end
      rescue IOError, SystemCallError => e
        Logging::Logging.error('cannot write ' + path)
      end
    end

    def load_history()
      path = File.join(get_prefix(), 'HISTORY')
      if File.exist?(path)
        ghost_time = 0
        ghost_vanished_count = 0
        begin
          f = open(path, 'r')
          for line in f
            if not line.include?(',')
              next
            end
            key, value = line.split(',', 2)
            key = key.strip()
            if key == 'time'
              begin
                ghost_time = Integer(value.strip())
              rescue
                #pass
              end
            elsif key == 'vanished_count'
              begin
                ghost_vanished_count = Integer(value.strip())
              rescue
                #pass
              end
            end
          end
        rescue IOError => e
          Logging::Logging.error('cannot read ' + path)
          ghost_time = 0
          vanished_count = 0
        end
        @ghost_time = ghost_time
        @vanished_count = ghost_vanished_count
      end
    end
 
    def load_settings()
      path = File.join(get_prefix(), 'SETTINGS')
      if File.exist?(path)
        balloon_directory = nil
        shell_directory = nil
        begin
          f = open(path, 'r')
          for line in f
            if not line.include?(',')
              next
            end
            key, value = line.split(',', 2)
            if key.strip() == 'balloon_directory'
              balloon_directory = value.strip()
            end
            if key.strip() == 'shell_directory'
              shell_directory = value.strip()
            end
          end
        rescue IOError => e
          Logging::Logging.error('cannot read ' + path)
        end
        @balloon_directory = balloon_directory
        @shell_directory = shell_directory
      else
        @balloon_directory = nil
        @shell_directory = nil
      end
    end

    def load_shiori()
      if @shiori and @shiori.load(:dir => @shiori_dir) != 0
        if @shiori.respond_to?("show_description")
          @shiori.show_description()
        end
      else
        Logging::Logging.error(get_selfname + ' cannot load SHIORI(' + @shiori_name + ')')
      end
      @__charset = 'Shift_JIS' # default
      get_event_response('OnInitialize', :event_type => 'NOTIFY')
      get_event_response('basewareversion',
                         Version.VERSION,
                         'ninix-aya',
                         Version.NUMBER,
                         :event_type => 'NOTIFY')
    end

    def finalize()
      if not @script_finally.empty? # XXX
        for proc_obj in @script_finally
          proc_obj.call(:flag_break => false)
        end
        @script_finally = []
      end
      if @__temp_mode == 0
        get_event_response('OnDestroy', :event_type => 'NOTIFY')
        @shiori.unload()
      end
      stop()
    end

    def enter_temp_mode()
      if @__temp_mode == 0
        @__temp_mode = 2
      end
    end

    def leave_temp_mode()
      @__temp_mode = 0
    end

    def is_listening(key)
      if not @__listening.include?(key)
        return false
      end
      return @__listening[key]
    end

    def on_audio_message(bus, message)
      if message == nil # XXX: workaround for Gst Version < 0.11
        if @script_mode == WAIT_MODE
          @script_mode = BROWSE_MODE
        end
        return
      end
      t = message.type
      if t == Gst::MessageType::EOS
        @audio_player.set_state(Gst::State::NULL)
        if @script_mode == WAIT_MODE
          ##assert not @audio_loop
          @script_mode = BROWSE_MODE
        end
        if @audio_loop
          @audio_player.set_state(Gst::State::PLAYING)
        end
      elsif t == Gst::MessageType::ERROR
        @audio_player.set_state(Gst::State::NULL)
        err, debug = message.parse_error()
        Logging::Logging.error('Error: ' + err + ', ' + debug)
        @audio_loop = false
      end
    end

    def set_surface(desc, surface_alias, surface, name, surface_dir, tooltips, seriko_descript)
      default_sakura = @desc.get('sakura.seriko.defaultsurface', :default => '0')
      default_kero = @desc.get('kero.seriko.defaultsurface', :default => '10')
      @surface.new_(desc, surface_alias, surface, name, surface_dir, tooltips, seriko_descript,
                   default_sakura, default_kero)
      for side in 2..@char-1
        default = @desc.get('char' + side.to_s + '.seriko.defaultsurface')
        @surface.add_window(side, default)
      end
      icon = @desc.get('icon', :default => nil)
      if icon != nil
        icon_path = File.join(@shiori_dir, icon)
        if not File.exist?(icon_path)
          icon_path = nil
        end
      else
        icon_path = nil
      end
      @surface.set_icon(icon_path)
    end

    def set_balloon(desc, balloon)
      @balloon.new_(desc, balloon)
      for side in 2..@char-1
        @balloon.add_window(side)
      end
      for side in 0..@char-1
        balloon_win = @balloon.get_window(side)
        surface_win = @surface.get_window(side)
        balloon_win.set_transient_for(surface_win)
      end
    end

    def update_balloon_offset(side, x_delta, y_delta)
      if side >= @char
        return
      end
      ox, oy = @surface.window[side].get_balloon_offset # without scaling
      direction = @balloon.window[side].direction
      sx, sy = get_surface_position(side)
      if direction == 0 # left
        nx = ox + x_delta
      else
        w, h = @surface.get_surface_size(side)
        nx = ox - x_delta
      end
      ny = oy + y_delta
      @surface.set_balloon_offset(side, [nx, ny])
    end

    def enqueue_script(event, script, sender, handle,
                       host, show_sstp_marker, use_translator,
                       db: nil, request_handler: nil)
      if @script_queue.empty? and \
        not @time_critical_session and not @passivemode
        if @sstp_request_handler
          @sstp_request_handler.send_sstp_break()
          @sstp_request_handler = nil
        end
        reset_script(:reset_all => true)
      end
      @script_queue << [event, script, sender, handle, host,
                        show_sstp_marker, use_translator,
                        db, request_handler]
    end

    RESET_ENQUEUE_EVENT = ['OnGhostChanging', 'OnShellChanging', 'OnVanishSelected']

    def check_event_queue()
      return (not @event_queue.empty?)
    end

    def enqueue_event(event, *arglist, proc_obj: nil) ## FIXME
      if RESET_ENQUEUE_EVENT.include?(event)
        reset_script(:reset_all => true)
      end
      @event_queue << [event, arglist, proc_obj]
    end

    EVENT_SCRIPTS = {
        'OnUpdateBegin' => \
        ['\t\h\s[0]',
         _('Network Update has begun.'),
         '\e'].join(''),
        'OnUpdateComplete' => \
        ['\t\h\s[5]',
         _('Network Update completed successfully.'),
         '\e'].join(''),
        'OnUpdateFailure' => \
        ['\t\h\s[4]',
         _('Network Update failed.'),
         '\e'].join(''),
        }

    def handle_event() ## FIXME
      while not @event_queue.empty?
        event, arglist, proc_obj = @event_queue.shift
        if EVENT_SCRIPTS.include?(event)
          default = EVENT_SCRIPTS[event]
        else
          default = nil
        end
        if notify_event(event, *arglist, :default => default)
          if proc_obj != nil
            @script_post_proc << proc_obj
          end
          return true
        elsif proc_obj != nil
          proc_obj.call()
          return true
        end
      end
      return false
    end

    def is_running()
      return @__running
    end

    def is_paused()
      return [PAUSE_MODE, PAUSE_NOCLEAR_MODE].include?(@script_mode)
    end

    def is_talking()
      if not @processed_script.empty? or not @processed_text.empty?
        return true
      else
        return false
      end
    end

    def busy(check_updateman: true)
      return (@time_critical_session or \
              @balloon.user_interaction or \
              not @event_queue.empty? or \
              @passivemode or \
              @sstp_request_handler != nil or \
              (check_updateman and @updateman.is_active()))
    end

    def get_silent_time()
      return @silent_time
    end

    def keep_silence(quiet)
      if quiet
        @silent_time = Time.new.to_f
      else
        @silent_time = 0
        reset_idle_time()
      end
    end

    def get_idle_time()
      now = Time.new.to_f
      idle = now - @idle_start
      return idle
    end

    def reset_idle_time()
      @idle_start = Time.new.to_f
    end

    def notify_preference_changed() ## FIXME
      @balloon.reset_fonts() ## FIXME
      @surface.reset_surface()
      notify_observer('set scale') ## FIXME
      @balloon.reset_balloon()
    end

    def get_surface_position(side)
      result = @surface.get_position(side)
      if result != nil
        return result
      else
        return [0, 0]
      end
    end

    def set_balloon_position(side, base_x, base_y)
      @balloon.set_position(side, base_x, base_y)
    end

    def set_balloon_direction(side, direction)
      if side >= @char
        return
      end
      @balloon.window[side].direction = direction
    end

    def get_balloon_size(side)
      result = @balloon.get_balloon_size(side)
      if result != nil
        return result
      else
        return [0, 0]
      end
    end

    def get_balloon_windowposition(side)
      return @balloon.get_balloon_windowposition(side)
    end

    def get_balloon_position(side)
      result = @balloon.get_position(side)
      if result != nil
        return result
      else
        return [0, 0]
      end
    end

    def balloon_is_shown(side)
      if @balloon and @balloon.is_shown(side)
        return true
      else
        return false
      end
    end

    def surface_is_shown(side)
      if @surface and @surface.is_shown(side)
        return true
      else
        return false
      end
    end

    def is_URL(s)
      return (s.start_with?('http://') or \
              s.start_with?('ftp://') or \
              s.start_with?('file:/'))
    end

    def is_anchor(link_id)
      if link_id.length == 2 and link_id[0] == 'anchor'
        return true
      else
        return false
      end
    end

    def vanish()
      if busy()
        Gdk.beep() ## FIXME
        return
      end
      notify_event('OnVanishSelecting')
      @__vanish_dialog.show()
    end

    def vanish_by_myself(next_ghost)
      @vanished_count += 1
      @ghost_time = 0
      @parent.handle_request('NOTIFY', 'vanish_sakura', self, next_ghost)
    end

    def get_ifghost()
      return [get_selfname(), ',', get_keroname()].join('')
    end

    def ifghost(ifghost)
      names = get_ifghost()
      name = get_selfname()
      return [name, names].include?(ifghost)
    end

    def get_name(default: _('Sakura&Unyuu'))
      return @desc.get('name', :default => default)
    end

    def get_username()
      return (getstring('username') or \
              @surface.get_username() or \
              @desc.get('user.defaultname', :default => _('User')))
    end

    def get_selfname(default: _('Sakura'))
      return (@surface.get_selfname() or \
              @desc.get('sakura.name', :default => default))
    end

    def get_selfname2()
      return (@surface.get_selfname2() or \
              @desc.get('sakura.name2', :default => _('Sakura')))
    end

    def get_keroname()
      return (@surface.get_keroname() or \
              @desc.get('kero.name', :default => _('Unyuu')))
    end

    def get_friendname()
      return (@surface.get_friendname() or \
              @desc.get('sakura.friend.name', :default => _('Tomoyo')))
    end

    def getaistringrandom() # obsolete
      result = get_event_response('OnAITalk')
      return translate(result)
    end

    def getdms()
      result = get_event_response('dms')
      return translate(result)
    end

    def getword(word_type)
      result = get_event_response(word_type)
      return translate(result)
    end

    def getstring(name)
      return get_event_response(name)
    end

    def translate(s)
      if s != nil
        if @use_makoto
          s = Makoto.execute(s)
        else
          r = get_event_response('OnTranslate', s, :translate => 0)
          if not r.empty?
            s = r
          end
        end
      end
      return s
    end

    def get_value(response) # FIXME: check return code
      result = {}
      to = nil
      for line in response.force_encoding(@__charset).split(/\r?\n/, 0)
        line = line.encode("UTF-8", :invalid => :replace, :undef => :replace).strip()
        if line.empty?
          next
        end
        if not line.include?(':')
          next
        end
        key, value = line.split(':', 2)
        key = key.strip()
        if key == 'Charset'
          charset = value.strip()
          if charset != @__charset
            if not Encoding.name_list.include?(charset)
              Logging::Logging.warning(
                'Unsupported charset ' + charset)
            else
              @__charset = charset
            end
          end
        end
        result[key] = value
      end
      for key in result.keys
        result[key].strip!
      end
      if result.include?('Reference0')
        to = result['Reference0']
      end
      if result.include?('Value')
        return result['Value'], to
      else
        return nil, to
      end
    end

    def get_event_response_with_communication(event, *arglist,
                                              event_type: 'GET', translate: 1)
      if @__temp_mode == 1
        return ''
      end
      ref = arglist
      header = [event_type.to_s, " SHIORI/3.0\r\n",
                "Sender: ", @__sender.to_s, "\r\n",
                "ID: ", event.to_s, "\r\n",
                "SecurityLevel: local\r\n",
                "Charset: ", @__charset.to_s, "\r\n"].join("")
      for i in 0..ref.length-1
        value = ref[i]
        if value != nil
          value = value.to_s
          header = [header,
                    "Reference", i.to_s, ": ",
                    value, "\r\n"].join("")
        end
      end
      header = [header, "\r\n"].join("")
      header = header.encode(@__charset, :invalid => :replace, :undef => :replace)
      response = @shiori.request(header)
      if event_type != 'NOTIFY' and @cantalk
        result, to = get_value(response)
        if translate != 0
          result = translate(result)
        end
      else
        result, to = '', nil
      end
      if result == nil
        result = ''
      end
      if to and not result.empty?
        communication = to
      else
        communication = nil
      end
      return result, communication
    end

    def get_event_response(event, *arglist, event_type: 'GET', translate: 1)
      result, communication = get_event_response_with_communication(
                event, *arglist,
                :event_type => event_type, :translate => translate)
      return result
    end

    ###   CALLBACK   ###
    def notify_start(init, vanished, ghost_changed,
                     name, prev_name, prev_shell, path, last_script,
                     abend: nil)
      if @__temp_mode != 0
        default = nil
      else
        default = Version.VERSION_INFO
      end
      if init
        if @ghost_time == 0
          if not notify_event('OnFirstBoot', @vanished_count,
                              nil, nil, nil, nil, nil, nil,
                              @surface.name)
            if abend != nil
              notify_event('OnBoot', @surface.name,
                           nil, nil, nil, nil, nil,
                           'halt', abend, :default => default)
            else
              notify_event('OnBoot', @surface.name,
                           :default => default)
            end
          end
        else
          if abend != nil
            notify_event('OnBoot', @surface.name,
                         nil, nil, nil, nil, nil,
                         'halt', abend, :default => default)
          else
            notify_event('OnBoot', @surface.name,
                         :default => default)
          end
        end
        left, top, scrn_w, scrn_h = Pix.get_workarea()
        notify_event('OnDisplayChange',
                     Gdk::Visual.best_depth,
                     scrn_w, scrn_h, :event_type => 'NOTIFY')
      elsif vanished
        if @ghost_time == 0
          if notify_event('OnFirstBoot', @vanished_count,
                          nil, nil, nil, nil, nil, nil,
                          @surface.name)
            return
          end
        elsif notify_event('OnVanished', name)
          return
        elsif notify_event('OnGhostChanged', name, last_script,
                           prev_name, nil, nil, nil, nil,
                           pref_shell)
          return
        end
        if abend != nil
          notify_event('OnBoot', @surface.name,
                       nil, nil, nil, nil, nil, nil,
                       'halt', abend, :default => default)
        else
          notify_event('OnBoot', @surface.name, :default => default)
        end
      elsif ghost_changed
        if @ghost_time == 0
          if notify_event('OnFirstBoot', @vanished_count,
                          nil, nil, nil, nil, nil, nil,
                          @surface.name)
            return
          end
        elsif notify_event('OnGhostChanged', name, last_script,
                           prev_name, nil, nil, nil, nil,
                           prev_shell)
          return
        end
        if abend != nil
          notify_event('OnBoot', @surface.name,
                       nil, nil, nil, nil, nil,
                       'halt', abend, :default => default)
        else
          notify_event('OnBoot', @surface.name, :default => default)
        end
      else
        #pass ## FIXME
      end
    end

    def notify_vanish_selected()
      proc_obj = lambda {
        @vanished_count += 1
        @ghost_time = 0
        GLib::Idle.add{
          @parent.handle_request('NOTIFY', 'vanish_sakura', self, nil)
        }
      }
      enqueue_event('OnVanishSelected', :proc_obj => proc_obj)
      @vanished = true ## FIXME
    end

    def notify_vanish_canceled()
      notify_event('OnVanishCancel')
    end

    def notify_iconified()
      @cantalk = false
      @parent.handle_request('NOTIFY', 'select_current_sakura')
      if not @passivemode
        reset_script(:reset_all => true)
        stand_by(true)
        notify_event('OnWindowStateMinimize')
      end
      notify_observer('iconified')
    end

    def notify_deiconified()
      if not @cantalk
        @cantalk = true
        @parent.handle_request('NOTIFY', 'select_current_sakura')
        if not @passivemode
          notify_event('OnWindowStateRestore')
        end
      end
      notify_observer('deiconified')
    end

    def notify_link_selection(link_id, text, number)
      if @script_origin == FROM_SSTP_CLIENT and \
        @sstp_request_handler != nil
        @sstp_request_handler.send_answer(text)
        @sstp_request_handler = nil
      end
      if is_anchor(link_id)
        notify_event('OnAnchorSelect', link_id[1])
      elsif is_URL(link_id)
        browser_open(link_id)
        reset_script(:reset_all => true)
        stand_by(false)
      elsif @sstp_entry_db
        # leave the previous sstp message as it is
        start_script(@sstp_entry_db.get(link_id, :default => '\e'))
        @sstp_entry_db = nil
      elsif not notify_event('OnChoiceSelect', link_id, text, number)
        reset_script(:reset_all => true)
        stand_by(false)
      end
    end

    def browser_open(url)
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        system "start #{url}"
      elsif RbConfig::CONFIG['host_os'] =~ /darwin/
        system "open #{url}"
      elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
        system "xdg-open #{url}"
      end
    end

    def notify_site_selection(args)
      title, url = args
      if is_URL(url)
        browser_open(url)
      end
      enqueue_event('OnRecommandedSiteChoice', title, url)
    end

    def notify_surface_click(button, click, side, x, y)
      if button == 1 and click == 1
        raise_all()
      end
      if @vanished
        if side == 0 and button == 1
          if @sstp_request_handler
            @sstp_request_handler.send_sstp_break()
            @sstp_request_handler = nil
          end
          reset_script(:reset_all => true)
          notify_event('OnVanishButtonHold', :default => '\e')
          @vanished = false
        end
        return
      end
      if @updateman.is_active()
        if button == 1 and click == 2
          @updateman.interrupt()
        end
        return
      end
      if @time_critical_session
        return
      elsif click == 1
        if @passivemode and \
          not @processed_script.empty?
          return
        end
        part = @surface.get_touched_region(side, x, y)
        if [1, 2, 3].include?(button)
          num_button = [0, 2, 1][button - 1]
          if not notify_event('OnMouseUp',
                              x, y, 0, side, part, num_button,
                              'mouse') # FIXME
            if button == 2
              if notify_event(
                   'OnMouseUpEx',
                   x, y, 0, side, part, 'middle',
                   'mouse') # FIXME
                return
              end
              if notify_event('OnMouseClickEx',
                              x, y, 0, side, part, 'middle',
                              'mouse') # FIXME
                return
              end
            end
            notify_event('OnMouseClick',
                         x, y, 0, side, part, num_button,
                         'mouse') # FIXME
          end
        elsif [8, 9].include?(button)
          ex_button = {
            2 => 'middle',
            8 => 'xbutton1',
            9 => 'xbutton2'
          }[button]
          if not notify_event('OnMouseUpEx',
                              x, y, 0, side, part, ex_button,
                              'mouse') # FIXME
            notify_event('OnMouseClickEx',
                         x, y, 0, side, part, ex_button,
                         'mouse') # FIXME
          end
        end
      elsif @passivemode
        return
      elsif [1, 3].include?(button) and click == 2
        if @sstp_request_handler
          @sstp_request_handler.send_sstp_break()
          @sstp_request_handler = nil
        end
        part = @surface.get_touched_region(side, x, y)
        num_button = [0, 2, 1][button - 1]
        notify_event('OnMouseDoubleClick',
                     x, y, 0, side, part, num_button,
                     'mouse') # FIXME
      elsif [2, 8, 9].include?(button) and click == 2
        part = @surface.get_touched_region(side, x, y)
        ex_button = {
          2 => 'middle',
          8 => 'xbutton1',
          9 => 'xbutton2'
        }[button]
        notify_event('OnMouseDoubleClickEx',
                     x, y, 0, side, part, ex_button,
                     'mouse') # FIXME
      end
    end

    def notify_balloon_click(button, click, side)
      if @script_mode == PAUSE_MODE
        @script_mode = BROWSE_MODE
        @balloon.clear_text_all()
        @balloon.hide_all()
        @script_side = 0
      elsif @script_mode == PAUSE_NOCLEAR_MODE
        @script_mode = BROWSE_MODE
      elsif button == 1 and click == 1
        raise_all()
      end
      if @vanished
        return
      end
      if @updateman.is_active()
        if button == 1 and click == 2
          @updateman.interrupt()
        end
        return
      end
      if @time_critical_session
        @time_critical_session = false
        return
      elsif @passivemode
        return
      elsif button == 1 and click == 2
        if @sstp_request_handler
          @sstp_request_handler.send_sstp_break()
          @sstp_request_handler = nil
          reset_script(:reset_all => true)
          stand_by(false)
        end
      elsif button == 3 and click == 1
        if @sstp_request_handler
          @sstp_request_handler.send_sstp_break()
          @sstp_request_handler = nil
        end
        if is_talking()
          notify_event('OnBalloonBreak',
                       @__current_script, side,
                       @script_position)
        else
          notify_event('OnBalloonClose', @__current_script)
          reset_script(:reset_all => true)
          stand_by(false)
        end
      end
    end

    def notify_surface_mouse_motion(side, x, y, part)
      if @surface_mouse_motion != nil
        return
      end
      if not part.empty?
        @surface_mouse_motion = [side, x, y, part]
      else
        @surface_mouse_motion = nil
      end
    end

    def notify_user_teach(word)
      if word != nil
        script = translate(get_event_response('OnTeach', word))
        if not script.empty?
          start_script(script)
          @balloon.hide_sstp_message()
        end
      end
    end


    MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    BOOT_EVENT = ['OnBoot', 'OnFirstBoot', 'OnGhostChanged', 'OnShellChanged',
                  'OnUpdateComplete']
    RESET_NOTIFY_EVENT = ['OnVanishSelecting', 'OnVanishCancel'] ## FIXME

    def notify_event(event, *arglist, event_type: 'GET', default: nil)
      if @time_critical_session and event.start_with?('OnMouse')
        return false
      end
      if RESET_NOTIFY_EVENT.include?(event)
        reset_script(:reset_all => true)
      end
      result = get_event_response_with_communication(event, *arglist,
                                                     :event_type => event_type)
      if result != nil
        script, communication = result
      else
        script, communication = [default, nil]
      end
      if not script.empty? or (script.empty? and event != 'OnSecondChange')
        t = Time.new.localtime
        m = MONTH_NAMES[t.month - 1]
        Logging::Logging.debug(
          sprintf("\n[%02d/%s/%d:%02d:%02d:%02d %+05d]",
                  t.day, m, t.year, t.hour, t.min, t.sec, t.utc_offset / 36))
        Logging::Logging.debug('Event: ' + event)
        for n in 0..arglist.length-1
          value = arglist[n]
          if value != nil
            value = value.to_s
            Logging::Logging.debug(
              'Reference' + n.to_s + ': ' + value)
          end
        end
      end
      if event == 'OnCloseAll'
        @force_quit = true
        if script.empty? # fallback
          result = get_event_response_with_communication(
            'OnClose', *arglist, :event_type => event_type)
          if result != nil
            script, communication = result
          else
            script, communication = [default, nil]
          end
        end
        if not script.empty?
          start_script(script)
          @balloon.hide_sstp_message()
        end
        return true
      end
      if event == 'OnClose' and arglist[0] == 'shutdown' # XXX
        @force_quit = true
      end
      if script.empty? # an empty script is ignored
        if BOOT_EVENT.include?(event)
          surface_bootup()
        end
        if event == 'OnMouseClick' and arglist[5] == 1
          @parent.handle_request(
            'NOTIFY', 'open_popup_menu', self, arglist[5], arglist[3])
        end
        @parent.handle_request(
          'NOTIFY', 'notify_other', @key,
          event, get_name(:default => ''),
          get_selfname(:default => ''),
          get_current_shell_name(),
          false, communication,
          nil, false, script, arglist)
        return false
      end
      Logging::Logging.debug('=> "' + script + '"')
      if @__temp_mode == 2
        @parent.handle_request('NOTIFY', 'reset_sstp_flag')
        leave_temp_mode()
      end
      if @passivemode and \
        (event == 'OnSecondChange' or event == 'OnMinuteChange')
        return false
      end
      start_script(script)
      @balloon.hide_sstp_message()
      if BOOT_EVENT.include?(event)
        @script_finally << lambda {|flag_break: false| @surface_bootup }
      end
      proc_obj = lambda {|flag_break: false|
        @parent.handle_request(
          'NOTIFY', 'notify_other', @key,
          event, get_name(:default => ''),
          get_selfname(:default => ''),
          get_current_shell_name(),
          flag_break, communication,
          nil, false, script, arglist)
      }
      @script_finally << proc_obj
      return true
    end

    def get_prefix()
      return @prefix
    end

    def stick_window(flag)
      @surface.window_stick(flag)
    end

    def toggle_bind(args)
      @surface.toggle_bind(args)
    end

    def get_menu_pixmap()
      path_background, path_sidebar, path_foreground, \
      align_background, align_sidebar, align_foreground = \
                                       @surface.get_menu_pixmap()
      top_dir = @surface.prefix
      ghost_dir = File.join(get_prefix(), 'ghost', 'master')
      name = getstring('menu.background.bitmap.filename')
      if not name.empty?
        name = name.gsub("\\", '/')
        path_background = File.join(top_dir, name)
      end
      if path_background == nil
        path_background = File.join(ghost_dir, 'menu_background.png')
      end
      if not File.exist?(path_background)
        path_background = nil
      end
      name = getstring('menu.sidebar.bitmap.filename')
      if not name.empty?
        name = name.gsub("\\", '/')
        path_sidebar = File.join(top_dir, name)
      end
      if path_sidebar == nil
        path_sidebar = File.join(ghost_dir, 'menu_sidebar.png')
      end
      if not File.exist?(path_sidebar)
        path_sidebar = nil
      end
      name = getstring('menu.foreground.bitmap.filename')
      if not name.empty?
        name = name.gsub("\\", '/')
        path_foreground = File.join(top_dir, name)
      end
      if path_foreground == nil
        path_foreground = File.join(ghost_dir, 'menu_foreground.png')
      end
      if not File.exist?(path_foreground)
        path_foreground = nil
      end
      align = getstring('menu.background.alignment')
      if not align.empty?
        align_background = align
      end
      if not ['lefttop', 'righttop', 'centertop'].include?(align_background)
        align_background = 'lefttop'
      end
      align_background = align_background[0..-4].encode('ascii') # XXX
      align = getstring('menu.sidebar.alignment')
      if not align.empty?
        align_sidebar = align
      end
      if not ['top', 'bottom'].include?(align_sidebar)
        align_sidebar = 'bottom'
      end
      align_sidebar = align_sidebar.encode('ascii') # XXX
      align = getstring('menu.foreground.alignment')
      if not align.empty?
        align_foreground = align
      end
      if not ['lefttop', 'righttop', 'centertop'].include?(align_foreground)
        align_foreground = 'lefttop'
      end
      align_foreground = align_foreground[0..-4].encode('ascii') # XXX
      return path_background, path_sidebar, path_foreground, \
             align_background, align_sidebar, align_foreground
    end

    def get_menu_fontcolor()
      background, foreground = @surface.get_menu_fontcolor()
      color_r = getstring('menu.background.font.color.r')
      color_g = getstring('menu.background.font.color.g')
      color_b = getstring('menu.background.font.color.b')
      begin
        color_r = [0, [255, color_r.to_i].min].max
        color_g = [0, [255, color_g.to_i].min].max
        color_b = [0, [255, color_b.to_i].min].max
      rescue
        #pass
      else
        background = [color_r, color_g, color_b]
      end
      color_r = getstring('menu.foreground.font.color.r')
      color_g = getstring('menu.foreground.font.color.g')
      color_b = getstring('menu.foreground.font.color.b')
      begin
        color_r = [0, [255, color_r.to_i].min].max
        color_g = [0, [255, color_g.to_i].min].max
        color_b = [0, [255, color_b.to_i].min].max
      rescue
        #pass
      else
        foreground = [color_r, color_g, color_b]
      end
      return background, foreground
    end

    def get_mayuna_menu()
      return @surface.get_mayuna_menu()
    end

    def get_current_balloon_directory()
      return @balloon.get_balloon_directory()
    end

    def get_current_shell()
      return @shell_directory
    end

    def get_current_shell_name()
      return @shells[get_current_shell()].baseinfo[0]
    end

    def get_default_shell()
      default = @shell_directory or 'master'
      if not @shells.include?(default)
        default = @shells.keys()[0] # XXX
      end
      return default
    end

    def get_balloon_default_id()
      return @desc.get('balloon.defaultsurface', :default => '0')
    end

    def select_shell(shell_key)
      #assert @shells and @shells.include?(shell_key)
      @shell_directory = shell_key # save user's choice
      surface_name, surface_dir, surface_desc, surface_alias, surface, surface_tooltips, seriko_descript = \
                                                                                         @shells[shell_key].baseinfo
      proc_obj = lambda {
        Logging::Logging.info('ghost ' + @key + ' ' + shell_key)
        set_surface(surface_desc, surface_alias, surface, surface_name,
                    surface_dir, surface_tooltips, seriko_descript)
        @surface.reset_alignment()
        @surface.reset_position()
        notify_event('OnShellChanged',
                     surface_name, surface_name, surface_dir)
      }
      enqueue_event('OnShellChanging', surface_name, surface_dir,
                    :proc_obj => proc_obj)
    end

    def select_balloon(item, desc, balloon)
      @balloon_directory = item # save user's choice
      if item == get_current_balloon_directory() # no change
        return # need reloadning?
      end
      #assert item == balloon['balloon_dir'][0]
      path = File.join(Home.get_ninix_home(), 'balloon', item)
      @balloon.hide_all()
      set_balloon(desc, balloon)
      @balloon.set_balloon_default()
      position_balloons()
      name = desc.get('name', :default => '')
      Logging::Logging.info('balloon ' + name + ' ' + path)
      notify_event('OnBalloonChange', name, path)
    end

    def surface_bootup(flag_break: false)
      for side in [0, 1]
        if not @__boot[side]
          set_surface_default(:side => side)
          @surface.show(side)
        end
      end
    end

    def get_uptime()
      uptime = ((Time.new.to_f - @start_time).to_i / 3600).to_i
      if uptime < 0
        @start_time = Time.new.to_f
        return 0
      end
      return uptime
    end

    def hide_all()
      @surface.hide_all()
      @balloon.hide_all()
    end

    def position_balloons()
      @surface.reset_balloon_position()
    end

    def align_top(side)
      @surface.set_alignment(side, 1)
    end

    def align_bottom(side)
      @surface.set_alignment(side, 0)
    end

    def align_current()
      @surface.set_alignment_current()
    end

    def identify_window(win)
      return (@surface.identify_window(win) or
              @balloon.identify_window(win))
    end

    def set_surface_default(side: nil)
      @surface.set_surface_default(side)
    end

    def get_surface_scale()
      return @parent.handle_request('GET', 'get_preference', 'surface_scale')
    end

    def get_surface_size(side)
      result = @surface.get_surface_size(side)
      if result != nil
        return result
      else
        return [0, 0]
      end
    end

    def set_surface_position(side, x, y)
      @surface.set_position(side, x, y)
    end

    def set_surface_id(side, id)
      @surface.set_surface(side, id)
    end

    def get_surface_id(side)
      return @surface.get_surface(side)
    end

    def surface_is_shown(side)
      return (@surface and @surface.is_shown(side))
    end

    def get_target_window
      return @surface.get_window(0).window
    end

    def get_kinoko_position(baseposition)
      side = 0
      x, y = get_surface_position(side)
      w, h = get_surface_size(side)
      if baseposition == 1
        rect = @surface.get_collision_area(side, 'face')
        if rect != nil
          x1, y1, x2, y2 = rect
          return x + ((x2 - x1) / 2).to_i, y + ((y2 - y1) / 2).to_i
        else
          return x + (w / 2).to_i, y + (h / 4).to_i
        end
      elsif baseposition == 2
        rect = @surface.get_collision_area(side, 'bust')
        if rect != nil
          x1, y1, x2, y2 = rect
          return x + ((x2 - x1) / 2).to_i, y + ((y2 - y1) / 2).to_i
        else
          return x + (w / 2).to_i, y + (h / 2).to_i
        end
      elsif baseposition == 3
        centerx, centery = @surface.get_center(side)
        if centerx == nil
          centerx = (w / 2).to_i
        end
        if centery == nil
          centery = (h / 2).to_i
        end
        return x + centerx, y + centery
      else # baseposition == 0 or baseposition not in [1, 2, 3]: # AKF
        centerx, centery = @surface.get_kinoko_center(side)
        if centerx == nil or centery == nil
          rect = @surface.get_collision_area(side, 'head')
          if rect != nil
            x1, y1, x2, y2 = rect
            return x + ((x2 - x1) / 2).to_i, y + ((y2 - y1) / 2).to_i
          else
            return x + (w / 2).to_i, y + (h / 8).to_i
          end
        end
        return x + centerx, y + centery
      end
    end

    def raise_surface(side)
      @surface.raise_(side)
    end

    def lower_surface(side)
      @surface.lower(side)
    end

    def raise_all()
      @surface.raise_all()
      @balloon.raise_all()
    end

    def lower_all()
      @surface.lower_all()
      @balloon.lower_all()
    end

    ###   STARTER   ###
    def stand_by(reset_surface)
      @balloon.hide_all()
      @balloon.hide_sstp_message()
      default_sakura = @desc.get('sakura.seriko.defaultsurface', :default => '0')
      default_kero = @desc.get('kero.seriko.defaultsurface', :default => '10')
      if reset_surface
        set_surface_default()
        @balloon.set_balloon_default()
      elsif get_surface_id(0) != default_sakura or \
           get_surface_id(1) != default_kero
        @__surface_life = Array(20..30).sample
        ##Logging::Logging.debug('surface_life = ' + @__surface_life)
      end
    end

    def start(key, init, temp, vanished, ghost_changed,
              prev_self_name, prev_name, prev_shell, last_script, abend)
      if is_running()
        if temp != 0
          enter_temp_mode()
        else
          if @__temp_mode == 1
            @__temp_mode = 2
            load_shiori()
            notify_start(
              init, vanished, ghost_changed,
              prev_self_name, prev_name, prev_shell,
              '', last_script, :abend => abend)
          end
        end
        return
      end
      @ghost_time = 0
      @vanished_count = 0
      @__running = true
      @__temp_mode = temp
      @key = key
      @force_quit = false
      Logging::Logging.info('ghost ' + key)
      load_settings()
      shell_key = get_default_shell()
      @shell_directory = shell_key # XXX
      #assert @shells and @shells.include?(shell_key)
      surface_name, surface_dir, surface_desc, surface_alias, surface, surface_tooltips, seriko_descript = \
                                                                                         @shells[shell_key].baseinfo
      if ghost_changed
        name = prev_self_name
      else
        name = surface_name
      end
      set_surface(surface_desc, surface_alias, surface, surface_name,
                       surface_dir, surface_tooltips, seriko_descript)
      balloon = nil
      if @parent.handle_request('GET', 'get_preference', 'ignore_default') == 0 ## FIXME: change prefs key
        balloon_path = @desc.get('deault.balloon.path', :default => '')
        balloon_name = @desc.get('balloon', :default => '')
        if not balloon_path.empty?
          balloon = @parent.handle_request(
            'GET', 'find_balloon_by_subdir', balloon_path)
        end
        if balloon == nil and not balloon_name.empty?
          balloon = @parent.handle_request(
            'GET', 'find_balloon_by_name', balloon_name)
        end
      end
      if balloon == nil
        if @balloon_directory != nil
          balloon = @balloon_directory
        else
          balloon = @parent.handle_request(
            'GET', 'get_preference', 'default_balloon')
        end
      end
      desc, balloon = @parent.handle_request(
              'GET', 'get_balloon_description', balloon)
      set_balloon(desc, balloon)
      if temp == 0
        load_shiori()
      end
      restart()
      @start_time = Time.new.to_f
      notify_start(
        init, vanished, ghost_changed,
        name, prev_name, prev_shell, surface_dir, last_script, :abend => abend)
      GLib::Timeout.add(10) { do_idle_tasks } # 10[ms]
    end

    def restart()
      load_history()
      @vanished = false
      @__boot = [false, false]
      @old_otherghostname = nil ## FIXME
      reset_script(:reset_all => true)
      @surface.reset_alignment()
      stand_by(true)
      @surface.reset_position()
      reset_idle_time()
      @__running = true
      @force_quit = false
    end

    def stop()
      if not @__running
        return
      end
      notify_observer('finalize')
      @__running = false
      save_settings()
      save_history()
      @parent.handle_request('NOTIFY', 'rebuild_ghostdb', self, :name => nil)
      hide_all()
      @surface.finalize()
      @balloon.finalize()
      if @audio_player != nil
        @audio_player.set_state(Gst::State::NULL)
      end
      @audio_loop = false
    end

    def process_script()
      now = Time.new
      idle = get_idle_time()
      second, minute = now.localtime.to_a[0, 2]
      if @clock[0] != second ## FIXME
        if @__temp_mode == 0
          @ghost_time += 1
        end
        @parent.handle_request(
          'NOTIFY', 'rebuild_ghostdb',
          self,
          :name => get_selfname(),
          :s0 => get_surface_id(0),
          :s1 => get_surface_id(1))
        otherghostname = @parent.handle_request(
          'GET', 'get_otherghostname', get_selfname())
        if otherghostname != @old_otherghostname
          notify_event('otherghostname', [otherghostname],
                       :event_type => 'NOTIFY')
        end
        @old_otherghostname = otherghostname
      end
      if not @__running
        #pass
      elsif [PAUSE_MODE, PAUSE_NOCLEAR_MODE].include?(@script_mode)
        ##if idle > PAUSE_TIMEOUT:
        ##    @script_mode = BROWSE_MODE
        #pass
      elsif @script_mode == WAIT_MODE
        #pass
      elsif not @processed_script.empty? or not @processed_text.empty?
        interpret_script()
      elsif not @script_post_proc.empty?
        for proc_obj in @script_post_proc
          proc_obj.call()
        end
        @script_post_proc = []
      elsif not @script_finally.empty?
        for proc_obj in @script_finally
          proc_obj.call()
        end
        @script_finally = []
      elsif @script_mode == SELECT_MODE
        if @passivemode
          #pass
        elsif idle > SELECT_TIMEOUT
          @script_mode = BROWSE_MODE
          if @sstp_request_handler
            @sstp_request_handler.send_timeout()
            @sstp_request_handler = nil
          end
          if not notify_event('OnChoiceTimeout')
            stand_by(false)
          end
        end
      elsif @sstp_handle != nil
        close_sstp_handle()
      elsif @balloon.user_interaction
        #pass
      elsif idle > @__balloon_life and @__balloon_life > 0 and not @passivemode
        @__balloon_life = 0
        for side in 0..@char-1
          if balloon_is_shown(side)
            notify_event('OnBalloonTimeout',
                         @__current_script)
            break
          end
        end
        stand_by(false)
        if @parent.handle_request('GET', 'get_preference', 'sink_after_talk') != 0
          @surface.lower_all()
        end
      elsif not @event_queue.empty? and handle_event()
        #pass
      elsif not @script_queue.empty? and not @passivemode
        if get_silent_time() > 0
          keep_silence(true) # extend silent time
        end
        event, script, sender, @sstp_handle, \
        host, show_sstp_marker, use_translator, \
        @sstp_entry_db, @sstp_request_handler = \
                        @script_queue.shift
        if @cantalk
          if show_sstp_marker
            @balloon.show_sstp_message(sender, host)
          else
            @balloon.hide_sstp_message()
          end
          # XXX: how about the use_translator flag?
          start_script(script, :origin => FROM_SSTP_CLIENT)
          proc_obj = lambda {|flag_break: false|
            @parent.handle_request(
              'NOTIFY', 'notify_other', @key,
              event, get_name(:default => ''),
              get_selfname(:default => ''),
              get_current_shell_name(),
              flag_break, nil,
              [sender, host], (not use_translator), script, [])
          }
          @script_finally << proc_obj
        end
      elsif get_silent_time() > 0
        if now.to_f - get_silent_time() > SILENT_TIME
          keep_silence(false)
        end
      elsif @clock[0] != second and \
           notify_event('OnSecondChange', get_uptime(),
                        @surface.get_mikire(),
                        @surface.get_kasanari(),
                        (not @passivemode and @cantalk))
        #pass
      elsif @clock[1] != minute and \
           notify_event('OnMinuteChange', get_uptime(),
                        @surface.get_mikire(),
                        @surface.get_kasanari(),
                        (not @passivemode and @cantalk))
        #pass
      elsif @surface_mouse_motion != nil
        side, x, y, part = @surface_mouse_motion
        notify_event('OnMouseMove', x, y, '', side, part)
        @surface_mouse_motion = nil
      elsif idle > @__surface_life and @__surface_life > 0 and not @passivemode
        @__surface_life = 0
        notify_event('OnSurfaceRestore',
                     get_surface_id(0),
                     get_surface_id(1))
      end
      @clock = [second, minute]
    end

    def do_idle_tasks()
      if not @__running
        return false
      end
      if @force_quit and not busy() and \
        not (not @processed_script.empty? or not @processed_text.empty?)
        quit()
      end
      @parent.handle_request('NOTIFY', 'update_working', get_name())
      if @__temp_mode != 0
        process_script()
        if not busy() and \
          @script_queue.empty? and \
          not (not @processed_script.empty? or \
               not @processed_text.empty?)
          if @__temp_mode == 1
            sleep(1.4)
            finalize()
            @parent.handle_request('NOTIFY', 'close_ghost', self)
            @parent.handle_request('NOTIFY', 'reset_sstp_flag')
            return false
          else
            @parent.handle_request('NOTIFY', 'reset_sstp_flag')
            leave_temp_mode()
            return true
          end
        else
          return true
        end
      end
      if @reload_event and not busy() and \
        not (not @processed_script.empty? or not @processed_text.empty?)
        hide_all()
        Logging::Logging.info('reloading....')
        @shiori.unload()
        @updateman.clean_up() # Don't call before unloading SHIORI
        @parent.handle_request(
          'NOTIFY', 'stop_sakura', self,
          lambda {|a|
            @parent.handle_request('NOTIFY', 'reload_current_sakura', a) },
          [self])
        load_settings()
        restart() ## FIXME
        Logging::Logging.info('done.')
        enqueue_event(*@reload_event)
        @reload_event = nil
      end
      # continue network update (enqueue events)
      if @updateman.is_active()
        @updateman.run()
        while true
          event = @updateman.get_event()
          if not event
            break
          end
          if event[0] == 'OnUpdateComplete' and event[1] == 'changed'
            @reload_event = event
          else
            enqueue_event(*event)
          end
        end
      end
      process_script()
      return true
    end

    def quit()
      @parent.handle_request('NOTIFY', 'stop_sakura', self)
    end

    ###   SCRIPT PLAYER   ###
    def start_script(script, origin: nil)
      if script.empty?
        return
      end
      @last_script = script
      if not origin
        @script_origin = FROM_GHOST
      else
        @script_origin = origin
      end
      reset_script(:reset_all => true)
      @__current_script = script
      if not script.rstrip().end_with?('\e')
        script = [script, '\e'].join('')
      end
      @processed_script = []
      @script_position = 0
      while true
        begin
          @processed_script.concat(@script_parser.parse(script))
          break
        rescue Script::ParserError => e
          Logging::Logging.error('-' * 50)
          Logging::Logging.error(e.format) # 'UTF-8'
          done, script = e.get_item
          @processed_script.concat(done)
        end
      end
      @script_mode = BROWSE_MODE
      @script_wait = nil
      @script_side = 0
      @time_critical_session = false
      @quick_session = false
      set_synchronized_session(:list => [], :reset => true)
      @balloon.hide_all()
      if @processed_script.empty?
        return
      end
      node = @processed_script[0]
      if node[0] == Script::SCRIPT_TAG and node[1] == '\C'
        @processed_script.shift
        @script_position = node[-1]
      else
        @balloon.clear_text_all()
      end
      @balloon.set_balloon_default()
      @current_time = Time.new.to_a
      reset_idle_time()
      if @parent.handle_request('GET', 'get_preference', 'raise_before_talk') != 0
        raise_all()
      end
    end

    def __yen_e(args)
      surface_id = get_surface_id(@script_side)
      @surface.invoke_yen_e(@script_side, surface_id)
      reset_script()
      @__balloon_life = BALLOON_LIFE
    end    

    def __yen_0(args)
      ##@balloon.show(0)
      @script_side = 0
    end

    def __yen_1(args)
      ##@balloon.show(1)
      @script_side = 1
    end

    def __yen_p(args)
      begin
        chr_id = args[0].to_i
      rescue ArgumentError
        return
      end
      if chr_id >= 0
        @script_side = chr_id
      end
    end

    def __yen_4(args)
      if @script_side == 0
        sw, sh = get_surface_size(1)
        sx, sy = get_surface_position(1)
      elsif @script_side == 1
        sw, sh = get_surface_size(0)
        sx, sy = get_surface_position(0)
      else
        return
      end
      w, h = get_surface_size(@script_side)
      x, y = get_surface_position(@script_side)
      left, top, scrn_w, scrn_h = Pix.get_workarea()
      if sx + (sw / 2).to_i > left + (scrn_w / 2).to_i
        new_x = [x - (scrn_w / 20).to_i, sx - (scrn_w / 20).to_i].min
      else
        new_x = [x + (scrn_w / 20).to_i, sx + (scrn_w / 20).to_i].max
      end
      if x > new_x
        step = -10
      else
        step = 10
      end
      for current_x in (x..new_x-1).step(step)
        set_surface_position(@script_side, current_x, y)
      end
      set_surface_position(@script_side, new_x, y)
    end

    def __yen_5(args)
      if @script_side == 0
        sw, sh = get_surface_size(1)
        sx, sy = get_surface_position(1)
      elsif @script_side == 1
        sw, sh = get_surface_size(0)
        sx, sy = get_surface_position(0)
      else
        return
      end
      w, h = get_surface_size(@script_side)
      x, y = get_surface_position(@script_side)
      left, top, scrn_w, scrn_h = Pix.get_workarea()
      if x < sx + (sw / 2).to_i < x + w or sx < x + (w / 2).to_i < sx + sw
        return
      end
      if sx + (sw / 2).to_i > x + (w / 2).to_i
        new_x = sx - (w / 2).to_i + 1
      else
        new_x = sx + sw - (w / 2).to_i - 1
      end
      new_x = [new_x, left].max
      new_x = [new_x, left + scrn_w - w].min
      if x > new_x
        step = -10
      else
        step = 10
      end
      for current_x in (x..new_x-1).step(step)
        set_surface_position(@script_side, current_x, y)
      end
      set_surface_position(@script_side, new_x, y)
    end

    def __yen_s(args)
      surface_id = args[0]
      if surface_id == '-1'
        @surface.hide(@script_side)
      else
        set_surface_id(@script_side, surface_id)
        @surface.show(@script_side)
      end
      if [0, 1].include?(@script_side) and not @__boot[@script_side]
        @__boot[@script_side] = true
      end
    end

    def __yen_b(args)
      if args[0] == '-1'
        @balloon.hide(@script_side)
      else
        begin
          balloon_id = (args[0].to_i / 2).to_i
        rescue ArgumentError
          balloon_id = 0
        else
          @balloon.set_balloon(@script_side, balloon_id)
        end
      end
    end

    def __yen__b(args)
      begin
        filename, x, y = expand_meta(args[0]).split(',', 3)
      rescue ArgumentError
        filename, param = expand_meta(args[0]).split(',', 2)
        #assert param == 'inline'
        x, y = 0, 0 ## FIXME
      end
      filename = get_normalized_path(filename)
      path = File.join(get_prefix(), 'ghost/master', filename)
      if File.file?(path)
        @balloon.append_image(@script_side, path, x, y)
      else
        path = [path, '.png'].join('')
        if File.file?(path)
          @balloon.append_image(@script_side, path, x, y)
        end
      end
    end

    def __yen_n(args)
      if not args.empty? and expand_meta(args[0]) == 'half'
        @balloon.append_text(@script_side, '\n[half]')
      else
        @balloon.append_text(@script_side, '\n')
      end
    end

    def __yen_c(args)
      @balloon.clear_text(@script_side)
    end

    def __set_weight(value, unit)
      begin
        amount = value.to_i * unit - 0.01
      rescue ArgumentError
        amount = 0
      end
      if amount > 0
        @script_wait = Time.new.to_f + amount
      end
    end

    def __yen_w(args)
      script_speed = @parent.handle_request(
        'GET', 'get_preference', 'script_speed')
      if not @quick_session and script_speed >= 0
        __set_weight(args[0], 0.05) # 50[ms]
      end
    end

    def __yen__w(args)
      script_speed = @parent.handle_request(
        'GET', 'get_preference', 'script_speed')
      if not @quick_session and script_speed >= 0
        __set_weight(args[0], 0.001) # 1[ms]
      end
    end

    def __yen_t(args)
      @time_critical_session = (not @time_critical_session)
    end

    def __yen__q(args)
      @quick_session = (not @quick_session)
    end

    def __yen__s(args)
      list = []
      for arg in args
        list << arg.to_i
      end
      set_synchronized_session(:list => list)
    end

    def __yen__e(args)
      @balloon.hide(@script_side)
      @balloon.clear_text(@script_side)
    end

    def __yen_q(args)
      newline_required = false
      if args.length == 3 # traditional syntax
        num, link_id, text = args
        newline_required = true
      else # new syntax
        text, link_id = args
      end
      text = expand_meta(text)
      @balloon.append_link(@script_side, link_id, text,
                           :newline_required => newline_required)
      @script_mode = SELECT_MODE
    end

    def __yen_URL(args)
      text = expand_meta(args[0])
      if args.length == 1
        link = text
      else
        link = '#cancel'
      end
      @balloon.append_link(@script_side, link, text)
      for i in (1..args.length-1).step(2)
        link = expand_meta(args[i])
        text = expand_meta(args[i + 1])
        @balloon.append_link(@script_side, link, text)
      end
      @script_mode = SELECT_MODE
    end

    def __yen__a(args)
      if @anchor
        anchor_id = @anchor[0]
        text = @anchor[1]
        @balloon.append_link_out(@script_side, anchor_id, text)
        @anchor = nil
      else
        anchor_id = args[0]
        @anchor = [['anchor', anchor_id], '']
        @balloon.append_link_in(@script_side, @anchor[0])
      end
    end

    def __yen_x(args)
      if @script_mode == BROWSE_MODE
        if args.length > 0 and expand_meta(args[0]) == 'noclear'
          @script_mode = PAUSE_NOCLEAR_MODE
        else
          @script_mode = PAUSE_MODE
        end
      end
    end

    def __yen_a(args)
      start_script(getaistringrandom())
    end

    def __yen_i(args)
      begin
        actor_id = args[0].to_i
      rescue ArgumentError
        #pass
      else
        @surface.invoke(@script_side, actor_id)
      end
    end

    def __yen_j(args)
      jump_id = args[0]
      if is_URL(jump_id)
        browser_open(jump_id)
      elsif @sstp_entry_db
        start_script(@sstp_entry_db.get(jump_id, :default => '\e'))
      end
    end

    def __yen_minus(args)
      quit()
    end

    def __yen_plus(args)
      @parent.handle_request('NOTIFY', 'select_ghost', self, true)
    end

    def __yen__plus(args)
      @parent.handle_request('NOTIFY', 'select_ghost', self, false)
    end

    def __yen_m(args)
      write_sstp_handle(expand_meta(args[0]))
    end

    def __yen_and(args)
      begin
        text = CGI.unescape_html("&" + args[0].to_s + ";")
      rescue ArgumentError
        text = nil
      end
      if text == nil
        text = '?'
      end
      @balloon.append_text(@script_side, text)
    end

    def __yen__m(args)
      begin
        num = args[0].to_i(16)
      rescue ArgumentError
        num = 0
      end
      if 0x20 <= num and num <= 0x7e
        text = num.chr
      else
        text = '?'
      end
      @balloon.append_text(@script_side, text)
    end

    def __yen__u(args)
      if re.match('0x[a-fA-F0-9]{4}', args[0])
        text = eval(['"\\u', args[0][2..-1], '"'].join(''))
        @balloon.append_text(@script_side, text)
      else
        @balloon.append_text(@script_side, '?')
      end
    end

    def __yen__v(args)
      if @audio_player == nil
        return
      end
      filename = expand_meta(args[0])
      filename = get_normalized_path(filename)
      path = File.join(get_prefix(), 'ghost/master', filename)
      if File.file?(path)
        @audio_player.set_state(Gst::State::NULL)
        @audio_player.set_property(
          'uri', 'file://' + URI.escape(path))
        @audio_loop = false
        @audio_player.set_state(Gst::State::PLAYING)
      end
    end

    def __yen_8(args)
      if @audio_player == nil
        return
      end
      filename = expand_meta(args[0])
      filename = get_normalized_path(filename)
      basename = File.basename(filename)
      ext = File.extname(filename)
      ext = ext.lower()
      if ext != '.wav'
        return
      end
      path = File.join(get_prefix(), 'ghost/master', filename)
      if File.file?(path)
        @audio_player.set_state(Gst::State::NULL)
        @audio_player.set_property(
          'uri', 'file://' + URI.escape(path))
        @audio_loop = false
        @audio_player.set_state(Gst::State::PLAYING)
      end
    end

    def __yen__V(args)
      if @audio_loop
        return # nothing to do
      end
      if @audio_player.get_state(timeout=Gst::SECOND)[1] == Gst::State::PLAYING
        @script_mode = WAIT_MODE
      end
    end

    def __yen_exclamation(args) ## FIXME
      if args.empty?
        return
      end
      argc = args.length
      args = args.map {|s| expand_meta(s)}
      if args[0] == 'raise' and argc >= 2
        notify_event(*args[1, 9])
      elsif args[0, 2] == ['open', 'readme']
        ReadmeDialog().show(get_name(), get_prefix())
      elsif args[0, 2] == ['open', 'browser'] and argc > 2
        browser_open(args[2])
      elsif args[0, 2] == ['open', 'communicatebox']
        @balloon.open_communicatebox()
      elsif args[0, 2] == ['open', 'teachbox']
        @balloon.open_teachbox()
      elsif args[0, 2] == ['open', 'inputbox'] and argc > 2
        if argc > 4
          @balloon.open_inputbox(args[2], :limittime => args[3], :default => args[4])
        elsif argc == 4
          @balloon.open_inputbox(args[2], :limittime => args[3])
          else
            @balloon.open_inputbox(args[2])
        end
      elsif args[0, 2] == ['open', 'passwordinputbox'] and argc > 2
        if argc > 4
          @balloon.open_passwordinputbox(args[2], :limittime => args[3], :default => args[4])
        elsif argc == 4
          @balloon.open_passwordinputbox(args[2], :limittime => args[3])
        else
          @balloon.open_passwordinputbox(args[2])
        end
      elsif args[0, 2] == ['open', 'configurationdialog']
        @parent.handle_request('NOTIFY', 'edit_preferences')
      elsif args[0, 2] == ['close', 'inputbox'] and argc > 2
        @balloon.close_inputbox(args[2])
      elsif args[0, 2] == ['change', 'balloon'] and argc > 2
        key = @parent.handle_request('GET', 'find_balloon_by_name', args[2])
        if key != nil
          desc, balloon = @parent.handle_request(
                  'GET', 'get_balloon_description', key)
          select_balloon(key, desc, balloon)
        end
      elsif args[0, 2] == ['change', 'shell'] and argc > 2
        for key in @shells.keys
          shell_name = @shells[key].baseinfo[0]
          if shell_name == args[2]
            select_shell(key)
            break
          end
        end
      elsif args[0, 2] == ['change', 'ghost'] and argc > 2
        if args[2] == 'random'
          @parent.handle_request('NOTIFY', 'select_ghost', self, false, :event => 0)
        else
          @parent.handle_request(
            'NOTIFY', 'select_ghost_by_name', self, args[2], :event => 0)
        end
      elsif args[0, 2] == ['call', 'ghost'] and argc > 2
        key = @parent.handle_request('GET', 'find_ghost_by_name', args[2])
        if key != nil
          @parent.handle_request('NOTIFY', 'start_sakura_cb', key, :caller => self)
        end
      elsif args[0, 1] == ['updatebymyself']
        if not busy(:check_updateman => false)
          __update()
        end
      elsif args[0, 1] == ['vanishbymyself']
        @vanished = true ## FIXME
        if argc > 1
          next_ghost = args[1]
        else
          next_ghost = nil
        end
        vanish_by_myself(next_ghost)
      elsif args[1, 1] == ['repaint']
        if args[0, 1] == ['lock']
          @lock_repaint = true
        elsif args[0, 1] == ['unlock']
          @lock_repaint = false
        end
      elsif args[1, 1] == ['passivemode']
        if args[0, 1] == ['enter']
          @passivemode = true
        elsif args[0, 1] == ['leave']
          @passivemode = false
        end
      elsif args[1, 1] == ['collisionmode']
        if args[0, 1] == ['enter']
          if args[2, 1] == ['rect']
            @parent.handle_request(
              'NOTIFY', 'set_collisionmode', true, :rect => true)
          else
            @parent.handle_request(
              'NOTIFY', 'set_collisionmode', true)
          end
        elsif args[0, 1] == ['leave']
          @parent.handle_request(
            'NOTIFY', 'set_collisionmode', false)
        end
      elsif args[0, 2] == ['set', 'alignmentondesktop'] and argc > 2
        if args[2] == 'bottom'
          if not @synchronized_session.empty?
            for chr_id in @synchronized_session
              align_bottom(chr_id)
            end
          else
            align_bottom(@script_side)
          end
        elsif args[2] == 'top'
          if not @synchronized_session.empty?
            for chr_id in @synchronized_session
              align_top(chr_id)
            end
          else
            align_top(@script_side)
          end
        elsif args[2] == 'free'
          if not @synchronized_session.empty?
            for chr_id in @synchronized_session
              @surface.set_alignment(chr_id, 2)
            end
          else
            @surface.set_alignment(@script_side, 2)
          end
        elsif args[2] == 'default'
          @surface.reset_alignment()
        end
      elsif args[0, 2] == ['set', 'autoscroll'] and argc > 2
        if args[2] == 'disable'
          @balloon.set_autoscroll(false)
        elsif args[2] == 'enable'
          @balloon.set_autoscroll(true)
        else
          #pass ## FIXME
        end
      elsif args[0, 2] == ['set', 'windowstate'] and argc > 2
        if args[2] == 'minimize'
          @surface.window_iconify(true)
          ##elsif args[2] == '!minimize':
          ##    @surface.window_iconify(false)
        elsif args[2] == 'stayontop'
          @surface.window_stayontop(true)
        elsif args[2] == '!stayontop'
          @surface.window_stayontop(false)
        end
      elsif args[0, 2] == ['set', 'trayicon'] and argc > 2
        path = File.join(get_prefix(), args[2])
        if File.exist?(path)
          @status_icon.set_from_file(path) # XXX
        end
        if argc > 3
          text = args[3]
          if not text.empty?
            @status_icon.set_has_tooltip(true)
            @status_icon.set_tooltip_text(text)
          else
            @status_icon.set_has_tooltip(false)
          end
        else
          @status_icon.set_has_tooltip(false)
        end
        @status_icon.set_visible(true)
      elsif args[0, 2] == ['set', 'wallpaper'] and argc > 2
        path = File.join(get_prefix(), args[2])
        opt = nil
        if argc > 3
          # possible picture_options value:
          # "none", "wallpaper", "centered", "scaled", "stretched"
          options = {
            'center' => 'centered',
            'tile' => 'wallpaper',
            'stretch' => 'stretched'
          }
          if not options.include?(args[3])
            opt = nil
          else
            opt = options[args[3]]
          end
        end
        if opt == nil
          opt = 'centered' # default
        end
        if File.exist?(path)
          if RbConfig::CONFIG['host_os'] =~ /linux/ # 'posix'
            # for GNOME3
            gsettings = Gio::Settings.new(
              'org.gnome.desktop.background')
            gsettings.set_string('picture-uri',
                                 ['file://', path].join(''))
            gsettings.set_string('picture-options', opt)
          else
            #pass # not implemented yet
          end
        end
      elsif args[0, 2] == ['set', 'otherghosttalk'] and argc > 2
        if args[2] == 'true'
          @__listening['OnOtherGhostTalk'] = true
        elsif args[2] == 'false'
          @__listening['OnOtherGhostTalk'] = false
        else
          #pass ## FIXME
        end
      elsif args[0, 2] == ['set', 'othersurfacechange'] and argc > 2
        if args[2] == 'true'
          @__listening['OnOtherSurfaceChange'] = true
        elsif args[2] == 'false'
          @__listening['OnOtherSurfaceChange'] = false
        else
          #pass ## FIXME
        end
      elsif args[0, 2] == ['set', 'balloonoffset'] and argc > 3
        begin
          x = args[2].to_i
          y = args[3].to_i
        rescue ArgumentError
          #pass
        else
          @surface.set_balloon_offset(@script_side, [x, y])
        end
      elsif args[0] == 'sound' and argc > 1
        command = args[1]
        if @audio_player == nil
          return
        end
        if command == 'stop'
          @audio_player.set_state(Gst::State::NULL)
          @audio_loop = false
        elsif command == 'play' and argc > 2
          filename = args[2]
          filename = get_normalized_path(filename)
          path = File.join(get_prefix(),
                           'ghost/master', filename)
          if File.file?(path)
            @audio_player.set_state(Gst::State::NULL)
            @audio_player.set_property(
              'uri', 'file://' + URI.escape(path))
            @audio_loop = false
            @audio_player.set_state(Gst::State::PLAYING)
          end
        elsif command == 'cdplay' and argc > 2
          @audio_player.set_state(Gst::State::NULL)
          begin
            track = args[2].to_i
          rescue ArgumentError
            return
          end
          @audio_player.set_property(
            'uri', 'cdda://' + track.to_s)
          @audio_loop = false
          @audio_player.set_state(Gst::State::PLAYING)
        elsif command == 'loop' and argc > 2
          filename = args[2]
          filename = get_normalized_path(filename)
          path = File.join(get_prefix(),
                           'ghost/master', filename)
          if File.file?(path)
            @audio_player.set_state(Gst::State::NULL)
            @audio_player.set_property(
              'uri', 'file://' + URI.escape(path))
            @audio_loop = true
            @audio_player.set_state(Gst::State::PLAYING)
          end
        elsif command == 'wait'
          if @audio_loop
            return # nothing to do
          end
          if @audio_player.get_state(timeout=Gst::SECOND)[1] == Gst::State::PLAYING
            @script_mode = WAIT_MODE
          end
        elsif command == 'pause'
          if @audio_player.get_state(timeout=Gst::SECOND)[1] == Gst::State::PLAYING
            @audio_player.set_state(Gst::State::PAUSED)
          end
        elsif command == 'resume'
          if @audio_player.get_state(timeout=Gst::SECOND)[1] == Gst::State::PAUSED
            @audio_player.set_state(Gst::State::PLAYING)
          end
        else
          #pass ## FIXME
        end
      elsif args[0] == '*'
        @balloon.append_sstp_marker(@script_side)
      elsif args[0] == 'quicksession' and argc > 1
        if args[1] == 'true'
          @quick_session = true
        elsif args[1] == 'false'
          @quick_session = false
        else
          #pass ## FIXME
        end
      elsif args[0] == 'bind' and argc > 2
        category = args[1]
        name = args[2]
        if argc < 4
          flag = 'toggle'
        else
          flag = args[3]
        end
        bind = @surface.window[@script_side].bind # XXX
        for key in bind.keys
          group = bind[key][0].split(',', 2)
          if category != group[0]
            next
          end
          if not name.empty? and name != group[1]
            next
          end
          if ['true', '1'].include?(flag)
            if bind[key][1]
              next
            end
          elsif ['false', '0'].include?(flag)
            if not bind[key][1]
              next
            end
          else # 'toggle'
            #pass
          end
          @surface.toggle_bind([@script_side, key])
        end
      else
        #pass ## FIXME
      end
    end

    def __yen___c(args)
      @balloon.open_communicatebox()
    end

    def __yen___t(args)
      @balloon.open_teachbox()
    end

    def __yen_v(args)
      raise_surface(@script_side)
    end

    def __yen_f(args)
      if args.length != 2 ## FIXME
        return
      end
      tag = nil
      if args[0] == 'sup'
        if args[1] == 'true'
          tag = '<sup>'
        else
          tag = '</sup>'
        end
      elsif args[0] == 'sub'
        if args[1] == 'true'
          tag = '<sub>'
        else
          tag = '</sub>'
        end
      elsif args[0] == 'strike'
        if ['true', '1', 1].include?(args[1])
          tag = '<s>'
        else
          tag = '</s>'
        end
      elsif args[0] == 'underline'
        if ['true', '1', 1].include?(args[1])
          tag = '<u>'
        else
          tag = '</u>'
        end
      else
        #pass ## FIXME
      end
      if tag != nil
        @balloon.append_meta(@script_side, tag)
      end
    end

    SCRIPT_TAG = {
        '\e' => "__yen_e",
        '\y' => "__yen_e",
        '\z' => "__yen_e",
        '\0' => "__yen_0",
        '\h' => "__yen_0",
        '\1' => "__yen_1",
        '\u' => "__yen_1",
        '\p' => "__yen_p",
        '\4' => "__yen_4",
        '\5' => "__yen_5",
        '\s' => "__yen_s",
        '\b' => "__yen_b",
        '\_b' => "__yen__b",
        '\n' => "__yen_n",
        '\c' => "__yen_c",
        '\w' => "__yen_w",
        '\_w' => "__yen__w",
        '\t' => "__yen_t",
        '\_q' => "__yen__q",
        '\_s' => "__yen__s",
        '\_e' => "__yen__e",
        '\q' => "__yen_q",
        '\URL' => "__yen_URL",
        '\_a' => "__yen__a",
        '\x' => "__yen_x",
        '\a' => "__yen_a", # Obsolete: only for old SHIORI
        '\i' => "__yen_i",
        '\j' => "__yen_j",
        '\-' => "__yen_minus",
        '\+' => "__yen_plus",
        '\_+' => "__yen__plus",
        '\m' => "__yen_m",
        '\&' => "__yen_and",
        '\_m' => "__yen__m",
        '\_u' => "__yen__u",
        '\_v' => "__yen__v",
        '\8' => "__yen_8",
        '\_V' => "__yen__V",
        '\!' => "__yen_exclamation",
        '\__c' => "__yen___c",
        '\__t' => "__yen___t", 
        '\v' => "__yen_v",
        '\f' => "__yen_f",
        '\C' => nil # dummy
        }

    def interpret_script()
      if @script_wait != nil
        if Time.new.to_f < @script_wait
          return
        end
        @script_wait = nil
      end
      if not @processed_text.empty?
        @balloon.show(@script_side)
        @balloon.append_text(@script_side, @processed_text[0])
        @processed_text = @processed_text[1..-1]
        surface_id = get_surface_id(@script_side)
        count = @balloon.get_text_count(@script_side)
        if @surface.invoke_talk(@script_side, surface_id, count)
          @balloon.reset_text_count(@script_side)
        end
        script_speed = @parent.handle_request(
          'GET', 'get_preference', 'script_speed')
        if script_speed > 0
          @script_wait = Time.new.to_f + script_speed * 0.02
        end
        return
      end
      node = @processed_script.shift
      @script_position = node[-1]
      if node[0] == Script::SCRIPT_TAG
        name, args = node[1], node[2..-2]
        if SCRIPT_TAG.include?(name) and \
           Sakura.method_defined?(SCRIPT_TAG[name])
          method(SCRIPT_TAG[name]).call(args)
        else
          #pass ## FIMXE
        end
      elsif node[0] == Script::SCRIPT_TEXT
        text = expand_meta(node[1])
        if @anchor
          @anchor[1] = [@anchor[1], text].join('')
        end
        script_speed = @parent.handle_request(
          'GET', 'get_preference', 'script_speed')
        if not @quick_session and script_speed >= 0
          @processed_text = text
        else
          @balloon.append_text(@script_side, text)
        end
      end
    end

    def reset_script(reset_all: false)
      if reset_all
        @script_mode = BROWSE_MODE
        if not @script_finally.empty?
          for proc_obj in @script_finally
            proc_obj.call(:flag_break => true)
          end
          @script_finally = []
        end
        @script_post_proc = []
        @__current_script = ''
      end
      @processed_script = []
      @processed_text = ''
      @script_position = 0
      @time_critical_session = false
      @quick_session = false
      @lock_repaint = false # SSP compat
      set_synchronized_session(:list => [], :reset => true)
      @balloon.set_autoscroll(true)
      reset_idle_time()
    end

    def set_synchronized_session(list: [], reset: false)
      if reset
        @synchronized_session = []
      elsif list.empty?
        if not @synchronized_session.empty?
          @synchronized_session = []
        else
          @synchronized_session = [0, 1]
        end
      else
        @synchronized_session = list
      end
      @balloon.synchronize(@synchronized_session)
    end

    def expand_meta(text_node)
      buf = []
      for chunk in text_node
        if chunk[0] == Script::TEXT_STRING
          buf << chunk[1]
        elsif chunk[1] == '%month'
          buf << @current_time[4].to_s
        elsif chunk[1] == '%day'
          buf << @current_time[3].to_s
        elsif chunk[1] == '%hour'
          buf << @current_time[2].to_s
        elsif chunk[1] == '%minute'
          buf << @current_time[1].to_s
        elsif chunk[1] == '%second'
          buf << @current_time[0].to_s
        elsif ['%username', '%c'].include?(chunk[1])
          buf << get_username()
        elsif chunk[1] == '%selfname'
          buf << get_selfname()
        elsif chunk[1] == '%selfname2'
          buf << get_selfname2()
        elsif chunk[1] == '%keroname'
          buf << get_keroname()
        elsif chunk[1] == '%friendname'
          buf << get_friendname()
        elsif chunk[1] == '%screenwidth'
          left, top, scrn_w, scrn_h = Pix.get_workarea()
          buf << scrn_w.to_s
        elsif chunk[1] == '%screenheight'
          left, top, scrn_w, scrn_h = Pix.get_workarea()
          buf << scrn_h.to_s
        elsif chunk[1] == '%et'
          buf << @current_time[5].to_s[-1] + '万年'
        elsif chunk[1] == '%wronghour'
          wrongtime = Time.new.to_f + [-2, -1, 1, 2].sample * 3600
          buf << time.localtime(wrongtime)[3].to_s
        elsif chunk[1] == '%exh'
          buf << get_uptime().to_s
        elsif ['%ms', '%mz', '%ml', '%mc', '%mh', \
               '%mt', '%me', '%mp', '%m?'].include?(chunk[1])
          buf << getword(["\\", chunk[1][1..-1]].join(''))
        elsif chunk[1] == '%dms'
          buf << getdms()
        else # %c, %songname
          buf << chunk[1]
        end
      end
      return buf.join('')
    end

    ###   SEND SSTP/1.3   ###
    def _send_sstp_handle(data)
      r, w, e = IO.select([], [@sstp_handle], [], 0)
      if not w
        return
      end
      begin
        @sstp_handle.send([data, "\n"].join(''))
      rescue SystemCallError => e
        #pass
      end
    end

    def write_sstp_handle(data)
      if @sstp_handle == nil
        return
      end
      _send_sstp_handle(['+', data].join(''))
      ##Logging::Logging.debug('write_sstp_handle(' + data.to_s + ')')
    end

    def close_sstp_handle()
      if @sstp_handle == nil
        return
      end
      _send_sstp_handle('-')
      ##Logging::Logging.debug('close_sstp_handle()')
      begin
        @sstp_handle.close()
      rescue SystemCallError => e
        #pass
      end
      @sstp_handle = nil
    end

    def close(reason: 'user')
      if busy()
        if reason == 'user'
          Gdk.beep() ## FIXME
          return
        else # shutdown
          if @updateman.is_active()
            @updateman.interrupt()
          end
        end
      end
      reset_script(:reset_all => true)
      enqueue_event('OnClose', reason)
    end

    def about()
      if busy()
        Gdk.beep() ## FIXME
        return
      end
      start_script(Version.VERSION_INFO)
      @balloon.hide_sstp_message()
    end

    def __update()
      if @updateman.is_active()
        return
      end
      homeurl = getstring('homeurl')
      if homeurl.empty?
        start_script(
          ['\t\h\s[0]',
           _("I'm afraid I don't have Network Update yet."),
           '\e'].join(''))
        @balloon.hide_sstp_message()
        return
      end
      ghostdir = get_prefix()
      Logging::Logging.info('homeurl = ' + homeurl)
      Logging::Logging.info('ghostdir = ' + ghostdir)
      @updateman.start(homeurl, ghostdir)
    end

    def network_update()
      if busy()
        Gdk.beep() ## FIXME
        return
      end
      __update()
    end
  end

  class VanishDialog

    include GetText

    bindtextdomain("ninix-aya")
    
    def initialize
      @parent = nil # dummy
      @dialog = Gtk::Dialog.new
      @dialog.signal_connect('delete_event') do |a|
        return true # XXX
      end
      @dialog.set_title('Vanish')
      @dialog.set_modal(true)
      @dialog.set_resizable(false)
      @dialog.set_window_position(Gtk::Window::Position::CENTER)
      @label = Gtk::Label.new(label=_('Vanish'))
      content_area = @dialog.content_area
      content_area.add(@label)
      @label.show()
      @dialog.add_button("_Yes", Gtk::ResponseType::YES)
      @dialog.add_button("_No", Gtk::ResponseType::NO)
      @dialog.signal_connect('response') do |w, e|
        response(w, e)
      end
    end

    def set_responsible(parent)
      @parent = parent
    end

    def set_message(message)
      @label.set_text(message)
    end

    def show()
      @dialog.show()
    end

    def ok()
      @dialog.hide()
      @parent.handle_request('NOTIFY', 'notify_vanish_selected')
      return true
    end

    def cancel()
      @dialog.hide()
      @parent.handle_request('NOTIFY', 'notify_vanish_canceled')
      return true
    end

    def response(widget, response)
      func = {Gtk::ResponseType::YES.to_i => "ok",
              Gtk::ResponseType::NO.to_i => "cancel",
              Gtk::ResponseType::DELETE_EVENT.to_i => "cancel",
             }
      method(func[response]).call()
      return true
    end
  end

  class ReadmeDialog

    def initialize
      @parent = nil # dummy
      @dialog = Gtk::Dialog.new
      @dialog.signal_connect('delete_event') do |a|
        return true # XXX
      end
      @dialog.set_title('Readme.txt')
      @dialog.set_modal(false)
      @dialog.set_resizable(false)
      @dialog.set_window_position(Gtk::Window::Position::CENTER)
      @label = Gtk::Label.new
      @label.show()
      @textview = Gtk::TextView.new
      @textview.set_editable(false)
      @textview.set_cursor_visible(false)
      @textview.show()
      scroll = Gtk::ScrolledWindow.new(nil, nil)
      scroll.set_policy(Gtk::PolicyType::AUTOMATIC, Gtk::PolicyType::AUTOMATIC)
      scroll.add(@textview)
      scroll.show()
      vbox = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL)
      vbox.set_size_request(720, 460)
      vbox.show()
      vbox.pack_start(@label, :expand => false, :fill => true, :padding => 0)
      vbox.pack_start(scroll, :expand => true, :fill => true, :padding => 0)
      content_area = @dialog.content_area
      content_area.add(vbox)
      @dialog.add_button("_Close", Gtk::ResponseType::CLOSE)
      @dialog.signal_connect('response') do |w, e|
        response(w, e)
      end
    end

    def set_responsible(parent)
      @parent = parent
    end

    def show(name, base_path)
      @label.set_text(name)
      path = File.join(base_path, 'readme.txt')
      if File.exist?(path)
        f = open(path)
        text = f.read()
        text = text.force_encoding('CP932').encode("UTF-8", :invalid => :replace, :undef => :replace) # XXX
        @textview.buffer.set_text(text)
        @dialog.show()
      end
    end

    def response(widget, response)
      func = {Gtk::ResponseType::CLOSE.to_i => "hide",
              Gtk::ResponseType::DELETE_EVENT.to_i => "hide",
             }
      widget.method(func[response]).call()
      return true
    end
  end
end
