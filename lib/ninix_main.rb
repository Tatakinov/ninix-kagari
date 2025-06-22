# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003-2005 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'optparse'
require 'uri'
require 'gettext'
require 'gtk3'
require 'ninix-fmo'

require_relative "ninix/pix"
require_relative "ninix/home"
require_relative "ninix/prefs"
require_relative "ninix/sakura"
require_relative "ninix/sstp"
require_relative "ninix/communicate"
require_relative "ninix/ngm"
require_relative "ninix/lock"
require_relative "ninix/install"
require_relative "ninix/nekodorif"
require_relative "ninix/kinoko"
require_relative "ninix/menu"
require_relative "ninix/metamagic"
require_relative "ninix/logging"
require_relative "ninix/version"
require_relative "ninix/ninix_server"
require_relative "ninix/error"
require_relative "ninix/sstp_controller"
require_relative "ninix/script_log"

module Ninix_Main
  include GetText
  bindtextdomain("ninix-kagari")

  def self.handleException(exception)
    message = ("Uncaught exception (#{exception.class})\n" + exception.backtrace.join("\n"))
    Logging::Logging.error(message)
    response_id = 1
    dialog = Gtk::MessageDialog.new(
      :parent => nil,
      :flags => 0,
      :type => Gtk::MessageType::ERROR,
      :buttons => Gtk::ButtonsType::NONE,
      :message => _("A ninix-kagari error has been detected."))
    dialog.set_title(_("Bug Detected"))
    dialog.set_window_position(Gtk::WindowPosition::CENTER)
    dialog.gravity = Gdk::Gravity::CENTER
    button = dialog.add_button(_("Show Details"), response_id)
    dialog.add_button("_Close", Gtk::ResponseType::CLOSE)
    textview = Gtk::TextView.new
    textview.set_editable(false)
    scrn = Gdk::Screen.default
    width = (scrn.width / 2).to_i
    height = (scrn.height / 4).to_i
    textview.set_size_request(width, height)
    textview.show()
    sw = Gtk::ScrolledWindow.new
    sw.show()
    sw.set_policy(Gtk::PolicyType::AUTOMATIC, Gtk::PolicyType::AUTOMATIC)
    sw.add(textview)
    frame = Gtk::Frame.new
    frame.set_shadow_type(Gtk::ShadowType::IN)
    frame.add(sw)
    frame.set_border_width(7)
    frame.set_size_request(480, 320) # XXX
    content_area = dialog.content_area
    content_area.add(frame)
    textbuffer = textview.buffer
    textbuffer.set_text(message)
    while true
      break unless dialog.run() == response_id # close button
      frame.show()
      button.set_sensitive(false)
    end
    dialog.destroy()
    fail SystemExit
  end

  class BalloonMeme < MetaMagic::Meme

    def create_menuitem(data)
      desc, balloon = data
      subdir = balloon['balloon_dir'][0]
      name = desc.get('name', :default => subdir)
      home_dir = Home.get_ninix_home()
      thumbnail_path = File.join(home_dir, 'balloon',
                                 subdir, 'thumbnail.png')
      thumbnail_path = nil unless File.exist?(thumbnail_path)
      return handle_request(
               'GET', 'create_balloon_menuitem', name, @key, thumbnail_path)
    end

    def delete_by_myself
      handle_request('NOTIFY', 'delete_balloon', @key)
    end
  end

  class Ghost < MetaMagic::Holon

    def create_menuitem(data)
      @parent.handle_request('GET', 'create_menuitem', @key, data)
    end

    def delete_by_myself
      @parent.handle_request('NOTIFY', 'delete_ghost', @key)
    end

    def create_instance(data)
      @parent.handle_request('GET', 'create_ghost', data)
    end
  end

  class Application

    def initialize(lockfile, shm, sstp_port: [9801, 11000], ghost: nil)
      @lockfile = lockfile
      @abend = nil
      @loaded = false
      @confirmed = false
      @console = Console.new(self)
      Logging::Logging.info("loading...")
      # create preference dialog
      @prefs = Prefs::PreferenceDialog.new
      @prefs.set_responsible(self)
      @sstp_controler = TCPSSTPController.new(sstp_port)
      @sstp_controler.set_responsible(self)
      # create usage dialog
      @usage_dialog = UsageDialog.new
      @communicate = Communicate::Communicate.new
      # create ghost manager
      @__ngm = NGM::NGM.new
      @__ngm.set_responsible(self)
      @current_sakura = nil
      # create installer
      @installer = Install::Installer.new
      # create popup menu
      @__menu = Menu::Menu.new
      @__menu.set_responsible(self)
      @__menu_owner = nil
      @socket = NinixServer.new('ninix') unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
      @shm = shm
      @init_ghost = ghost
      @sakura_info = {}
      unless ENV.include?('NINIX_DISABLE_UNIX_SOCKET')
        GLib::Timeout.add(10) do
          begin
            soc = @socket.accept_nonblock
          rescue IO::WaitReadable, Errno::EINTR
            next true
          end
          buffer = []
          for key, value in @sakura_info
            for k, v in value
              buffer << key + '.' + k.to_s + "\x01" + v.to_s
            end
          end
          data = buffer.join("\x0d\x0a") + "\x0d\x0a\x00"
          Thread.start(soc, data) do |s, d|
            s.write([d.bytesize].pack('L*'))
            s.write([d].pack('a*'))
            s.close
          end
          next true
        end
      end
      @script_log = ScriptLog::Window.new

      @ghosts = {} # Ordered Hash
      odict_baseinfo = Home.search_ghosts()
      for key, value in odict_baseinfo
        holon = Ghost.new(key)
        holon.set_responsible(self)
        @ghosts[key] = holon 
        holon.baseinfo = value
      end
      @balloons = {} # Ordered Hash
      odict_baseinfo = Home.search_balloons()
      for key, value in odict_baseinfo
        meme = BalloonMeme.new(key)
        meme.set_responsible(self)
        @balloons[key] = meme
        meme.baseinfo = value
      end
      @balloon_menu = create_balloon_menu()
      @nekoninni = Home.search_nekoninni()
      @katochan = Home.search_katochan()
      @kinoko = Home.search_kinoko()
      Logging::Logging.info("done.")
    end

    def edit_preferences(*arglist)
      @prefs.edit_preferences(*arglist)
    end

    def prefs_get(*arglist)
      @prefs.get(*arglist)
    end

    def get_otherghostname(*arglist)
      @communicate.get_otherghostname(*arglist)
    end

    def rebuild_ghostdb(*arglist, **kwarg)
      @communicate.rebuild_ghostdb(*arglist, **kwarg)
    end

    def notify_other(*arglist)
      @communicate.notify_other(*arglist)
    end

    def raise_other(*arglist)
      @communicate.raise_other(*arglist)
    end

    def reset_sstp_flag(*arglist)
      @sstp_controler.reset_sstp_flag(*arglist)
    end

    def get_sstp_port(*arglist)
      @sstp_controler.get_sstp_port(*arglist)
    end

    def handle_request(event_type, event, *arglist, **kwarg)
      fail "assert" unless ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
        'close_all' => 'close_all_ghosts',
        'edit_preferences' => 'edit_preferences',
        'get_preference' => 'prefs_get',
        'get_otherghostname' => 'get_otherghostname',
        'rebuild_ghostdb' =>  'rebuild_ghostdb',
        'notify_other' => 'notify_other',
        'reset_sstp_flag' => 'reset_sstp_flag',
        'get_sstp_port' => 'get_sstp_port',
        'get_prefix' => 'get_sakura_prefix',
        'get_workarea' => 'get_workarea'
      }
      unless handlers.include?(event)
        if Application.method_defined?(event)
          result = method(event).call(*arglist, **kwarg)
        else
          result = nil
        end
      else
        result = method(handlers[event]).call(*arglist, **kwarg)
      end
      return result if event_type == 'GET'
    end

    def set_collisionmode(flag, rect: false)
      @prefs.check_collision_button.set_active(flag)
      @prefs.check_collision_name_button.set_active((not rect))
      @prefs.update(:commit => true) # XXX
      notify_preference_changed()
    end

    def do_install(filename)
      @communicate.notify_all('OnInstallBegin', [])
      begin
        filetype, target_dirs, names, errno = @installer.install(
                                        filename, Home.get_ninix_home())
      rescue
        target_dirs = nil
      end
      unless errno.zero?
        error_reason = {
          1 => 'extraction',
          2 => 'invalid type',
          3 => 'artificial',
          4 => 'unsupported',
        }
        if error_reason.include?(errno)
          @communicate.notify_all('OnInstallFailure', [error_reason[errno]])
        else
          @communicate.notify_all('OnInstallFailure', ['unknown'])
        end
        # XXX: ninix-kagariでは発生しない.
        ##@communicate.notify_all('OnInstallRefuse', [])
      else
        ##@communicate.notify_all('OnInstallCompleteEx', []) # FIXME
        if filetype != 'kinoko'
          if filetype == 'ghost'
            unless target_dirs[1].nil?
              id = 'ghost with balloon'
              name2 = names[1]
            else
              id = filetype
              name2 = nil
            end
            name = names[0]
          else
            id = filetype
            name2 = nil
            name = names
          end
          @communicate.notify_all('OnInstallComplete', [id, name, name2])
        end
      end
      unless target_dirs.nil? or target_dirs.empty?
        case filetype
        when 'ghost'
          add_sakura(target_dirs[0])
          ghost_conf = Home.search_ghosts(:target => [target_dirs[0]])
          desc = ghost_conf[target_dirs[0]][0]
          path = desc.get('readme')
          path = 'readme.txt' if path.nil?
          charset = desc.get('readme.charset')
          charset = 'CP932' if charset.nil?
          Sakura::ReadmeDialog.new.show(
            target_dirs[0],
            File.join(Home.get_ninix_home(),
                      'ghost', target_dirs[0]),
            path, charset)
          unless target_dirs[1].nil?
            add_balloon(target_dirs[1])
            balloon_conf = Home.search_balloons(:target => [target_dirs[1]])
            desc = balloon_conf[target_dirs[1]][0]
            path = desc.get('readme')
            path = 'readme.txt' if path.nil?
            charset = desc.get('readme.charset')
            charset = 'CP932' if charset.nil?
            Sakura::ReadmeDialog.new.show(
              target_dirs[1],
              File.join(Home.get_ninix_home(),
                        'balloon', target_dirs[1]),
              path, charset)
          end
        when 'supplement'
          add_sakura(target_dirs) # XXX: reload
        when 'balloon'
          add_balloon(target_dirs)
          balloon_conf = Home.search_balloons(:target => [target_dirs])
          desc = balloon_conf[target_dirs][0]
          path = desc.get('readme')
          path = 'readme.txt' if path.nil?
          charset = desc.get('readme.charset')
          charset = 'CP932' if charset.nil?
          Sakura::ReadmeDialog.new.show(
            target_dirs,
            File.join(Home.get_ninix_home(),
                      'balloon', target_dirs),
            path, charset)
        when 'nekoninni'
          @nekoninni = Home.search_nekoninni()
        when 'katochan'
          @katochan = Home.search_katochan()
        when 'kinoko'
          @kinoko = Home.search_kinoko()
          @communicate.notify_all('OnKinokoObjectInstalled', names)
        end
      end
    end

    def notify_installedghostname(key: nil)
      installed = []
      for value in @ghosts.values()
        sakura = value.instance
        next if sakura.nil?
        installed << sakura.get_name(:default => '')
      end
      unless key.nil?
        if @ghosts.include?(key)
          sakura = @ghosts[key].instance
          sakura.notify_event('installedghostname', *installed)
        end
      else
        for sakura in get_working_ghost
          sakura.notify_event('installedghostname', *installed)
        end
      end
    end

    def notify_installedballoonname(key: nil)
      installed = []
      for value in @balloons.values()
        desc, balloon = value.baseinfo
        subdir = balloon['balloon_dir'][0]
        installed << desc.get('name', :default => subdir)
      end
      unless key.nil?
        if @ghosts.include?(key)
          sakura = @ghosts[key].instance
          sakura.notify_event('installedballoonname', *installed)
        end
      else
        for sakura in get_working_ghost
          sakura.notify_event('installedballoonname', *installed)
        end
      end
    end

    def current_sakura_instance
      @ghosts[@current_sakura].instance
    end

    def create_ghost(data)
      ghost = Sakura::Sakura.new
      ghost.set_responsible(self)
      ghost.new_(*data)
      return ghost
    end

    def get_sakura_cantalk
      current_sakura_instance.cantalk
    end

    def get_event_response(event, *arglist) ## FIXME
      current_sakura_instance.get_event_response(*event)
    end

    def keep_silence(quiet)
      current_sakura_instance.keep_silence(quiet)
    end

    def get_ghost_name
      sakura = current_sakura_instance
      return sakura.get_ifghost()
    end

    def enqueue_event(event, *arglist)
      current_sakura_instance.enqueue_event(event, *arglist)
    end

    def enqueue_script(event, script, sender, handle,
                       host, show_sstp_marker, use_translator,
                       db: nil, request_handler: nil, temp_mode: false)
      sakura = current_sakura_instance
      sakura.enqueue_script(event, script, sender, handle,
                            host, show_sstp_marker, use_translator,
                            db: db, request_handler: request_handler, temp_mode: temp_mode)
    end

    def get_working_ghost(cantalk: false)
      ghosts = []
      for value in @ghosts.values()
        sakura = value.instance
        next if sakura.nil?
        next unless sakura.is_running()
        next if cantalk and not sakura.cantalk
        ghosts << sakura
      end
      return ghosts
    end

    def get_sakura_prefix
      @__menu_owner.get_prefix()
    end

    def getstring(name)
      @__menu_owner.getstring(name)
    end

    def stick_window
      stick = @__menu.get_stick()
      @__menu_owner.stick_window(stick)
    end

    def toggle_bind(args)
      @__menu_owner.toggle_bind(args)
    end

    def select_shell(key)
      @__menu_owner.select_shell(key)
    end

    def select_balloon(key)
      desc, balloon = get_balloon_description(key)
      @__menu_owner.select_balloon(key, desc, balloon)
    end

    def get_current_balloon_directory
      @__menu_owner.get_current_balloon_directory()
    end

    def start_sakura_cb(key, caller: nil)
      sakura_name = @ghosts[key].instance.get_selfname(:default => '')
      name = @ghosts[key].instance.get_name(:default => '')
      if caller.nil?
        caller = @__menu_owner
      end
      caller.notify_event('OnGhostCalling', sakura_name, 'manual', name, key)
      start_sakura(key, :init => true) # XXX
    end

    def select_sakura(key)
      if @__menu_owner.busy()
        Gdk.beep()
        return
      end
      change_sakura(@__menu_owner, key, 'manual')
    end

    def notify_site_selection(*args)
      @__menu_owner.notify_site_selection(args)
    end

    def close_sakura
      @__menu_owner.close()
    end

    def about
      @__menu_owner.about()
    end

    def vanish
      @__menu_owner.vanish()
    end

    def open_scriptinputbox
      @__menu_owner.open_scriptinputbox()
    end

    def network_update
      @__menu_owner.network_update()
    end

    def open_popup_menu(sakura, side)
      @__menu_owner = sakura
      path_background, path_sidebar, path_foreground, \
      align_background, align_sidebar, align_foreground = \
                                       @__menu_owner.get_menu_pixmap()
      @__menu.set_pixmap(
        path_background, path_sidebar, path_foreground,
        align_background, align_sidebar, align_foreground)
      background, foreground = @__menu_owner.get_menu_fontcolor()
      if background[0] == -1 || background[1] == -1 || background[2] == -1
        background = []
      end
      if foreground[0] == -1 || foreground[1] == -1 || foreground[2] == -1
        foreground = []
      end
      @__menu.set_fontcolor(background, foreground)
      mayuna_menu = @__menu_owner.get_mayuna_menu()
      @__menu.create_mayuna_menu(mayuna_menu)
      @__menu.popup(side)
    end

    def get_ghost_menus
      menus = []
      for value in @ghosts.values()
        menus << value.menuitem
      end
      return menus
    end

    def get_shell_menu
      @__menu_owner.get_shell_menu()
    end

    def get_balloon_menu
      current_key = get_current_balloon_directory()
      for key in @balloons.keys
        menuitem = @balloons[key].menuitem
        menuitem.set_sensitive(key != current_key) # not working
      end
      return @balloon_menu
    end

    def create_balloon_menuitem(balloon_name, balloon_key, thumbnail)
      @__menu.create_meme_menuitem(
        balloon_name, balloon_key, lambda {|v| select_balloon(v) }, thumbnail)
    end

    def create_balloon_menu
      balloon_menuitems = {} # Ordered Hash
      for key in @balloons.keys
        balloon_menuitems[key] = @balloons[key].menuitem
      end
      return @__menu.create_meme_menu(balloon_menuitems)
    end

    def create_shell_menu(menuitems)
      @__menu.create_meme_menu(menuitems)
    end

    def create_shell_menuitem(shell_name, shell_key, thumbnail)
      @__menu.create_meme_menuitem(
        shell_name, shell_key,
        lambda {|key| select_shell(key) }, thumbnail)
    end

    def create_menuitem(key, baseinfo)
      desc = baseinfo[0]
      shiori_dir = baseinfo[1]
      icon = desc.get('icon', :default => nil)
      unless icon.nil?
        icon_path = File.join(shiori_dir, icon)
        unless File.exist?(icon_path)
          icon_path = nil
        end
      else
        icon_path = nil
      end
      name = desc.get('name')
      thumbnail_path = File.join(shiori_dir, 'thumbnail.png')
      unless File.exist?(thumbnail_path)
        thumbnail_path = nil
      end
      start_menuitem = @__menu.create_ghost_menuitem(
        name, icon_path, key, lambda {|key| start_sakura_cb(key) }, # XXX
        thumbnail_path)
      select_menuitem = @__menu.create_ghost_menuitem(
        name, icon_path, key, lambda {|key| select_sakura(key) },
        thumbnail_path)
      menuitem = {
        'Summon' => start_menuitem,
        'Change' => select_menuitem,
      }
      return menuitem
    end

    def delete_ghost(key)
      fail "assert" unless @ghosts.include?(key)
      @ghosts.delete(key)
    end

    def get_balloon_list
      balloon_list = []
      for key in @balloons.keys
        desc, balloon = @balloons[key].baseinfo
        subdir = balloon['balloon_dir'][0]
        name = desc.get('name', :default => subdir)
        balloon_list << [name, subdir]
      end
      return balloon_list
    end

    def get_nekodorif_list
      nekodorif_list = []
      nekoninni = @nekoninni
      for nekoninni_name, nekoninni_dir in nekoninni
        next if nekoninni_name.nil? or nekoninni_name.empty?
        item = {}
        item['name'] = nekoninni_name
        item['dir'] = nekoninni_dir
        nekodorif_list << item
      end
      return nekodorif_list
    end

    def get_kinoko_list
      @kinoko
    end

    def load
      # load user preferences
      @prefs.load()
      Gtk::Settings.default.set_gtk_font_name(@prefs.get('menu_fonts'))
      # choose default ghost/shell
      default_sakura = nil
      directory = @prefs.get('sakura_dir')
      name = @prefs.get('sakura_name') # XXX: backward compat
      unless @init_ghost.nil?
        default_sakura = find_ghost_by_name(@init_ghost)
      end
      if default_sakura.nil?
        default_sakura = find_ghost_by_dir(directory)
      end
      if default_sakura.nil?
        default_sakura = find_ghost_by_name(name)
      end
      if default_sakura.nil?
        default_sakura = choose_default_sakura()
      end
      # load ghost
      @current_sakura = default_sakura
      ##for i, name in enumerate(get_ghost_names())
      ##    Logging::Logging.info("GHOST(#{i}): #{name}")
      ##end
      start_sakura(@current_sakura, :init => true, :abend => @abend)
    end

    def find_ghost_by_dir(directory)
      if @ghosts.include?(directory)
        return directory
      else
        return nil
      end
    end

    def find_ghost_by_name(name)
      for key in @ghosts.keys
        sakura = @ghosts[key].instance
        begin
          if sakura.get_name(:default => nil) == name
            return key
          end
        rescue # old preferences(EUC-JP)
          #pass
        end
      end
      return nil
    end

    def choose_default_sakura
      return @ghosts.keys[0]
    end

    def find_balloon_by_name(name)
      for key in @balloons.keys
        desc, balloon = @balloons[key].baseinfo
        begin
          if desc.get('name') == name
            return key
          end
          if balloon['balloon_dir'][0] == Home.get_normalized_path(name) # XXX
            return key
          end
        rescue # old preferences(EUC-JP)
          #pass
        end
      end
      return nil
    end

    def find_balloon_by_subdir(subdir)
      for key in @balloons.keys
        desc, balloon = @balloons[key].baseinfo
        begin
          if balloon['balloon_dir'][0] == subdir
            return key
          end
          if Home.get_normalized_path(desc.get('name')) == subdir # XXX
            return key
          end
        rescue # old preferences(EUC-JP)
          #pass
        end
      end
      return nil
    end

    def run(abend, app_window, gtk_app)
      @abend = abend
      @app_window = app_window
      @gtk_app = gtk_app
      if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        # The SIGTERM signal is not generated under Windows NT.
        # Win32::Console::API.SetConsoleCtrlHandler will probably not be implemented.
      else
        Signal.trap(:TERM) {|signo| close_all_ghosts(:reason => 'shutdown') }
      end
      @timeout_id = GLib::Timeout.add(100) { do_idle_tasks } # 100[ms]
    end

    def get_ghost_names
      for value in @ghosts.values()
        unless value.instance.nil?
          yield value.instance.get_selfname() ## FIXME
        end
      end
    end

    def if_ghost(if_ghost, working: false)
      instance_list = []
      for value in @ghosts.values()
        unless value.instance.nil?
          instance_list << value.instance
        end
      end
      for sakura in instance_list
        if working
          next unless sakura.is_running() and sakura.cantalk
        end
        return true if sakura.ifghost(if_ghost)
      end
      return false
    end

    def update_sakura(name, sender)
      key = find_ghost_by_name(name)
      return if key.nil?
      sakura = @ghosts[key].instance
      unless sakura.is_running()
        start_sakura(key, :init => true)
      end
      sakura.enqueue_script(nil, '\![updatebymyself]\e', sender,
                            nil, nil, false, false, :db => nil)
    end

    def select_current_sakura(ifghost: nil)
      unless ifghost.nil?
        break_flag = false
        for value in @ghosts.values()
          sakura = value.instance
          next if sakura.nil?
          if sakura.ifghost(ifghost)
            unless sakura.is_running()
              @current_sakura = value.key
              start_sakura(@current_sakura, :init => true, :temp => 1)
            else
              @current_sakura = sakura.key
            end
            break
          else
            #pass
          end
        end
        return unless break_flag
      else
        working_list = get_working_ghost(:cantalk => true)
        unless working_list.empty?
          @current_sakura = working_list.sample.key
        else
          return
        end
      end
    end

    def set_menu_sensitive(key, flag)
      menuitems = @ghosts[key].menuitem
      for item in menuitems.values()
        item.set_sensitive(flag)
      end
    end

    def close_ghost(sakura)
      if get_working_ghost.empty?
        @prefs.set_current_sakura(sakura.key)
        quit()
      elsif @current_sakura == sakura.key
        select_current_sakura()
      end
    end

    def close_all_ghosts(reason: 'user')
      for sakura in get_working_ghost
        sakura.notify_event('OnCloseAll', reason)
      end
    end

    def quit
      GLib::Source.remove(@timeout_id)
      @usage_dialog.close()
      @sstp_controler.quit() ## FIXME
      save_preferences()
      @gtk_app.quit
    end

    def save_preferences
      begin
        @prefs.save()
      rescue # IOError, SystemCallError
        Logging::Logging.error('Cannot write preferences to file (ignored).')
      rescue
        #pass ## FIXME
      end
    end

    def select_ghost(sakura, sequential, event: 1, vanished: false)
      keys = @ghosts.keys
      return if keys.length < 2
      # select another ghost
      if sequential
        key = keys[(keys.index(sakura.key) + 1) % keys.length]
      else
        keys.delete(sakura.key)
        key = keys.sample
      end
      change_sakura(sakura, key, 'automatic', :event => event, :vanished => vanished)
    end

    def select_ghost_by_name(sakura, name, event: 1, vanished: false)
      key = find_ghost_by_name(name)
      return if key.nil?
      change_sakura(sakura, key, 'automatic', :event => event, :vanished => vanished)
    end

    def change_sakura(sakura, key, method, event: 1, vanished: false)
      return if sakura.key == key # XXX: needs reloading?
      proc_obj = lambda { stop_sakura(
                            sakura,
                            lambda {|key, prev|
                              start_sakura(key, :prev => prev) },
                            key, sakura.key) }
      if vanished
        sakura.finalize()
        start_sakura(key, :prev => sakura.key, :vanished => vanished)
        close_ghost(sakura)
      elsif event.zero?
        proc_obj.call()
      else
        sakura_name = @ghosts[key].instance.get_selfname(:default => '')
        name = @ghosts[key].instance.get_name(:default => '')
        sakura.enqueue_event(
          'OnGhostChanging', sakura_name, method, name, key,
          :proc_obj => proc_obj)
      end
    end

    def stop_sakura(sakura, starter=nil, *args)
      sakura.finalize()
      unless starter.nil?
        starter.call(*args)
      end
      set_menu_sensitive(sakura.key, true)
      close_ghost(sakura)
    end

    def start_sakura(key, prev: nil, vanished: false, init: false, temp: 0, abend: nil)
      sakura = @ghosts[key].instance
      fail "assert" if sakura.nil?
      unless prev.nil?
        fail "assert" unless @ghosts.include?(prev) ## FIXME: vanish case?
        fail "assert" if @ghosts[prev].instance.nil?
      end
      if init
        ghost_changed = false
      else
        fail "assert" if prev.nil? ## FIXME
        if prev == key
          ghost_changed = false
        else
          ghost_changed = true
        end
      end
      if ghost_changed
        self_name = @ghosts[prev].instance.get_selfname()
        name = @ghosts[prev].instance.get_name()
        shell = @ghosts[prev].instance.get_current_shell_name()
        last_script = @ghosts[prev].instance.last_script
      else
        self_name = nil
        name = nil
        shell = nil
        last_script = nil
      end
      sakura.notify_preference_changed()
      sakura.start(key, init, temp, vanished, ghost_changed,
                   self_name, name, shell, last_script, abend)
      notify_installedghostname(:key => key)
      notify_installedballoonname(:key => key)
      sakura.notify_installedshellname()
      set_menu_sensitive(key, false)
    end

    def update_working(ghost_name)
      @lockfile.truncate(0)
      @lockfile.seek(0)
      @lockfile.write(ghost_name)
      @lockfile.flush()        
    end

    def notify_preference_changed
      for sakura in get_working_ghost
        sakura.notify_preference_changed()
      end
    end

    def get_balloon_description(subdir)
      key = find_balloon_by_subdir(subdir)
      if key.nil?
        ##Logging::Logging.warning('Balloon ' + subdir + ' not found.')
        default_balloon = @prefs.get('default_balloon')
        key = find_balloon_by_subdir(default_balloon)
      end
      if key.nil?
        key = @balloons.keys[0]
      end
      return @balloons[key].baseinfo
    end

    def reload_current_sakura(sakura)
      save_preferences()
      key = sakura.key
      ghost_dir = File.split(sakura.get_prefix())[1] # XXX
      ghost_conf = Home.search_ghosts(:target => [ghost_dir])
      unless ghost_conf.nil?
        @ghosts[key].baseinfo = ghost_conf[key]
      else
        close_ghost(sakura) ## FIXME
        @ghosts.delete(key)
        return ## FIXME
      end
      start_sakura(key, :prev => key, :init => true) 
    end

    def add_sakura(ghost_dir)
      if @ghosts.include?(ghost_dir)
        exists = true
        Logging::Logging.warning('INSTALLED GHOST CHANGED: ' + ghost_dir)
      else
        exists = false
        Logging::Logging.info('NEW GHOST INSTALLED: ' + ghost_dir)
      end
      ghost_conf = Home.search_ghosts(:target => [ghost_dir])
      unless ghost_conf.empty?
        if exists
          sakura = @ghosts[ghost_dir].instance
          if sakura.is_running() # restart if working
            key = sakura.key
            proc_obj = lambda {
              @ghosts[ghost_dir].baseinfo = ghost_conf[ghost_dir]
              Logging::Logging.info('restarting....')
              start_sakura(key, :prev => key, :init => true)
              Logging::Logging.info('done.')
            }
            stop_sakura(sakura, proc_obj)
          end
        else
          holon = Ghost.new(ghost_dir)
          holon.set_responsible(self)
          @ghosts[ghost_dir] = holon
          holon.baseinfo = ghost_conf[ghost_dir]
        end
      else
        if exists
          sakura = @ghosts[ghost_dir].instance
          if sakura.is_running() # stop if working
            stop_sakura(sakura)
          end
          @ghosts.delete(ghost_dir)
        end
      end
      notify_installedghostname()
    end

    def add_balloon(balloon_dir)
      if @balloons.include?(balloon_dir)
        exists = true
        Logging::Logging.warning('INSTALLED BALLOON CHANGED: ' + balloon_dir)
      else
        exists = false
        Logging::Logging.info('NEW BALLOON INSTALLED: ' + balloon_dir)
      end
      balloon_conf = Home.search_balloons(:target => [balloon_dir])
      unless balloon_conf.empty?
        if exists
          @balloons[balloon_dir].baseinfo = balloon_conf[balloon_dir]
        else
          meme = BalloonMeme.new(balloon_dir)
          meme.set_responsible(self)
          @balloons[balloon_dir] = meme
          meme.baseinfo = balloon_conf[balloon_dir]
        end
      else
        if exists
          @balloons.delete(balloon_dir)
        end
      end
      @balloon_menu = create_balloon_menu()
      notify_installedballoonname()
    end

    def vanish_sakura(sakura, next_ghost)
      # remove ghost
      prefix = sakura.get_prefix()
      Dir.foreach(prefix) { |filename|
        next if /\A\.+\z/ =~ filename
        if File.file?(File.join(prefix, filename))
          if filename != 'HISTORY'
            begin
              File.delete(File.join(prefix, filename))
            rescue
              Logging::Logging.error(
                '*** REMOVE FAILED *** : ' + filename)
            end
          end
        else # dir
          begin
            FileUtils.remove_entry_secure(File.join(prefix, filename))
          rescue
            Logging::Logging.error(
              '*** REMOVE FAILED *** : ' + filename)
          end
        end
      }
      unless next_ghost.nil?
        select_ghost_by_name(sakura, next_ghost, :vanished => true)
      else
        select_ghost(sakura, false, :vanished => true)
      end
      @ghosts.delete(sakura.key)
    end

    def select_nekodorif(nekodorif_dir)
      target = @__menu_owner
      Nekodorif::Nekoninni.new.load(nekodorif_dir,
                                    @katochan, target)
    end

    def select_kinoko(data)
      target = @__menu_owner
      Kinoko::Kinoko.new(@kinoko).load(data, target)
    end

    def open_console
      @console.open()
    end

    def open_ghost_manager
      @__ngm.show_dialog()
    end

    def show_usage
      for sakura in get_working_ghost
        sakura.save_history()
      end
      history = {}
      for key in @ghosts.keys
        sakura = @ghosts[key].instance
        name = sakura.get_name(:default => key)
        ghost_time = 0
        prefix = sakura.get_prefix()
        path = File.join(prefix, 'HISTORY')
        if File.exist?(path)
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
              end
            end
          rescue # IOError => e
            Logging::Logging.error('cannot read ' + path)
          end
        end
        ai_list = []
        Dir.foreach(File.join(prefix, 'shell')) { |subdir|
          next if /\A\.+\z/ =~ subdir
          path = File.join(prefix, 'shell', subdir, 'ai.png')
          if File.exist?(path)
            ai_list << path
          end
        }
        history[name] = [ghost_time, ai_list]
      end
      @usage_dialog.open(history)
    end

    def confirmed
      @confirmed
    end

    def search_ghosts
      balloons = @balloons
      ghosts = @ghosts
      if ghosts.length > 0 and balloons.length > 0
        @confirmed = true
      end
      return ghosts.length, balloons.length
    end

    def do_idle_tasks
      unless @confirmed
        @console.open()
      else
        unless @loaded
          load()
          # start SSTP server
          @sstp_controler.start_servers()
          @loaded = true
        else
          @sstp_controler.receive_sstp_request()
          @sstp_controler.handle_sstp_queue()
        end
      end
      return true
    end

    def get_workarea
      [0, 0, *@app_window.get_size]
    end

    def get_property(key)
      now = Time.new
      case key
      when 'system.year'
        return now.year.to_s
      when 'system.month'
        return now.month.to_s
      when 'system.day'
        return now.day.to_s
      when 'system.hour'
        return now.hour.to_s
      when 'system.minute'
        return now.min.to_s
      when 'system.second'
        return now.sec.to_s
      when 'system.millisecond'
        return (now.nsec / 1_000_000).to_s
      when 'system.dayofweek'
        return now.wday.to_s
      when 'baseware.version'
        return Version.VERSION
      when 'baseware.name'
        return 'ninix-kagari'
      end
      return nil
    end

    def add_sakura_info(uuid, *args)
      return false if @sakura_info.include?(uuid)
      return update_sakura_info(uuid, *args, force: true)
    end

    def update_sakura_info(uuid, sakura_name, kero_name, ghost_path, force: false)
      return false if not force and not @sakura_info.include?(uuid)
      @sakura_info[uuid] = {
        name: sakura_name, keroname: kero_name,
        ghostpath: ghost_path,
      }
    end

    def remove_sakura_info(uuid)
      return false if not @sakura_info.include?(uuid)
      @sakura_info.delete(uuid)
      return true
    end

    def open_script_log
      @script_log.show
    end

    def append_script_log(name, script)
      @script_log.append_data(name, script)
    end
  end

  class Console
    include GetText
    attr_writer :level

    def initialize(app)
      @app = app
      @dialog = Gtk::Dialog.new(:parent => nil)
      @dialog.signal_connect('delete_event') do |w, e|
        next true # XXX
      end
      @level = Logger::WARN # XXX
      Logging::Logging.add_logger(self)
      @sw = Gtk::ScrolledWindow.new
      @sw.set_policy(Gtk::PolicyType::NEVER, Gtk::PolicyType::ALWAYS)
      @sw.show()
      @tv = Gtk::TextView.new
      @tv.set_wrap_mode(Gtk::WrapMode::CHAR)
      @tv.override_background_color(
        Gtk::StateFlags::NORMAL, Gdk::RGBA.new(0, 0, 0, 255))
      @tv.set_cursor_visible(true)
      @tv.set_editable(true) # important
      @tb = @tv.buffer
      @tag_critical = @tb.create_tag(nil, 'foreground' => 'red')
      @tag_error = @tb.create_tag(nil, 'foreground' => 'red')
      @tag_warning = @tb.create_tag(nil, 'foreground' => 'orange')
      @tag_info = @tb.create_tag(nil, 'foreground' => 'green')
      @tag_debug = @tb.create_tag(nil, 'foreground' => 'yellow')
      @tag_notset = @tb.create_tag(nil, 'foreground' => 'blue')
      ### DnD data types
      ##dnd_targets = [['text/uri-list', 0, 0]]
      ##@tv.drag_dest_set(Gtk::DestDefaults::ALL, dnd_targets,
      ##                  Gdk::DragAction::COPY)
      @tv.drag_dest_set_target_list(nil) # important
      @tv.drag_dest_add_uri_targets()
      @tv.signal_connect('drag_data_received') do |widget, context, x, y, data, info, time|
        drag_data_received(widget, context, x, y, data, info, time)
        next true
      end
      @tv.show()
      @sw.add(@tv)
      @tv.set_size_request(400, 250)
      @sw.set_size_request(400, 250)
      content_area = @dialog.content_area
      content_area.pack_start(@sw, :expand => true, :fill => true, :padding => 0)
      @dialog.add_button('Install', 1)
      @dialog.add_button("_Close", Gtk::ResponseType::CLOSE)
      @dialog.signal_connect('response') do |w, e|
        next response(w, e)
      end
      @file_chooser = Gtk::FileChooserDialog.new(
        :title => "Install..",
        :action => Gtk::FileChooserAction::OPEN,
        :buttons => [["_Open", Gtk::ResponseType::OK],
                    ["_Cancel", Gtk::ResponseType::CANCEL]])
      @file_chooser.set_default_response(Gtk::ResponseType::CANCEL)
      filter = Gtk::FileFilter.new
      filter.set_name("All files")
      filter.add_pattern("*")
      @file_chooser.add_filter(filter)
      filter = Gtk::FileFilter.new
      filter.set_name("nar/zip")
      filter.add_mime_type("application/zip")
      filter.add_pattern("*.nar")
      filter.add_pattern("*.zip")
      @file_chooser.add_filter(filter)
      @opened = false
    end

    def message_with_tag(message, tag)
      it = @tb.end_iter
      @tb.insert(it, [Logger::SEV_LABEL[@level], ':', message, "\n"].join(""), :tags => [tag])
      it = @tb.end_iter
      # scroll_to_iter may not have the desired effect.
      mark = @tb.create_mark("end", it, false)
      @tv.scroll_to_mark(mark, 0.0, false, 0.5, 0.5)
    end

    def info(message)
      return if @level > Logger::INFO
      tag = @tag_info
      message_with_tag(message, tag)
    end

    def debug(message)
      return if @level > Logger::DEBUG
      tag = @tag_debug
      message_with_tag(message, tag)
    end

    def fatal(message)
      return if @level > Logger::FATAL
      tag = @tag_critical
      message_with_tag(message, tag)
    end

    def error(message)
      return if @level > Logger::ERROR
      tag = @tag_error
      message_with_tag(message, tag)
    end

    def warn(message)
      return if @level > Logger::WARN
      tag = @tag_warning
      message_with_tag(message, tag)
    end

    def unknown(message)
      return if @level > Logger::UNKNOWN
      tag = @tag_notset
      message_with_tag(message, tag)
    end

    def update
      ghosts, balloons = @app.search_ghosts() # XXX
      if ghosts > 0 and balloons > 0
        @dialog.set_title(_('Console'))
        Logging::Logging.info('Ghosts: ' + ghosts.to_s)
        Logging::Logging.info('Balloons: ' + balloons.to_s)
      else
        @dialog.set_title(_("Nanntokashitekudasai."))
        if ghosts > 0
          Logging::Logging.info('Ghosts: ' + ghosts.to_s)
        else
          Logging::Logging.warning('Ghosts: ' + ghosts.to_s)
        end
        if balloons > 0
          Logging::Logging.info('Balloons: ' + balloons.to_s)
        else
          Logging::Logging.warning('Balloons: ' + balloons.to_s)
        end
      end
    end

    def open
      return if @opened
      update()
      @dialog.show()
      @opened = true
    end

    def close
      @dialog.hide()
      @opened = false
      unless @app.confirmed
        @app.quit()
      end
      return true
    end

    def response(widget, response)
      func = {1 =>  'open_file_chooser',
              Gtk::ResponseType::CLOSE.to_i => 'close',
              Gtk::ResponseType::DELETE_EVENT.to_i => 'close',
             }
      method(func[response]).call()
      return true
    end

    def open_file_chooser
      response = @file_chooser.run()
      case response
      when Gtk::ResponseType::OK
        filename = @file_chooser.filename
        @app.do_install(filename)
        update()
      when Gtk::ResponseType::CANCEL
        #pass
      end
      @file_chooser.hide()
    end

    def drag_data_received(widget, context, x, y, data, info, time)
      filelist = []
      for uri in data.uris
        uri_parsed = URI.parse(uri)
        pathname = URI.unescape(uri_parsed.path)
        if uri_parsed.scheme == 'file' and File.exist?(pathname)
          filelist << pathname
        elsif uri_parsed.scheme == 'http' or uri_parsed.scheme == 'ftp'
          filelist << uri
        end
      end
      unless filelist.empty?
        for filename in filelist
          @app.do_install(filename)
        end
        update()
      end
    end
  end

  class UsageDialog

    def initialize
      @dialog = Gtk::Dialog.new
      @dialog.set_title('Usage')
      @dialog.signal_connect('delete_event') do |w, e|
        next true # XXX
      end
      @darea = Gtk::DrawingArea.new
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK)
      @size = [550, 330]
      @darea.set_size_request(*@size)
      @darea.signal_connect('configure_event') do |w, e|
        configure(w, e)
        next true
      end
      @darea.signal_connect('draw') do |w, e|
        redraw(w, e)
        next true
      end
      content_area = @dialog.content_area
      content_area.pack_start(@darea, :expand => true, :fill => true, :padding => 0)
      @darea.show()
      @dialog.add_button("_Close", Gtk::ResponseType::CLOSE)
      @dialog.signal_connect('response') do |w, e|
        next response(w, e)
      end
      @opened = false
    end

    def open(history)
      return if @opened
      @history = history
      @items = []
      for item in @history
        name = item[0]
        clock = item[1][0]
        path = item[1][1]
        @items << [name, clock, path]
      end
      @items.sort_by! {|item| item[1] }
      @items.reverse!
      ai_list = @items[0][2]
      unless ai_list.empty?
        path = ai_list.sample
        fail "assert" unless File.exist?(path)
        @pixbuf = Pix.create_pixbuf_from_file(path)
        @pixbuf.saturate_and_pixelate(1.0, true)
      else
        @pixbuf = nil
      end
      @dialog.show()
      @opened = true
    end

    def close
      @dialog.hide()
      @opened = false
      return true
    end

    def response(widget, response)
      func = {Gtk::ResponseType::CLOSE.to_i => 'close',
              Gtk::ResponseType::DELETE_EVENT.to_i => 'close',
             }
      method(func[response]).call()
      return true
    end

    def configure(darea, event)
      alloc = darea.allocation
      @size = [alloc.width, alloc.height]
    end

    def redraw(widget, cr)
      if @items.empty?
        return # should not reach here
      end
      total = 0.0
      for name, clock, path in @items
        total += clock
      end
      layout = Pango::Layout.new(widget.pango_context)
      font_desc = Pango::FontDescription.new()
      font_desc.set_size(9 * Pango::SCALE)
      font_desc.set_family('Sans') # FIXME
      layout.set_font_description(font_desc)
      # redraw graph
      w, h = @size
      cr.set_source_rgb(1.0, 1.0, 1.0) # white
      cr.paint()
      # ai.png
      unless @pixbuf.nil?
        cr.set_source_pixbuf(@pixbuf, 16, 32) # XXX
        cr.paint()
      end
      w3 = w4 = 0
      rows = []
      for name, clock, path in @items[0..13]
        layout.set_text(name)
        name_w, name_h = layout.pixel_size
        rate = sprintf("%.1f%%", clock / total * 100)
        layout.set_text(rate)
        rate_w, rate_h = layout.pixel_size
        w3 = [rate_w, w3].max
        time = sprintf("%d:%02d", *(clock / 60).to_i.divmod(60))
        layout.set_text(time)
        time_w, time_h = layout.pixel_size
        w4 = [time_w, w4].max
        rows << [clock, name, name_w, name_h, rate, rate_w, rate_h,
                 time, time_w, time_h]
      end
      w1 = 280
      w2 = (w - w1 - w3 - w4 - 70)
      x = 20
      y = 15
      x += (w1 + 10)
      label = 'name'
      layout.set_text(label)
      label_name_w, label_name_h = layout.pixel_size
      cr.set_source_rgb(0.8, 0.8, 0.8) # gray
      cr.move_to(x, y)
      cr.show_pango_layout(layout)
      x = (x + w2 + 10)
      label = 'rate'
      layout.set_text(label)
      label_rate_w, label_rate_h = layout.pixel_size
      cr.set_source_rgb(0.8, 0.8, 0.8) # gray
      cr.move_to(x + w3 - label_rate_w, y)
      cr.show_pango_layout(layout)
      x += (w3 + 10)
      label = 'time'
      layout.set_text(label)
      label_time_w, label_time_h = layout.pixel_size
      cr.set_source_rgb(0.8, 0.8, 0.8) # gray
      cr.move_to(x + w4 - label_time_w, y)
      cr.show_pango_layout(layout)
      y += ([label_name_h, label_rate_h, label_time_h].max + 4)
      for clock, name, name_w, name_h, rate, rate_w, rate_h, time, time_w, \
          time_h in rows
        x = 20
        bw = (clock / total * w1).to_i
        bh = ([name_h, rate_h, time_h].max - 1)
        cr.set_source_rgb(0.8, 0.8, 0.8) # gray
        cr.rectangle(x + 1, y + 1, bw, bh)
        cr.stroke()
        cr.set_source_rgb(1.0, 1.0, 1.0) # white
        cr.rectangle(x, y, bw, bh)
        cr.stroke()
        cr.set_source_rgb(0.0, 0.0, 0.0) # black
        cr.rectangle(x, y, bw, bh)
        cr.stroke()
        x += (w1 + 10)
        layout.set_text(name)
        end_ = name.length
        while end_ > 0
          w, h = layout.pixel_size
          if w > 168
            end_ -= 1
            layout.set_text([name[0..end_-1], '...'].join(''))
          else
            break
          end
        end
        cr.set_source_rgb(0.0, 0.0, 0.0) # black
        cr.move_to(x, y)
        cr.show_pango_layout(layout)
        x += (w2 + 10)
        layout.set_text(rate)
        cr.set_source_rgb(0.0, 0.0, 0.0) # black
        cr.move_to(x + w3 - rate_w, y)
        cr.show_pango_layout(layout)
        x += (w3 + 10)
        layout.set_text(time)
        cr.set_source_rgb(0.0, 0.0, 0.0) # black
        cr.move_to(x + w4 - time_w, y)
        cr.show_pango_layout(layout)
        y += ([name_h, rate_h, time_h].max + 4)
      end
    end
  end
end


Logging::Logging.set_level(Logger::INFO)

# Homeの確認と2重起動防止はGtk::Applicationの外でやらないと
# 起動中のninix-kagariが落ちる。
begin
  is_running = false
  begin
    shm = NinixFMO::NinixFMO.new('/ninix', NinixFMO::O_RDWR)
    path_running = shm.read
    UNIXSocket.open(File.join(path_running, 'ninix')) do |soc|
      is_running = true
      # 起動中のninix側がBroken Pipeしないように全部読み込む
      soc.read
    end
  rescue
    # 起動中のninixが存在しない場合にここに来るのでnop
  end
  raise SystemExit, 'ninix-kagari is already running' if is_running
  shm = NinixFMO::NinixFMO.new('/ninix', NinixFMO::O_RDWR ^ NinixFMO::O_CREAT)
  path = [NinixServer.sockdir, File::SEPARATOR].join
  shm.write([path].pack('a*'))
  if shm.read != path
    raise SystemExit, "ninix-kagari is already running" if not Lock.lockfile(lock)
  end
  home_dir = Home.get_ninix_home()
  unless File.exist?(home_dir)
    begin
      FileUtils.mkdir_p(home_dir)
    rescue
      raise SystemExit, "Cannot create Home directory (abort)\n"
    end
  end
  lockfile_path = File.join(home_dir, ".lock")
  if File.exist?(lockfile_path)
    lock = open(lockfile_path, 'r')
    abend = lock.gets
  else
    abend = nil
  end
  # aquire Inter Process Mutex (not Global Mutex)
  lock = open(lockfile_path, 'w')
  raise SystemExit, 'ninix-kagari is already running' if not Lock.lockfile(lock)
rescue SystemExit => e
  p e.message
  exit false
end

gtk_app = Gtk::Application.new('io.github.tatakinov.ninix-kagari', :flags_none)

gtk_app.signal_connect 'activate' do |application|
  # parse command line arguments
  opt = OptionParser.new
  option = {}
  opt.on('--sstp-port sstp_port', 'additional port for listening SSTP requests') {|v| option[:sstp_port] = v}
  opt.on('--debug', 'debug') {|v| option[:debug] = v}
  opt.on('--logfile logfile_name', 'logfile name') {|v| option[:logfile] = v}
  opt.on('--ghost ghost_name', 'ghost name') do |v|
    option[:ghost] = v
  end
  opt.parse!(ARGV)
  Logging::Logging.add_logger(Logger.new(option[:logfile])) unless option[:logfile].nil?
  # TCP 7743：伺か（未使用）(IANA Registered Port for SSTP)
  # UDP 7743：伺か（未使用）(IANA Registered Port for SSTP)
  # TCP 9801：伺か          (IANA Registered Port for SSTP)
  # UDP 9801：伺か（未使用）(IANA Registered Port for SSTP)
  # TCP 9821：SSP
  # TCP 11000：伺か（廃止） (IANA Registered Port for IRISA)
  sstp_port = [9801]
  # parse command line arguments
  unless option[:sstp_port].nil?
    if option[:sstp_port].to_i < 1024
      Logging::Logging.warning("Invalid --sstp-port number (ignored)")
    else
      sstp_port << option[:sstp_port].to_i
    end
  end
  Logging::Logging.set_level(Logger::DEBUG) unless option[:debug].nil?

  option = {
    sstp_port: sstp_port,
    ghost: option[:ghost],
  }

  Gdk.set_program_class('Ninix')
  app_window = Pix::TransparentApplicationWindow.new(application)
  app_window.set_title("Ninix-kagari")
  app_window.show_all
  # start
  app = Ninix_Main::Application.new(lock, shm, **option)
  app.run(abend, app_window, application)
  # end
  lock.truncate(0)
  begin
    Lock.unlockfile(lock)
  rescue
    #pass
  end
end

begin
  gtk_app.run
rescue => e # should never rescue Exception
  Ninix_Main.handleException(e)
end
