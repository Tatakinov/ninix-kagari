# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#  Copyright (C) 2024, 2025 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"
begin
  require "gst"
rescue LoadError
  Gst = nil
end
require "cgi"
require "uri"
require "pathname"
require "securerandom"

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
require_relative "case_insensitive_file"
require_relative "http"

module Sakura

  class ShellMeme < MetaMagic::Meme

    def initialize(key)
      super(key)
    end

    def create_menuitem(data)
      shell_name = data[0]
      subdir = data[1]
      base_path = @parent.handle_request(:GET, :get_prefix)
      thumbnail_path = File.join(base_path, 'shell',
                                 subdir, 'thumbnail.png')
      unless File.exist?(thumbnail_path)
        thumbnail_path = nil
      end
      return @parent.handle_request(
        :GET, :create_shell_menuitem, shell_name, @key,
        thumbnail_path)
    end

    def delete_by_myself()
      @parent.handle_request(:GET, :delete_shell, @key)
    end
  end

  class Sakura < MetaMagic::Holon
    attr_reader :key, :cantalk, :last_script

    include GetText

    bindtextdomain("ninix-kagari")
    
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
      super("") # FIXME
      @handlers = {
        :lock_repaint => :get_lock_repaint
      }
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
      @surface_mouse_motion = nil
      @time_critical_session = false
      @lock_repaint = [false, false]
      @passivemode = false
      @__running = false
      @anchor = nil
      @choice = nil
      @clock = [0, 0]
      @synchronized_session = []
      @force_quit = false
      ##
      @old_otherghostname = nil
      # create vanish dialog
      @__vanish_dialog = VanishDialog.new
      @__vanish_dialog.set_responsible(self)
      @cantalk = true
      @__sender = 'ninix-kagari'
      @__charset = 'UTF-8'
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
      unless Gst.nil?
        @audio_player = Gst::ElementFactory.make('playbin', 'player')
        unless @audio_player.nil?
          fakesink = Gst::ElementFactory.make('fakesink', 'fakesink')
          @audio_player.set_property('video-sink', fakesink)
          bus = @audio_player.bus
          bus.add_signal_watch()
          bus.signal_connect('message') do |bus, message|
            on_audio_message(bus, message)
            next true
          end
        end
      else
        @audio_player = nil
      end
      @audio_loop = false
      @reload_event = nil
      @client = Http::Client.new
      @client.set_responsible(self)
      @defer_show = []
    end

    def get_lock_repaint(*args)
      @lock_repaint[0]
    end

    def attach_observer(observer)
      unless @__observers.include?(observer)
        @__observers[observer] = 1
      end
    end

    def notify_observer(event, *args)
      if args.nil?
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
      fail "assert" unless @shells.include?(key)
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
             shiori_dll, shiori_name)
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
        :GET, :create_shell_menu, shell_menuitems)
      @shiori_dll = shiori_dll
      @shiori_name = shiori_name
      name = [shiori_dll, shiori_name]
      @shiori = @__dll.request(name)
      char = 2
      while not @desc.get(sprintf('char%d.seriko.defaultsurface', char)).nil?
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
        @__sender = 'ninix-kagari'
      end
    end

    def save_history()
      path = File.join(get_prefix(), 'HISTORY')
      begin
        open(path, 'w') do |file|
          file.write("time, " + @ghost_time.to_s + "\n")
          file.write("vanished_count, " + @vanished_count.to_s + "\n")
        end
      rescue # IOError, SystemCallError => e
        Logging::Logging.error('cannot write ' + path)
      end
    end

    def save_settings()
      path = File.join(get_prefix(), 'SETTINGS')
      begin
        open(path, 'w') do |file|
          unless @balloon_directory.nil?
            file.write("balloon_directory, " + @balloon_directory + "\n")
          end
          unless @shell_directory.nil?
            file.write("shell_directory, " + @shell_directory + "\n")
          end
        end
      rescue # IOError, SystemCallError => e
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
            next unless line.include?(',')
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
        rescue # IOError => e
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
            next unless line.include?(',')
            key, value = line.split(',', 2)
            if key.strip() == 'balloon_directory'
              balloon_directory = value.strip()
            end
            if key.strip() == 'shell_directory'
              shell_directory = value.strip()
            end
          end
        rescue # IOError => e
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
      unless @shiori.nil? or @shiori.load(:dir => @shiori_dir).zero?
        if @shiori.respond_to?("show_description")
          @shiori.show_description()
        end
      else
        Logging::Logging.error(get_selfname + ' cannot load SHIORI(' + @shiori_name + ')')
      end
      @__charset = 'UTF-8' # default
      get_event_response('OnInitialize', :event_type => 'NOTIFY')
      get_event_response('basewareversion',
                         Version.VERSION,
                         'ninix-kagari',
                         Version.NUMBER,
                         :event_type => 'NOTIFY')
    end

    def finalize()
      unless @script_finally.empty? # XXX
        for proc_obj in @script_finally
          proc_obj.call(:flag_break => false)
        end
        @script_finally = []
      end
      if @__temp_mode.zero?
        get_event_response('OnDestroy', :event_type => 'NOTIFY')
        @shiori.unload()
      end
      stop()
    end

    def enter_temp_mode()
      @__temp_mode = 2 if @__temp_mode.zero?
    end

    def leave_temp_mode()
      @__temp_mode = 0
    end

    def is_listening(key)
      return false unless @__listening.include?(key)
      return @__listening[key]
    end

    def on_audio_message(bus, message)
      if message.nil? # XXX: workaround for Gst Version < 0.11
        if @script_mode == WAIT_MODE
          @script_mode = BROWSE_MODE
        end
        return
      end
      t = message.type
      if t == Gst::MessageType::EOS
        @audio_player.set_state(Gst::State::NULL)
        if @script_mode == WAIT_MODE
          fail "assert" if @audio_loop
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
      unless icon.nil?
        icon_path = File.join(@shiori_dir, icon)
        unless File.exist?(icon_path)
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
    end

    def update_balloon_offset(side, x_delta, y_delta)
      return if side >= @char
      ox, oy = @surface.window[side].get_balloon_offset # without scaling
      direction = @balloon.window[side].direction
      sx, sy = get_surface_position(side)
      if direction.zero? # left
        nx = (ox + x_delta)
      else
        w, h = @surface.get_surface_size(side)
        nx = (ox - x_delta)
      end
      ny = (oy + y_delta)
      @surface.set_balloon_offset(side, [nx, ny])
    end

    def enqueue_script(event, script, sender, handle,
                       host, show_sstp_marker, use_translator,
                       db: nil, request_handler: nil, temp_mode: false)
      if temp_mode
        enter_temp_mode()
      end
      if @script_queue.empty? and \
        not @time_critical_session and not @passivemode
        unless @sstp_request_handler.nil?
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

    def enqueue_event(event, *arglist, proc_obj: nil)
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

    def handle_event()
      while not @event_queue.empty?
        event, arglist, proc_obj = @event_queue.shift
        if EVENT_SCRIPTS.include?(event)
          default = EVENT_SCRIPTS[event]
        else
          default = nil
        end
        if notify_event(event, *arglist, :default => default)
          unless proc_obj.nil?
            @script_post_proc << proc_obj
          end
          return true
        elsif not proc_obj.nil?
          proc_obj.call()
          return true
        end
      end
      return false
    end

    def is_running()
      @__running
    end

    def is_paused()
      return [PAUSE_MODE, PAUSE_NOCLEAR_MODE].include?(@script_mode)
    end

    def is_talking()
      unless @processed_script.empty? and @processed_text.empty?
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
              not @sstp_request_handler.nil? or \
              (check_updateman and @updateman.is_active()))
    end

    def get_silent_time()
      @silent_time
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
      idle = (now - @idle_start)
      return idle
    end

    def reset_idle_time()
      @idle_start = Time.new.to_f
    end

    def notify_preference_changed()
      @balloon.reset_fonts()
      @surface.reset_surface()
      notify_observer('set scale')
      @balloon.reset_balloon()
    end

    def get_workarea
      @parent.handle_request(:GET, :get_workarea)
    end

    def get_surface_position(side)
      result = @surface.get_position(side)
      unless result.nil?
        return result
      else
        return [0, 0]
      end
    end

    def set_balloon_position(side, base_x, base_y)
      @balloon.set_position(side, base_x, base_y)
    end

    def set_balloon_direction(side, direction)
      return if side >= @char
      @balloon.window[side].direction = direction
    end

    def get_balloon_size(side)
      result = @balloon.get_balloon_size(side)
      unless result.nil?
        return result
      else
        return [0, 0]
      end
    end

    def get_balloon_windowposition(side)
      @balloon.get_balloon_windowposition(side)
    end

    def get_balloon_position(side)
      result = @balloon.get_position(side)
      unless result.nil?
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

    def open_scriptinputbox()
      @balloon.open_scriptinputbox
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
      @parent.handle_request(:GET, :vanish_sakura, self, next_ghost)
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
      @desc.get('name', :default => default)
    end

    def get_username()
      username = getstring('username')
      if username.nil?
        username = @surface.get_username()
      end
      if username.nil?
        username = @desc.get('user.defaultname', :default => _('User'))
      end
      return username
    end

    def get_selfname(default: _('Sakura'))
      selfname = @surface.get_selfname()
      if selfname.nil?
        selfname = @desc.get('sakura.name', :default => default)
      end
      return selfname
    end

    def get_selfname2()
      selfname2 = @surface.get_selfname2()
      if selfname2.nil?
        selfname2 = @desc.get('sakura.name2', :default => _('Sakura'))
      end
      return selfname2
    end

    def get_keroname()
      keroname = @surface.get_keroname()
      if keroname.nil?
        keroname = @desc.get('kero.name', :default => _('Unyuu'))
      end
      return keroname
    end

    def get_friendname()
      friendname = @surface.get_friendname()
      if friendname.nil?
        friendname = @desc.get('sakura.friend.name', :default => _('Tomoyo'))
      end
      return friendname
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
      get_event_response(name)
    end

    def translate(s, event, embed: false)
      unless s.nil? or s.empty?
        if @use_makoto
          s = Makoto.execute(s)
        else
          r = get_event_response('OnTranslate', s, nil, event, :translate => 0,
                                embed: embed)
          unless r.empty?
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
        line = line.encode("UTF-8", :invalid => :replace, :undef => :replace).strip().gsub(/¥/, '\\')
        next if line.empty?
        next unless line.include?(':')
        key, value = line.split(':', 2)
        key = key.strip()
        if key == 'Charset'
          charset = value.strip()
          if charset != @__charset
            unless Encoding.name_list.include?(charset)
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
      if result.include?('Value') and not result['Value'].empty?
        return result['Value'], to
      else
        return nil, to
      end
    end

    def get_event_response_with_communication(event, *arglist,
        event_type: 'GET', translate: 1, embed: false, fallback: nil)
      return '' if @__temp_mode == 1
      ref = arglist
      header = [event_type.to_s, " SHIORI/3.0\r\n",
                "Sender: ", @__sender.to_s, "\r\n",
                "ID: ", event.to_s, "\r\n",
                "SecurityLevel: local\r\n",
                "Charset: ", @__charset.to_s, "\r\n"].join("")
      # FIXME もっと汎用性を持たせたい。
      if embed
        header = [header, "SenderType: embed", "\r\n"].join
      end
      for i in 0..ref.length-1
        value = ref[i]
        unless value.nil?
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
        result = translate(result, event.to_s, embed: embed) unless translate.zero?
      else
        result, to = '', nil
      end
      result = '' if result.nil?
      unless to.nil? or result.empty?
        communication = to
      else
        communication = nil
      end
      if result.empty? and not fallback.nil?
        return get_event_response(fallback[0], *fallback[1], event_type: event_type, translate: translate, embed: embed)
      end
      return result, communication
    end

    def get_event_response(event, *arglist, event_type: 'GET', translate: 1, embed: false)
      result, communication = get_event_response_with_communication(
                event, *arglist,
                event_type: event_type, translate: translate, embed: embed)
      return result
    end

    ###   CALLBACK   ###
    def notify_start(init, vanished, ghost_changed,
                     name, prev_name, prev_shell, path, last_script,
                     abend: nil)
      unless @__temp_mode.zero?
        default = nil
      else
        default = Version.VERSION_INFO
      end
      if abend.nil?
        on_boot = ['OnBoot', [@surface.name]]
      else
        on_boot = ['OnBoot', [@surface.name, nil, nil, nil, nil, nil, 'halt', abend]]
      end
      if init
        if @ghost_time.zero?
          unless notify_event('OnFirstBoot', @vanished_count,
                              nil, nil, nil, nil, nil, nil,
                              @surface.name, fallback: on_boot)
            unless abend.nil?
              notify_event('OnBoot', @surface.name,
                           nil, nil, nil, nil, nil,
                           'halt', abend, :default => default)
            else
              notify_event('OnBoot', @surface.name,
                           :default => default)
            end
          end
        else
          unless abend.nil?
            notify_event('OnBoot', @surface.name,
                         nil, nil, nil, nil, nil,
                         'halt', abend, :default => default)
          else
            notify_event('OnBoot', @surface.name,
                         :default => default)
          end
        end
        left, top, scrn_w, scrn_h = get_workarea
        notify_event('OnDisplayChange',
                     Gdk::Visual.best_depth,
                     scrn_w, scrn_h, :event_type => 'NOTIFY')
      elsif vanished
        if @ghost_time.zero?
          if notify_event('OnFirstBoot', @vanished_count,
                          nil, nil, nil, nil, nil, nil,
                          @surface.name, fallback: on_boot)
            return
          end
        elsif notify_event('OnVanished', name, fallback: on_boot)
          return
        elsif notify_event('OnGhostChanged', name, last_script,
                           prev_name, nil, nil, nil, nil,
                           pref_shell, fallback: on_boot)
          return
        end
        unless abend.nil?
          notify_event('OnBoot', @surface.name,
                       nil, nil, nil, nil, nil, nil,
                       'halt', abend, :default => default)
        else
          notify_event('OnBoot', @surface.name, :default => default)
        end
      elsif ghost_changed
        if @ghost_time.zero?
          if notify_event('OnFirstBoot', @vanished_count,
                          nil, nil, nil, nil, nil, nil,
                          @surface.name, fallback: on_boot)
            return
          end
        elsif notify_event('OnGhostChanged', name, last_script,
                           prev_name, nil, nil, nil, nil,
                           prev_shell, fallback: on_boot)
          return
        end
        unless abend.nil?
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
          @parent.handle_request(:GET, :vanish_sakura, self, nil)
        }
      }
      enqueue_event('OnVanishSelected', :proc_obj => proc_obj)
      @vanished = true
    end

    def notify_vanish_canceled()
      notify_event('OnVanishCancel')
    end

    def notify_iconified()
      @cantalk = false
      @parent.handle_request(:GET, :select_current_sakura)
      unless @passivemode
        reset_script(:reset_all => true)
        stand_by(true)
        notify_event('OnWindowStateMinimize')
      end
      notify_observer('iconified')
    end

    def notify_deiconified()
      unless @cantalk
        @cantalk = true
        @parent.handle_request(:GET, :select_current_sakura)
        unless @passivemode
          notify_event('OnWindowStateRestore')
        end
      end
      notify_observer('deiconified')
    end

    def notify_link_selection(link_id, text, args, number)
      if @script_origin == FROM_SSTP_CLIENT and \
        not @sstp_request_handler.nil?
        @sstp_request_handler.send_answer(text)
        @sstp_request_handler = nil
      end
      if is_anchor(link_id)
        if link_id[1].start_with?('On')
          notify_event(link_id[1], *args)
        else
          if args.empty?
            notify_event('OnAnchorSelect', link_id[1])
          else
            # TODO: not implemented
          end
        end
      elsif is_URL(link_id)
        browser_open(link_id)
        reset_script(:reset_all => true)
        stand_by(false)
      elsif not @sstp_entry_db.nil?
        # leave the previous sstp message as it is
        start_script(@sstp_entry_db.get(link_id, :default => '\e'))
        @sstp_entry_db = nil
      else
        if link_id.start_with?('On')
          ret = notify_event(link_id, *args)
        else
          if args.empty?
            ret = notify_event('OnChoiceSelect', link_id, text, number)
          else
            # TODO: not implemented
            ret = false
          end
        end
        if not ret
          reset_script(:reset_all => true)
          stand_by(false)
        end
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
          unless @sstp_request_handler.nil?
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
      return if @time_critical_session
      if click == 1
        return if @passivemode and not @processed_script.empty?
        part = @surface.get_touched_region(side, x, y)
        if [1, 2, 3].include?(button)
          num_button = [0, 2, 1][button - 1]
          unless notify_event('OnMouseUp',
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
          unless notify_event('OnMouseUpEx',
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
        unless @sstp_request_handler.nil?
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
      return unless @surface_mouse_motion.nil?
      unless part.empty?
        @surface_mouse_motion = [side, x, y, part]
      else
        @surface_mouse_motion = nil
      end
    end

    def notify_user_teach(word)
      unless word.nil?
        script = translate(get_event_response('OnTeach', word))
        unless script.empty?
          start_script(script)
          @balloon.hide_sstp_message()
        end
      end
    end


    MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    BOOT_EVENT = ['OnBoot', 'OnFirstBoot', 'OnGhostChanged', 'OnShellChanged',
                  'OnUpdateComplete']
    RESET_NOTIFY_EVENT = ['OnVanishSelecting', 'OnVanishCancel']

    def notify_event(event, *arglist, event_type: 'GET', default: nil, embed: false, fallback: nil)
      return false if @time_critical_session and event.start_with?('OnMouse')
      if RESET_NOTIFY_EVENT.include?(event)
        reset_script(:reset_all => true)
      end
      result = get_event_response_with_communication(event, *arglist,
          event_type: event_type, embed: embed)
      unless result.nil?
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
          unless value.nil?
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
          unless result.nil?
            script, communication = result
          else
            script, communication = [default, nil]
          end
        end
        unless script.empty?
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
            :GET, :open_popup_menu, self, arglist[3])
        end
        @parent.handle_request(
          :GET, :notify_other, @key,
          event, get_name(:default => ''),
          get_selfname(:default => ''),
          get_current_shell_name(),
          false, communication,
          nil, false, script, arglist)
        return false
      end
      Logging::Logging.debug('=> "' + script + '"')
      if @__temp_mode == 2
        @parent.handle_request(:GET, :reset_sstp_flag)
        @controller.handle_request(:GET, :reset_sstp_flag) unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
        leave_temp_mode()
      end
      if @passivemode and \
        (event == 'OnSecondChange' or event == 'OnMinuteChange')
        return false
      end
      start_script(script, embed: embed)
      @balloon.hide_sstp_message()
      if BOOT_EVENT.include?(event)
        @script_finally << lambda {|flag_break: false| @surface_bootup }
      end
      proc_obj = lambda {|flag_break: false|
        @parent.handle_request(
          :GET, :notify_other, @key,
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
      @prefix
    end

    def stick_window(flag)
      @surface.window_stick(flag)
    end

    def toggle_bind(side, bind_id)
      @surface.toggle_bind(side, bind_id)
    end

    def get_menu_pixmap()
      path_background, path_sidebar, path_foreground, \
      align_background, align_sidebar, align_foreground = \
                                       @surface.get_menu_pixmap()
      top_dir = @surface.prefix
      ghost_dir = File.join(get_prefix(), 'ghost', 'master')
      name = getstring('menu.background.bitmap.filename')
      unless name.empty?
        name = name.gsub("\\", '/')
        path_background = File.join(top_dir, name)
      end
      if path_background.nil?
        path_background = File.join(ghost_dir, 'menu_background.png')
      end
      unless File.exist?(path_background)
        path_background = nil
      end
      name = getstring('menu.sidebar.bitmap.filename')
      unless name.empty?
        name = name.gsub("\\", '/')
        path_sidebar = File.join(top_dir, name)
      end
      if path_sidebar.nil?
        path_sidebar = File.join(ghost_dir, 'menu_sidebar.png')
      end
      unless File.exist?(path_sidebar)
        path_sidebar = nil
      end
      name = getstring('menu.foreground.bitmap.filename')
      unless name.empty?
        name = name.gsub("\\", '/')
        path_foreground = File.join(top_dir, name)
      end
      if path_foreground.nil?
        path_foreground = File.join(ghost_dir, 'menu_foreground.png')
      end
      unless File.exist?(path_foreground)
        path_foreground = nil
      end
      align = getstring('menu.background.alignment')
      unless align.empty?
        align_background = align
      end
      unless ['lefttop', 'righttop', 'centertop'].include?(align_background)
        align_background = 'lefttop'
      end
      align_background = align_background[0..-4].encode('ascii', :invalid => :replace, :undef => :replace) # XXX
      align = getstring('menu.sidebar.alignment')
      unless align.empty?
        align_sidebar = align
      end
      unless ['top', 'bottom'].include?(align_sidebar)
        align_sidebar = 'bottom'
      end
      align_sidebar = align_sidebar.encode('ascii', :invalid => :replace, :undef => :replace) # XXX
      align = getstring('menu.foreground.alignment')
      unless align.empty?
        align_foreground = align
      end
      unless ['lefttop', 'righttop', 'centertop'].include?(align_foreground)
        align_foreground = 'lefttop'
      end
      align_foreground = align_foreground[0..-4].encode('ascii', :invalid => :replace, :undef => :replace) # XXX
      return path_background, path_sidebar, path_foreground, \
             align_background, align_sidebar, align_foreground
    end

    def get_menu_fontcolor()
      background, foreground = @surface.get_menu_fontcolor()
      color_r = getstring('menu.background.font.color.r')
      color_g = getstring('menu.background.font.color.g')
      color_b = getstring('menu.background.font.color.b')
      begin
        color_r = [0, [255, Integer(color_r)].min].max
        color_g = [0, [255, Integer(color_g)].min].max
        color_b = [0, [255, Integer(color_b)].min].max
      rescue
        #pass
      else
        background = [color_r, color_g, color_b]
      end
      color_r = getstring('menu.foreground.font.color.r')
      color_g = getstring('menu.foreground.font.color.g')
      color_b = getstring('menu.foreground.font.color.b')
      begin
        color_r = [0, [255, Integer(color_r)].min].max
        color_g = [0, [255, Integer(color_g)].min].max
        color_b = [0, [255, Integer(color_b)].min].max
      rescue
        #pass
      else
        foreground = [color_r, color_g, color_b]
      end
      return background, foreground
    end

    def get_mayuna_menu()
      @surface.get_mayuna_menu()
    end

    def get_current_balloon_directory()
      @balloon.get_balloon_directory()
    end

    def get_current_shell()
      @shell_directory
    end

    def get_current_shell_name()
      @shells[get_current_shell()].baseinfo[0]
    end

    def get_default_shell()
      default = @shell_directory or 'master'
      unless @shells.include?(default)
        default = @shells.keys()[0] # XXX
      end
      return default
    end

    def get_balloon_default_id()
      @desc.get('balloon.defaultsurface', :default => '0')
    end

    def select_shell(shell_key)
      fail "assert" unless not @shells.nil? and @shells.include?(shell_key)
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
      fail "assert" unless item == balloon['balloon_dir'][0]
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
        unless @__boot[side]
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
      @parent.handle_request(:GET, :get_preference, 'surface_scale')
    end

    def get_surface_size(side)
      result = @surface.get_surface_size(side)
      unless result.nil?
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
      @surface.get_surface(side)
    end

    def surface_is_shown(side)
      return (@surface and @surface.is_shown(side))
    end

    def get_target_window
      @surface.get_window(0)
    end

    def get_kinoko_position(baseposition)
      side = 0
      x, y = get_surface_position(side)
      w, h = get_surface_size(side)
      if baseposition == 1
        rect = @surface.get_collision_area(side, 'face')
        unless rect.nil?
          x1, y1, x2, y2 = rect
          return (x + ((x2 - x1) / 2).to_i), (y + ((y2 - y1) / 2).to_i)
        else
          return (x + (w / 2).to_i), (y + (h / 4).to_i)
        end
      elsif baseposition == 2
        rect = @surface.get_collision_area(side, 'bust')
        unless rect.nil?
          x1, y1, x2, y2 = rect
          return (x + ((x2 - x1) / 2).to_i), (y + ((y2 - y1) / 2).to_i)
        else
          return (x + (w / 2).to_i), (y + (h / 2).to_i)
        end
      elsif baseposition == 3
        centerx, centery = @surface.get_center(side)
        if centerx.nil?
          centerx = (w / 2).to_i
        end
        if centery.nil?
          centery = (h / 2).to_i
        end
        return x + centerx, y + centery
      else # baseposition == 0 or baseposition not in [1, 2, 3]: # AKF
        centerx, centery = @surface.get_kinoko_center(side)
        if centerx.nil? or centery.nil?
          rect = @surface.get_collision_area(side, 'head')
          unless rect.nil?
            x1, y1, x2, y2 = rect
            return (x + ((x2 - x1) / 2).to_i), (y + ((y2 - y1) / 2).to_i)
          else
            return (x + (w / 2).to_i), (y + (h / 8).to_i)
          end
        end
        return (x + centerx), (y + centery)
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
        unless temp.zero?
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
      fail "assert" unless not @shells.nil? and @shells.include?(shell_key)
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
      if @parent.handle_request(:GET, :get_preference, 'ignore_default').zero? ## FIXME: change prefs key
        balloon_path = @desc.get('deault.balloon.path', :default => '')
        balloon_name = @desc.get('balloon', :default => '')
        unless balloon_path.empty?
          balloon = @parent.handle_request(
            :GET, :find_balloon_by_subdir, balloon_path)
        end
        if balloon.nil? and not balloon_name.empty?
          balloon = @parent.handle_request(
            :GET, :find_balloon_by_name, balloon_name)
        end
      end
      if balloon.nil?
        unless @balloon_directory.nil?
          balloon = @balloon_directory
        else
          balloon = @parent.handle_request(
            :GET, :get_preference, 'default_balloon')
        end
      end
      desc, balloon = @parent.handle_request(
              :GET, :get_balloon_description, balloon)
      set_balloon(desc, balloon)
      if temp.zero?
        load_shiori()
      end
      restart()
      @start_time = Time.new.to_f
      notify_start(
        init, vanished, ghost_changed,
        name, prev_name, prev_shell, surface_dir, last_script, :abend => abend)
      loop do
        @uuid = SecureRandom.uuid
        if @parent.handle_request(:GET, :add_sakura_info, @uuid,
            @desc.get('sakura.name'),
            @desc.get('kero.name'),
            File.join(get_prefix(), ''),
            @desc.get('name')
                                 )
          break
        end
      end
      unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
        @controller = UnixSSTPController.new(@uuid)
        @controller.set_responsible(self)
        @controller.start_servers
      end
      GLib::Timeout.add(10) { do_idle_tasks } # 10[ms]
    end

    def restart()
      load_history()
      @vanished = false
      @__boot = [false, false]
      @old_otherghostname = nil
      reset_script(:reset_all => true)
      @surface.reset_alignment()
      stand_by(true)
      @surface.reset_position()
      reset_idle_time()
      @__running = true
      @force_quit = false
    end

    def stop()
      return unless @__running
      @controller.quit unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
      notify_observer('finalize')
      @__running = false
      save_settings()
      save_history()
      @parent.handle_request(:GET, :rebuild_ghostdb, self, :name => nil)
      hide_all()
      @surface.finalize()
      @balloon.finalize()
      unless @audio_player.nil?
        @audio_player.set_state(Gst::State::NULL)
      end
      @audio_loop = false
    end

    def process_script()
      now = Time.now.localtime
      idle = get_idle_time()
      second = now.sec
      minute = now.min
      if @clock[0] != second
        @ghost_time += 1 if @__temp_mode.zero?
        @parent.handle_request(
          :GET, :rebuild_ghostdb,
          self,
          :name => get_selfname(),
          :s0 => get_surface_id(0),
          :s1 => get_surface_id(1))
        otherghostname = @parent.handle_request(
          :GET, :get_otherghostname, get_selfname())
        if otherghostname != @old_otherghostname
          notify_event('otherghostname', otherghostname,
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
          unless @sstp_request_handler.nil?
            @sstp_request_handler.send_timeout()
            @sstp_request_handler = nil
          end
          unless notify_event('OnChoiceTimeout')
            stand_by(false)
          end
        end
      elsif not @sstp_handle.nil?
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
        unless @parent.handle_request(:GET, :get_preference, 'sink_after_talk').zero?
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
              :GET, :notify_other, @key,
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
      elsif not @surface_mouse_motion.nil?
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
      return false unless @__running
      if @force_quit and not busy() and @processed_script.empty? and @processed_text.empty?
        quit()
      end
      unless @wait_for_animation.nil?
        if @surface.is_playing_animation(@script_side, @wait_for_animation)
          return true
        else
          @wait_for_animation = nil
        end
      end
      unless @__temp_mode.zero?
        process_script()
        if not busy() and \
          @script_queue.empty? and \
          not (not @processed_script.empty? or \
               not @processed_text.empty?)
          if @__temp_mode == 1
            sleep(1.4)
            finalize()
            @parent.handle_request(:GET, :close_ghost, self)
            @parent.handle_request(:GET, :reset_sstp_flag)
            @controller.handle_request(:GET, :reset_sstp_flag) unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
            return false
          else
            @parent.handle_request(:GET, :reset_sstp_flag)
            @controller.handle_request(:GET, :reset_sstp_flag) unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
            leave_temp_mode()
            return true
          end
        else
          return true
        end
      end
      if not @reload_event.nil? and not busy() and \
        not (not @processed_script.empty? or not @processed_text.empty?)
        hide_all()
        Logging::Logging.info('reloading....')
        @shiori.unload()
        @updateman.clean_up() # Don't call before unloading SHIORI
        @parent.handle_request(
          :GET, :stop_sakura, self,
          starter = lambda {|a|
            @parent.handle_request(:GET, :reload_current_sakura, a) },
          self)
        load_settings()
        restart()
        Logging::Logging.info('done.')
        enqueue_event(*@reload_event)
        @reload_event = nil
      end
      # continue network update (enqueue events)
      if @updateman.is_active()
        @updateman.run()
        while true
          event = @updateman.get_event()
          break if event.nil?
          if event[0] == 'OnUpdateComplete' and event[1] == 'changed'
            @reload_event = event
          else
            enqueue_event(*event)
          end
        end
      end
      # process async http
      @client.run
      #
      unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
        @controller.handle_sstp_queue
      end
      process_script()
      return true
    end

    def quit()
      @parent.handle_request(:GET, :remove_sakura_info, @uuid)
      @parent.handle_request(:GET, :stop_sakura, self)
    end

    ###   SCRIPT PLAYER   ###
    def start_script(script, origin: nil, embed: false)
      return if script.empty?
      @parent.handle_request(:GET, :append_script_log, @desc.get('name'), script)
      @last_script = script
      if origin.nil?
        @script_origin = FROM_GHOST
      else
        @script_origin = origin
      end
      # embed用
      processed_script_bak = @processed_script
      reset_script(:reset_all => true)
      @__current_script = script
      if embed
        # nop
      else not script.rstrip().end_with?('\e')
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
      if embed
        @processed_script.concat(processed_script_bak)
      else
        @script_mode = BROWSE_MODE
        @script_wait = nil
        @script_side = 0
        @time_critical_session = false
        @quick_session = false
        set_synchronized_session(:list => [], :reset => true)
        @script_start_time = get_current_time
      end
      return if @processed_script.empty?
      node = @processed_script[0]
      if node[0] == Script::SCRIPT_TAG and node[1] == '\C'
        @processed_script.shift
        @script_position = node[-1]
      elsif not embed
        @balloon.clear_text_all()
      else
        #@balloon.hide_all()
      end
      @balloon.set_balloon_default()
      @current_time = Time.new.to_a
      reset_idle_time()
      unless @parent.handle_request(:GET, :get_preference, 'raise_before_talk').zero?
        raise_all()
      end
    end

    def __yen_e(args)
      # 最初から最後まで1つのクイックセクション内にある場合に
      # バルーンが表示されない問題の対処
      for side in @defer_show
        @balloon.show(side)
      end
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
        chr_id = Integer(args[0])
      rescue ArgumentError
        return
      end
      if chr_id >= 0
        @script_side = chr_id
        @balloon.add_window(@script_side)
        @balloon.set_balloon_default(side: @script_side)
      end
    end

    def __yen_4(args)
      case @script_side
      when 0
        sw, sh = get_surface_size(1)
        sx, sy = get_surface_position(1)
      when 1
        sw, sh = get_surface_size(0)
        sx, sy = get_surface_position(0)
      else
        return
      end
      w, h = get_surface_size(@script_side)
      x, y = get_surface_position(@script_side)
      left, top, scrn_w, scrn_h = get_workarea
      if (sx + (sw / 2).to_i) > (left + (scrn_w / 2).to_i)
        new_x = [x - (scrn_w / 20).to_i, sx - (scrn_w / 20).to_i].min
      else
        new_x = [x + (scrn_w / 20).to_i, sx + (scrn_w / 20).to_i].max
      end
      if x > new_x
        step = -10
      else
        step = 10
      end
      for current_x in x.step(new_x-1, step)
        set_surface_position(@script_side, current_x, y)
      end
      set_surface_position(@script_side, new_x, y)
    end

    def __yen_5(args)
      case @script_side
      when 0
        sw, sh = get_surface_size(1)
        sx, sy = get_surface_position(1)
      when 1
        sw, sh = get_surface_size(0)
        sx, sy = get_surface_position(0)
      else
        return
      end
      w, h = get_surface_size(@script_side)
      x, y = get_surface_position(@script_side)
      left, top, scrn_w, scrn_h = get_workarea
      if (x < (sx + (sw / 2).to_i) and (sx + (sw / 2).to_i) < (x + w)) or
        (sx < (x + (w / 2).to_i) and (x + (w / 2).to_i) < (sx + sw))
        return
      end
      if (sx + (sw / 2).to_i) > (x + (w / 2).to_i)
        new_x = (sx - (w / 2).to_i + 1)
      else
        new_x = (sx + sw - (w / 2).to_i - 1)
      end
      new_x = [new_x, left].max
      new_x = [new_x, left + scrn_w - w].min
      if x > new_x
        step = -10
      else
        step = 10
      end
      for current_x in x.step(new_x-1, step)
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
          balloon_id = (Integer(args[0]) / 2).to_i
        rescue ArgumentError
          balloon_id = 0
        else
          @balloon.set_balloon(@script_side, balloon_id)
        end
      end
    end

    def __yen__b(args)
      filename = args.shift
      kwargs = {}
      index = if args[0] == 'inline'
        kwargs[:inline] = true
        1
      else
        begin
          kwargs[:x] = Integer(args[0])
          kwargs[:y] = Integer(args[1])
        rescue
          return
        end
        2
      end
      for i in index .. args.length - 1
        arg = args[i]
        if arg.start_with?('--option=')
          arg = arg[9 .. -1]
        end
        if arg == 'opaque'
          kwargs[:opaque] = true
        elsif arg == 'use_self_alpha'
          kwargs[:use_self_alpha] = true
        elsif arg.start_with('--clipping=')
          arg = arg[11 .. -1]
          x1, x2, y1, y2 = arg.split(' ', 4)
          begin
            x1 = Integer(x1)
            x2 = Integer(x2)
            y1 = Integer(y1)
            y2 = Integer(y2)
          rescue
            next
          end
          kwargs[:clipping] = [x1, y1, x2 - x1, y2 - y1]
        elsif arg == 'foreground'
          kwargs[:foreground] = true
        elsif arg == 'fixed'
          kwargs[:fixed] = true
        end
      end
      if kwargs[:fixed] and kwargs[:inline]
        kwargs.delete(:fixed)
      end
      filename = Home.get_normalized_path(filename)
      path = File.join(get_prefix(), 'ghost/master', filename)
      if File.file?(path)
        @balloon.append_image(@script_side, path, **kwargs)
      else
        path = [path, '.png'].join('')
        if File.file?(path)
          @balloon.append_image(@script_side, path, **kwargs)
        end
      end
    end

    def __yen_n(args)
      if not args.empty? and expand_meta(args[0]) == 'half'
        @balloon.new_line(@script_side)
        @balloon.set_draw_absolute_x(@script_side, 0)
        @balloon.set_draw_relative_y_char(@script_side, 0.5, use_default_height: false)
      else
        @balloon.new_line(@script_side)
        @balloon.set_draw_absolute_x(@script_side, 0)
        @balloon.set_draw_relative_y_char(@script_side, 1, use_default_height: false)
      end
    end

    def __yen_c(args)
      @balloon.clear_text(@script_side)
    end

    def __set_weight(value, unit)
      begin
        amount = (Integer(value) * unit - 0.01)
      rescue ArgumentError
        amount = 0
      end
      if amount > 0
        @script_wait = (Time.new.to_f + amount)
      end
    end

    def __yen_w(args)
      script_speed = @parent.handle_request(
        :GET, :get_preference, 'script_speed')
      if not @quick_session and script_speed >= 0
        __set_weight(args[0], 0.05) # 50[ms]
      end
    end

    def __yen__w(args)
      script_speed = @parent.handle_request(
        :GET, :get_preference, 'script_speed')
      if not @quick_session and script_speed >= 0
        __set_weight(args[0], 0.001) # 1[ms]
      end
    end

    def __yen___w(args)
      if args.length == 1
        if args[0] == 'clear'
          @script_start_time = get_current_time
        else
          now = get_current_time
          diff = (now[0] - @script_start_time[0]) - (now[1] - @script_start_time[1]) / 1_000_000_000.0
          time = args[0].to_i / 1_000.0
        end
        time = time - diff
        if not @quick_session and script_speed >= 0 and time > 0
          __set_weight(1, time) # 1[ms]
        end
      elsif args.length == 2 and args[0] == 'animation'
        begin
          id = Integer(args[1])
          if @surface.is_playing_animation(@script_side, id)
            @wait_for_animation = id
          end
        rescue ArgumentError
          # nop
        end
      end
    end

    def __yen_t(args)
      @time_critical_session = (not @time_critical_session)
    end

    def __yen__q(args)
      @quick_session = (not @quick_session)
      if @quick_session
        @defer_show = []
      else
        for side in @defer_show
          @balloon.show(side)
        end
      end
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
      is_deprecated = args.shift
      if is_deprecated # traditional syntax
        num, link_id, text = args
        args = []
        newline_required = true
      else # new syntax
        text, link_id, args = args
      end
      text = expand_meta(text)
      @balloon.append_link(@script_side, link_id, text, args)
      if newline_required
        __yen_n([])
      end
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
      for i in 1.step(args.length-1, 2)
        link = expand_meta(args[i])
        text = expand_meta(args[i + 1])
        @balloon.append_link(@script_side, link, text)
      end
      @script_mode = SELECT_MODE
    end

    def __yen__a(args)
      unless @anchor.nil?
        anchor_id = @anchor[0]
        args = @anchor[0].pop
        text = @anchor[1]
        @balloon.append_link_out(@script_side, anchor_id, text, args)
        @anchor = nil
      else
        anchor_id = args.shift[0][1]
        @anchor = [['anchor', anchor_id, args[0]], '']
        @balloon.append_link_in(@script_side, @anchor[0], args)
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
      @script_start_time = get_current_time
    end

    def __yen_a(args)
      start_script(getaistringrandom())
    end

    def __yen_i(args)
      begin
        actor_id = Integer(args[0])
        @surface.invoke(@script_side, actor_id)
        if args[1] == 'wait'
          @wait_for_animation = actor_id
        end
      rescue ArgumentError
        # nop
      end
    end

    def __yen_j(args)
      jump_id = args[0]
      if is_URL(jump_id)
        browser_open(jump_id)
      elsif not @sstp_entry_db.nil?
        start_script(@sstp_entry_db.get(jump_id, :default => '\e'))
      end
    end

    def __yen_minus(args)
      quit()
    end

    def __yen_plus(args)
      @parent.handle_request(:GET, :select_ghost, self, true)
    end

    def __yen__plus(args)
      @parent.handle_request(:GET, :select_ghost, self, false)
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
      if text.nil?
        text = '?'
      end
      @balloon.append_text(@script_side, text)
    end

    def __yen__m(args)
      begin
        num = Integer(args[0], 16)
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
      re__u = Regexp.new('\A(0x[a-fA-F0-9]{4}|[0-9]{4})\z')
      unless re__u.match(args[0]).nil?
        temp = Integer(re__u.match(args[0])[0])
        temp1 = ((temp & 0xFF00) >> 8)
        temp2 = (temp & 0x00FF)
        text = [temp2, temp1].pack("C*").force_encoding("UTF-16LE").encode("UTF-8", :invalid => :replace, :undef => :replace)
        @balloon.append_text(@script_side, text)
      else
        @balloon.append_text(@script_side, '?')
      end
    end

    def __yen__v(args)
      return if @audio_player.nil?
      filename = expand_meta(args[0])
      filename = Home.get_normalized_path(filename)
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
      return if @audio_player.nil?
      filename = expand_meta(args[0])
      filename = Home.get_normalized_path(filename)
      basename = File.basename(filename)
      ext = File.extname(filename)
      ext = ext.lower()
      return if ext != '.wav'
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
      return if @audio_loop # nothing to do
      if @audio_player.get_state(timeout=Gst::SECOND)[1] == Gst::State::PLAYING
        @script_mode = WAIT_MODE
      end
    end

    def __yen_exclamation(args)
      return if args.empty?
      argc = args.length
      args = args.map {|s| expand_meta(s)}
      if args[0] == 'raise' and argc >= 2
        notify_event(*args[1..])
      elsif args[0] == 'raiseother' and argc >= 3
        @parent.handle_request(:GET, :raise_other, args[1], @key, *args[2..])
      elsif args[0] == 'embed' and argc >= 2
        notify_event(*args[1..], embed: true)
      elsif args[0, 2] == ['open', 'readme']
        path = @desc.get('readme')
        path = 'readme.txt' if path.nil?
        charset = @desc.get('readme.charset')
        charset = 'CP932' if charset.nil?
        ReadmeDialog.new.show(get_name(), get_prefix(), path, charset)
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
        @parent.handle_request(:GET, :edit_preferences)
      elsif args[0, 2] == ['close', 'inputbox'] and argc > 2
        @balloon.close_inputbox(args[2])
      elsif args[0, 2] == ['close', 'communicatebox']
        @balloon.close_communicatebox
      elsif args[0, 2] == ['close', 'teachbox']
        @balloon.close_teachbox
      elsif args[0, 2] == ['change', 'balloon'] and argc > 2
        key = @parent.handle_request(:GET, :find_balloon_by_name, args[2])
        unless key.nil?
          desc, balloon = @parent.handle_request(
                  :GET, :get_balloon_description, key)
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
          @parent.handle_request(:GET, :select_ghost, self, false, :event => 0)
        else
          @parent.handle_request(
            :GET, :select_ghost_by_name, self, args[2], :event => 0)
        end
      elsif args[0, 2] == ['call', 'ghost'] and argc > 2
        ## FIXME: 'random', 'lastinstalled'対応
        key = @parent.handle_request(:GET, :find_ghost_by_name, args[2])
        unless key.nil?
          @parent.handle_request(:GET, :start_sakura_cb, key, :caller => self)
        end
      elsif args[0, 1] == ['updatebymyself']
        unless busy(:check_updateman => false)
          __update()
        end
      elsif args[0, 1] == ['vanishbymyself']
        @vanished = true
        if argc > 1
          next_ghost = args[1]
        else
          next_ghost = nil
        end
        vanish_by_myself(next_ghost)
      elsif args[1, 1] == ['repaint']
        if args[0, 1] == ['lock']
          @lock_repaint = [true, args[2] == 'manual']
        elsif args[0, 1] == ['unlock']
          @lock_repaint = [false, false]
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
              :GET, :set_collisionmode, true, :rect => true)
          else
            @parent.handle_request(
              :GET, :set_collisionmode, true)
          end
        elsif args[0, 1] == ['leave']
          @parent.handle_request(
            :GET, :set_collisionmode, false)
        end
      elsif args[0, 2] == ['set', 'alignmentondesktop'] and argc > 2
        case args[2]
        when 'bottom'
          unless @synchronized_session.empty?
            for chr_id in @synchronized_session
              align_bottom(chr_id)
            end
          else
            align_bottom(@script_side)
          end
        when 'top'
          unless @synchronized_session.empty?
            for chr_id in @synchronized_session
              align_top(chr_id)
            end
          else
            align_top(@script_side)
          end
        when 'free'
          unless @synchronized_session.empty?
            for chr_id in @synchronized_session
              @surface.set_alignment(chr_id, 2)
            end
          else
            @surface.set_alignment(@script_side, 2)
          end
        when 'default'
          @surface.reset_alignment()
        end
      elsif args[0, 2] == ['set', 'autoscroll'] and argc > 2
        case args[2]
        when 'disable'
          @balloon.set_autoscroll(false)
        when 'enable'
          @balloon.set_autoscroll(true)
        else
          #pass ## FIXME
        end
      elsif args[0, 2] == ['set', 'windowstate'] and argc > 2
        case args[2]
        when 'minimize'
          @surface.window_iconify(true)
          ##elsif args[2] == '!minimize':
          ##    @surface.window_iconify(false)
        when 'stayontop'
          @surface.window_stayontop(true)
        when '!stayontop'
          @surface.window_stayontop(false)
        end
      elsif args[0, 2] == ['set', 'trayicon'] and argc > 2 ## FIXME: tasktrayicon
        path = File.join(get_prefix(), args[2])
        if File.exist?(path)
          @status_icon.set_from_file(path) # XXX
        end
        if argc > 3
          text = args[3]
          unless text.empty?
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
          unless options.include?(args[3])
            opt = nil
          else
            opt = options[args[3]]
          end
        end
        if opt.nil?
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
          x = Integer(args[2])
          y = Integer(args[3])
        rescue ArgumentError
          #pass
        else
          @surface.set_balloon_offset(@script_side, [x, y])
        end
      elsif args[0] == 'sound' and argc > 1
        command = args[1]
        return if @audio_player.nil?
        if command == 'stop'
          @audio_player.set_state(Gst::State::NULL)
          @audio_loop = false
        elsif command == 'play' and argc > 2
          filename = args[2]
          filename = Home.get_normalized_path(filename)
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
            track = Integer(args[2])
          rescue ArgumentError
            return
          end
          @audio_player.set_property(
            'uri', 'cdda://' + track.to_s)
          @audio_loop = false
          @audio_player.set_state(Gst::State::PLAYING)
        elsif command == 'loop' and argc > 2
          filename = args[2]
          filename = Home.get_normalized_path(filename)
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
          return if @audio_loop # nothing to do
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
        if args[1] == 'true' ## FIXME: '1'でも可
          @quick_session = true
        elsif args[1] == 'false' ## FIXME: '0'でも可
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
          next if category != group[0]
          next if not name.empty? and name != group[1]
          if ['true', '1'].include?(flag)
            next if bind[key][1]
          elsif ['false', '0'].include?(flag)
            next unless bind[key][1]
          else # 'toggle'
            #pass
          end
          @surface.toggle_bind(@script_side, key)
        end
      elsif args[0] == 'execute'
        case args[1]
        when 'http-get', 'http-post', 'http-head', 'http-put', 'http-delete'
          unless args[2].nil?
            url = args[2]
            method = args[1][5..]
            query = nil
            header = {}
            file = nil
            blocking = true
            event = nil
            charset = "UTF-8"
            timeout = 60
            options = args[3..]
            options.each do |option|
              if option.start_with?('--async=')
                event = option[8 .. ]
                blocking = false
              elsif option.start_with?('--authorization=')
                header["Authorization"] = option[16 .. ]
              elsif option.start_with?('--cookie=')
                header["Cookie"] = option[9 .. ]
              elsif option.start_with?('--content-type=')
                header["Content-Type"] = option[15 .. ]
              elsif option.start_with?('--file=')
                file = option[7 .. ]
              elsif option.start_with?('--header=')
                h = option[9 .. ]
                index = s.index(/:/)
                if index.nil?
                  next
                end
                k = h[0, i]
                v = h[i + 1 .. ].match(/\A *(.+)\z/)[1]
                header[k] = v
              elsif option.start_with?('--log=')
                # TODO stub
              elsif option.start_with?('--nodescript=')
                # TODO stub
              elsif option.start_with?('--nofile=')
                file = false
              elsif option.start_with?('--param=')
                p = option[8 .. ]
                encoded = URI.encode_www_form_component(p.encode(charset))
                if query.nil?
                  query = encoded
                else
                  query = query + '&' + encoded
                end
              elsif option.start_with?('--param-charset=')
                charset = option[16 .. ]
              elsif option.start_with?('--param-input-file=')
                filename = option[19 .. ]
                path = File.join(get_prefix(), 'ghost/master', filename)
                path = Pathname.new(path).cleanpath.to_s
                unless path.start_with?(get_prefix())
                  next
                end
                File.open(path, 'rb') do |fh|
                  # バイナリで読み込んでくれてるか?
                  query = fh.read(nil)
                end
              elsif option == '--progress-notify'
                # TODO stub
              elsif option.start_with?('--sync=')
                event = option[7 .. ]
                blocking = true
              elsif option.start_with?('--timeout=')
                t = option[10 .. ].to_i
                unless t > 0 and t <= 300
                  next
                end
                timeout = t
              else
                query = option
              end
            end
            @client.enqueue(url, {
              method: method,
              query: query,
              timeout: timeout,
              header: header.empty? ? nil : header,
            }, {
              method: method,
              url: url,
              filename: file,
              event: event,
            }, blocking: blocking)
            if blocking
              @client.run
            end
          end
        else
          # TODO stub
        end
      elsif args[1] == 'property'
        if args[0] == 'get'
          event = args[2]
          keys = args[3 .. ]
          values = []
          keys.each do |key|
            values << get_property(key)
          end
          enqueue_event(event, *values)
        end
      elsif args[0] == 'anim' and not args[2].nil?
        id = args[2].to_i
        case args[1]
        when 'clear'
          @surface.change_animation_state(@script_side, id, :clear)
        when 'pause'
          @surface.change_animation_state(@script_side, id, :pause)
        when 'resume'
          @surface.change_animation_state(@script_side, id, :resume)
        when 'offset'
          unless args[3].nil? or args[4].nil?
            x = args[3].to_i
            y = args[4].to_i
            @surface.change_animation_state(@script_side, id, :offset, x, y)
          end
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
      kwargs = {}
      if args.length == 1
        if args[0] == 'default'
          kwargs = {
            height: 'default',
            color: 'default',
            bold: 'default',
            italic: 'default',
            strike: 'default',
            underline: 'default',
            sub: 'default',
            sup: 'default',
          }
        elsif args[0] == 'disable'
          kwargs = {
            height: 'disable',
            color: 'disable',
            bold: 'disable',
            italic: 'disable',
            strike: 'disable',
            underline: 'disable',
            sub: 'disable',
            sup: 'disable',
          }
        else
          return
        end
        @balloon.append_meta(@script_side, **kwargs)
        return
      end
      return if args.length != 2 ## FIXME
      if args[0] == 'height'
        if args[1] == 'default'
          kwargs[:height] = 'default'
        else
          relative = false
          rate = false
          if args[1].start_with?('+') or args[1].start_with?('-')
            relative = true
            args[1] = args[1][1 .. -1]
          end
          if args[1].end_with?('%')
            rate = true
            args[1] = args[1][0 .. -2]
          end
          begin
            value = Float(args[1])
          rescue
            return
          end
          kwargs[:height] = [value, relative, rate]
        end
      elsif args[0] == 'color'
        kwargs[:color] = args[1]
      elsif args[0] == 'bold'
        if ['true', '1'].include?(args[1])
          kwargs[:bold] = true
        elsif ['false', '0'].include?(args[1])
          kwargs[:bold] = false
        end
      elsif args[0] == 'italic'
        if ['true', '1'].include?(args[1])
          kwargs[:italic] = true
        elsif ['false', '0'].include?(args[1])
          kwargs[:italic] = false
        end
      elsif args[0] == 'strike'
        if ['true', '1'].include?(args[1])
          kwargs[:strike] = true
        elsif ['false', '0'].include?(args[1])
          kwargs[:strike] = false
        end
      elsif args[0] == 'underline'
        if ['true', '1'].include?(args[1])
          kwargs[:underline] = true
        elsif ['false', '0'].include?(args[1])
          kwargs[:underline] = false
        end
      elsif args[0] == 'sup'
        if ['true', '1'].include?(args[1])
          kwargs[:sup] = true
        elsif ['false', '0'].include?(args[1])
          kwargs[:sup] = false
        end
      elsif args[0] == 'sub'
        if ['true', '1'].include?(args[1])
          kwargs[:sub] = true
        elsif ['false', '0'].include?(args[1])
          kwargs[:sub] = false
        end
      else
        #pass ## FIXME
      end
      unless kwargs.empty?
        @balloon.append_meta(@script_side, **kwargs)
      end
    end

    def __yen__l(args)
      is_absolute = true
      is_pixel = true
      pos = expand_meta(args[0]).split(',', 2)
      @balloon.new_line(@script_side)
      for i in 0..1
        x = pos[i]
        if x.empty?
          func = 'set_draw_relative_'
          if i == 0
            func += 'x'
          elsif i == 1
            func += 'y'
          end
          @balloon.method(func).call(@script_side, 0)
        else
          if x.start_with?('@')
            is_absolute = false
            x = x[1..-1]
          end
          begin
            if x.end_with?('em')
              is_pixel = false
              v = Float(x[0..-3])
            elsif x.end_with?('%')
              is_pixel = false
              v = Float(x[0..-2]) / 100
            else
              v = Float(x)
            end
            func = 'set_draw_'
            if is_absolute
              func += 'absolute_'
            else
              func += 'relative_'
            end
            if i == 0
              func += 'x'
            elsif i == 1
              func += 'y'
            end
            if not(is_pixel)
              func += '_char'
            end
            @balloon.method(func).call(@script_side, v)
          rescue
            # nop
            func = 'set_draw_relative_'
            if i == 0
              func += 'x'
            elsif i == 1
              func += 'y'
            end
            @balloon.method(func).call(@script_side, 0)
          end
        end
      end
    end

    def __yen___q(args)
      unless @choice.nil?
        choice_id, args, text = @choice
        @balloon.append_link_out(@script_side, choice_id, text, args)
        @choice = nil
      else
        choice_id = args.shift[0][1]
        @choice = [choice_id, args[0], '']
        @balloon.append_link_in(@script_side, @choice[0], @choice[1])
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
      '\__w' => "__yen___w",
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
      '\C' => nil, # dummy
      '\_l' => "__yen__l",
      '\__q' => "__yen___q",
    }

    def interpret_script()
      unless @script_wait.nil?
        return if Time.new.to_f < @script_wait
        @script_wait = nil
      end
      unless @processed_text.empty?
        @balloon.show(@script_side)
        balloon_win = @balloon.get_window(@script_side)
        surface_win = @surface.get_window(@script_side)
        balloon_win.window.restack(surface_win.window, true)
        @balloon.append_text(@script_side, @processed_text[0])
        @processed_text = @processed_text[1..-1]
        surface_id = get_surface_id(@script_side)
        count = @balloon.get_text_count(@script_side)
        if @surface.invoke_talk(@script_side, surface_id, count)
          @balloon.reset_text_count(@script_side)
        end
        script_speed = @parent.handle_request(
          :GET, :get_preference, 'script_speed')
        if script_speed > 0
          @script_wait = (Time.new.to_f + script_speed * 0.02)
        end
        return
      end
      node = @processed_script.shift
      @script_position = node[-1]
      case node[0]
      when Script::SCRIPT_TAG
        name, args = node[1], node[2..-2]
        if SCRIPT_TAG.include?(name) and \
           Sakura.method_defined?(SCRIPT_TAG[name])
          method(SCRIPT_TAG[name]).call(args)
        else
          #pass ## FIMXE
        end
      when Script::SCRIPT_TEXT
        text = expand_meta(node[1])
        unless @anchor.nil?
          @anchor[1] = [@anchor[1], text].join('')
        end
        unless @choice.nil?
          @choice[2] = [@choice[2], text].join('')
        end
        script_speed = @parent.handle_request(
          :GET, :get_preference, 'script_speed')
        if not @quick_session and script_speed >= 0
          @processed_text = text
        else
          @balloon.append_text(@script_side, text)
          @defer_show << @script_side if @quick_session and
            not @defer_show.include?(@script_side)
        end
      end
    end

    def reset_script(reset_all: false)
      if reset_all
        @script_mode = BROWSE_MODE
        unless @script_finally.empty?
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
      @lock_repaint = [false, false] unless @lock_repaint[1] # SSP compat
      @defer_show = []
      set_synchronized_session(:list => [], :reset => true)
      @balloon.set_autoscroll(true)
      reset_idle_time()
    end

    def set_synchronized_session(list: [], reset: false)
      if reset
        @synchronized_session = []
      elsif list.empty?
        unless @synchronized_session.empty?
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
      property_regexp = Regexp.new(/\A%property\[((\\\\|\\\]|(?!\\\\|\\\]).)+?)\]\z/)
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
          left, top, scrn_w, scrn_h = get_workarea
          buf << scrn_w.to_s
        elsif chunk[1] == '%screenheight'
          left, top, scrn_w, scrn_h = get_workarea
          buf << scrn_h.to_s
        elsif chunk[1] == '%et'
          buf << @current_time[5].to_s[-1] + '万年'
        elsif chunk[1] == '%wronghour'
          wrongtime = (Time.new.to_f + [-2, -1, 1, 2].sample * 3600)
          buf << time.localtime(wrongtime)[3].to_s
        elsif chunk[1] == '%exh'
          buf << get_uptime().to_s
        elsif ['%ms', '%mz', '%ml', '%mc', '%mh', \
               '%mt', '%me', '%mp', '%m?'].include?(chunk[1])
          buf << getword(["\\", chunk[1][1..-1]].join(''))
        elsif chunk[1] == '%dms'
          buf << getdms()
        elsif property_regexp.match?(chunk[1])
          key = property_regexp.match(chunk[1])[1]
          buf << (get_property(key) or '')
        else # %c, %songname
          buf << chunk[1]
        end
      end
      return buf.join('')
    end

    ###   SEND SSTP/1.3   ###
    def _send_sstp_handle(data)
      return if IO.select([], [@sstp_handle], [], 0).nil?
      begin
        @sstp_handle.send([data, "\n"].join(''))
      rescue SystemCallError => e
        #pass
      end
    end

    def write_sstp_handle(data)
      return if @sstp_handle.nil?
      _send_sstp_handle(['+', data].join(''))
      ##Logging::Logging.debug('write_sstp_handle(' + data.to_s + ')')
    end

    def close_sstp_handle()
      return if @sstp_handle.nil?
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
      return if @updateman.is_active()
      homeurl = getstring('homeurl')
      if homeurl.empty?
        homeurl = @desc.get('homeurl')
      end
      if homeurl.nil?
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

    def get_general_property(key)
      case key
      when 'name'
      when 'sakuraname'
      when 'keroname'
      when 'craftmanw'
      when 'craftmanurl'
      end
      return nil
    end

    def get_property(key)
      if key.start_with?('currentghost.')
        key = key[13 .. ]
        if false
          # TODO stub
        else
          return get_general_property(key)
        end
      else
        return @parent.handle_request(:GET, :get_property, key)
      end
      return nil
    end

    def get_current_time
      now = Time.now
      return [now.to_i, now.nsec]
    end
  end

  class VanishDialog

    include GetText

    bindtextdomain("ninix-kagari")
    
    def initialize
      @parent = nil # dummy
      @dialog = Gtk::Dialog.new
      @dialog.signal_connect('delete_event') do |a|
        next true # XXX
      end
      @dialog.set_title('Vanish')
      @dialog.set_modal(true)
      @dialog.set_resizable(false)
      @dialog.set_window_position(Gtk::WindowPosition::CENTER)
      @label = Gtk::Label.new(label=_('Vanish'))
      content_area = @dialog.content_area
      content_area.add(@label)
      @label.show()
      @dialog.add_button("_Yes", Gtk::ResponseType::YES)
      @dialog.add_button("_No", Gtk::ResponseType::NO)
      @dialog.signal_connect('response') do |w, e|
        next response(w, e)
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
      @parent.handle_request(:GET, :notify_vanish_selected)
      return true
    end

    def cancel()
      @dialog.hide()
      @parent.handle_request(:GET, :notify_vanish_canceled)
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
        next true # XXX
      end
      @dialog.set_title('Readme.txt')
      @dialog.set_modal(false)
      @dialog.set_resizable(false)
      @dialog.set_window_position(Gtk::WindowPosition::CENTER)
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
        next response(w, e)
      end
    end

    def set_responsible(parent)
      @parent = parent
    end

    def show(name, base_path, readme, charset)
      @label.set_text(name)
      path = File.join(base_path, readme)
      path = CaseInsensitiveFile.exist?(path)
      if not path.nil? and File.file?(path)
        f = open(path)
        text = f.read()
        text = text.force_encoding(charset).encode("UTF-8", :invalid => :replace, :undef => :replace) # XXX
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
