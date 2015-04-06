# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#  Copyright (C) 2003-2005 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

#import argparse
#import urllib.parse
#import urllib.request
#import os
#import socket
#import sys
#import logging
#import logging.handlers
#import random
#import traceback
#import io
#import importlib
#import locale
#import multiprocessing
#from collections import OrderedDict

#if os.name == 'nt': # locale setting for windows
#    lang = os.getenv('LANG')
#    if lang is None:
#        os.environ['LANG'] = locale._build_localename(locale.getdefaultlocale())
#import gettext
#gettext.install('ninix')

require 'optparse'
require 'uri'
require 'gettext'
require "gtk3"

require "ninix/pix"
require "ninix/home"
require "ninix/prefs"
require "ninix/sakura"
require "ninix/sstp"
require "ninix/communicate"
require "ninix/ngm"
require "ninix/lock"
require "ninix/install"
##require "ninix/plugin"
require "ninix/nekodorif"
require "ninix/kinoko"
require "ninix/menu"
require "ninix/metamagic"

opt = OptionParser.new
opt.on('--sstp-port sstp_port', 'additional port for listening SSTP requests') {|v| }
opt.on('--debug', 'debug') {|v| }
opt.on('--logfile logfile_name', 'logfile name') {|v| }
#opt.parse!(ARGV)
opt.parse(ARGV)
#parser = argparse.ArgumentParser('ninix')
#parser.add_argument('--sstp-port', type=int, dest='sstp_port',
#                    help='additional port for listening SSTP requests')
#parser.add_argument('--debug', action='store_true', help='debug')
#parser.add_argument('--logfile', type=str, help='logfile name')

#logger = logging.getLogger()
#logger.setLevel(logging.INFO) # XXX

module Ninix_Main
  
  def self.handleException(exception_type, value, tb)
    #logger.error('Uncaught exception',
    #             exc_info=(exception_type, value, tb))
    response_id = 1
    dialog = Gtk::MessageDialog.new(
      nil, 0, Gtk.MessageType.ERROR, Gtk.ButtonsType.NONE,
      _('A ninix-aya error has been detected.'))
    dialog.set_title(_('Bug Detected'))
    dialog.set_position(Gtk.WindowPosition.CENTER)
    dialog.set_gravity(Gdk.Gravity.CENTER)
    button = dialog.add_button(_('Show Details'), response_id)
    dialog.add_button(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
    textview = Gtk::TextView.new
    textview.set_editable(false)
    left, top, scrn_w, scrn_h = Pix.get_workarea()
    width = (scrn_w / 2).to_i
    height = (scrn_h / 4).to_i
    textview.set_size_request(width, height)
    textview.show()
    sw = Gtk::ScrolledWindow.new
    sw.show()
    sw.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
    sw.add(textview)
    frame = Gtk::Frame.new
    frame.set_shadow_type(Gtk.ShadowType.IN)
    frame.add(sw)
    frame.set_border_width(7)
    content_area = dialog.get_content_area()
    content_area.add(frame)
    stringio = io.StringIO()
    traceback.print_exception(exception_type, value, tb, nil, stringio)
    textbuffer = textview.get_buffer()
    textbuffer.set_text(stringio.getvalue())
    while true
      if dialog.run() == response_id
        frame.show()
        button.set_sensitive(0)
      else # close button
        break
      end
    end
    dialog.destroy()
    raise SystemExit
  end
  
#  sys.excepthook = handleException

  def self.main
    # parse command line arguments
    args = ARGV.getopts("logfile:", "sstp_port:", "debug")
    if args["logfile"]
      #logger.addHandler(logging.FileHandler(args.logfile))
    end
    # TCP 7743：伺か（未使用）(IANA Registered Port for SSTP)
    # UDP 7743：伺か（未使用）(IANA Registered Port for SSTP)
    # TCP 9801：伺か          (IANA Registered Port for SSTP)
    # UDP 9801：伺か（未使用）(IANA Registered Port for SSTP)
    # TCP 9821：SSP
    # TCP 11000：伺か（廃止） (IANA Registered Port for IRISA)
    sstp_port = [9801]
    # parse command line arguments
    if args["sstp_port"]
      if args["sstp_port"].to_i < 1024
        #logging.warning('Invalid --sstp-port number (ignored)')
      else
        sstp_port << args["sstp_port"].to_i
      end
    end
    if args["debug"]
      #logger.setLevel(logging.DEBUG)
    end
    home_dir = Home.get_ninix_home()
    if not File.exists?(home_dir)
      begin
        FileUtils.mkdir_p(home_dir)
      rescue #except
        raise SystemExit('Cannot create Home directory (abort)\n')
      end
    end
    lockfile_path = File.join(Home.get_ninix_home(), '.lock')
    if File.exists?(lockfile_path)
      f = open(lockfile_path, 'r')
      abend = f.gets
      if not abend
        abend = nil
      end
    else
      abend = nil
    end
    # aquire Inter Process Mutex (not Global Mutex)
    f = open(lockfile_path, 'w')
    begin
      Lock.lockfile(f)
    rescue #except
      raise SystemExit('ninix-aya is already running')
    end
    # start
    #logging.info('loading...')
    app = Application.new(f, sstp_port)
    #logging.info('done.')
    app.run(abend)
    f.truncate(0)
    begin
      ninix.lock.unlockfile(f)
    rescue # except:
      #pass
    end
  end
  
  class SSTPControler

    def initialize(sstp_port)
      @parent = nil
      @sstp_port = sstp_port
      @sstp_servers = []
      @__sstp_queue = []
      @__sstp_flag = false
      @__current_sender = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist, **argdict)
      #assert ['GET', 'NOTIFY'].include?(event_type)
      handlers = {
      }
      handler = handlers.get(event, getattr(self, event, nil))
      if handler == nil
        result = self.request_parent(
          event_type, event, *arglist, **argdict)
      else
        result = handler(*arglist, **argdict)
      end
      if event_type == 'GET'
        return result
      end
    end

    def enqueue_request(event, script_odict, sender, handle,
                        address, show_sstp_marker, use_translator,
                        entry_db, request_handler)
      @__sstp_queue <<
        [event, script_odict, sender, handle, address, show_sstp_marker,
         use_translator, entry_db, request_handler]
    end

    def check_request_queue(sender)
      count = 0
      for request in @__sstp_queue
        if request[2].split(' / ')[0] == sender.split(' / ')[0]
          count += 1
        end
      end
      if @__sstp_flag and \
        @__current_sender.split(' / ')[0] == sender.split(' / ')[0]
        count += 1
      end
      return count.to_s, @__sstp_queue.length.to_s
    end

    def set_sstp_flag(sender)
      @__sstp_flag = true
      @__current_sender = sender
    end

    def reset_sstp_flag
      @__sstp_flag = false
      @__current_sender = nil
    end

    def handle_sstp_queue
      if @__sstp_flag or @__sstp_queue.empty?
        return
      end
      event, script_odict, sender, handle, address, \
      show_sstp_marker, use_translator, \
      entry_db, request_handler = @__sstp_queue.pop(0)
      working = (event != nil)
      break_flag = false
      for if_ghost in script_odict.keys()
        if if_ghost and request_parent('GET', 'if_ghost', if_ghost, working)
          request_parent('NOTIFY', 'select_current_sakura', if_ghost)
          default_script = script_odict[if_ghost]
          break_flag = true
          break
        end
      end
      if not break_flag
        if not request_parent('GET', 'get_preference', 'allowembryo')
          if event == nil
            if request_handler
              request_handler.send_response(420) # Refuse
            end
            return
          else
            default_script = nil
          end
        else
          if script_odict.include?('') # XXX
            default_script = script_odict['']
          else
            default_script = list(script_odict.values())[0]
          end
        end
        if event != nil
          script = request_parent('GET', 'get_event_response', event)
        else
          script = nil
        end
        if not script
          script = default_script
        end
        if script == nil
          if request_handler
            request_handler.send_response(204) # No Content
          end
          return
        end
        set_sstp_flag(sender)
        request_parent(
          'NOTIFY', 'enqueue_script',
          event, script, sender, handle, address,
          show_sstp_marker, use_translator, entry_db,
          request_handler, temp_mode=true)
      end
    end

    def receive_sstp_request
      begin
        for sstp_server in self.sstp_servers
          sstp_server.handle_request()
        end
      rescue # except socket.error as e:
        code, message = e.args
        #logging.error('socket.error: {0} ({1:d})'.format(message, code))
      rescue # except ValueError: # may happen when ninix is terminated
        return
      end
    end

    def get_sstp_port
      if not @sstp_servers
        return nil
      end
      return @sstp_servers[0].server_address[1]
    end

    def quit
      for server in @sstp_servers
        server.close()
      end
    end

    def start_servers
      for port in @sstp_port
        begin
          server = ninix.sstp.SSTPServer.new(['', port])
        rescue # except socket.error as e:
          code, message = e.args
          #logging.warning(
          #  'Port {0:d}: {1} (ignored)'.format(port, message))
          next
        end
        server.set_responsible(self.handle_request)
        @sstp_servers << server
        #logging.info('Serving SSTP on port {0:d}'.format(port))
      end
    end
  end
  
  class PluginDialog

    def initialize(plugin_dir, queue, message)
        @plugin_dir = plugin_dir
        @queue = queue
        dialog = Gtk.Window()
        dialog.set_title(plugin_dir)
        ##dialog.set_decorated(false)
        ##dialog.set_resizable(false)
        dialog.connect('delete_event', self.delete)
        dialog.connect('key_press_event', self.key_press)
        dialog.connect('button_press_event', self.button_press)
        dialog.set_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        ##dialog.set_modal(true)
        dialog.set_position(Gtk.WindowPosition.CENTER)
        dialog.realize()
        entry = Gtk::Entry.new
        entry.connect('activate', self.activate)
        entry.set_size_request(320, -1)
        entry.show()
        box = Gtk::VBox.new(spacing=10)
        box.set_border_width(10)
        label = Gtk::Label.new(message)
        box.pack_start(label, false, true, 0)
        label.show()
        box.pack_start(entry, false, true, 0)
        dialog.add(box)
        box.show()
        @dialog = dialog
    end

    def open
      @dialog.show()
    end

    def delete(widget, event)
      @dialog.hide()
      cancel()
      return true
    end

    def key_press(widget, event)
      if event.keyval == Gdk.KEY_Escape
        @dialog.hide()
        cancel()
        return true
      end
      return false
    end

    def button_press(widget, event)
      if [1, 2].include?(event.button)
        @dialog.begin_move_drag(
          event.button, event.x_root.to_i, event.y_root.to_i,
          Gtk.current_event_time)
      end
      return true
    end

    def activate(widget)
      @dialog.hide()
      enter(widget.get_text())
      return true
    end

    def enter(text)
      @queue.put(text)
    end

    def cancel
      @queue.put('')
    end
  end

  class PluginControler

    def initialize
      @jobs = {}
      @queue = {}
      @data = {}
      @dialog = {}
      @parent = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def save_data(plugin_dir)
      if not @data.include?(plugin_dir)
        return
      end
      home_dir = ninix.home.get_ninix_home()
      target_dir = File.join(home_dir, 'plugin', plugin_dir)
      path = File.join(target_dir, 'SAVEDATA')
      f = open(path, 'w', encoding='utf-8')
      f.write('#plugin: {0:1.1f}\n'.format(ninix.home.PLUGIN_STANDARD[1]))
      for name, value in @data[plugin_dir].items()
        if value == nil
          next
        end
        f.write('{0}:{1}\n'.format(name, value))
      end
    end

    def load_data(plugin_dir)
      home_dir = ninix.home.get_ninix_home()
      target_dir = File.join(home_dir, 'plugin', plugin_dir)
      path = File.join(target_dir, 'SAVEDATA')
      if not File.exists?(path)
        return {}
      end
      data = {}
      begin
        f = open(path, 'r', encoding='utf-8')
        line = f.readline()
        line = line.rstrip('\r\n')
        if not line.startswith('#plugin:')
          return {}
        end
        begin
          standard = float(line[8..-1])
        rescue # except:
          return {}
        end
        if standard < ninix.home.PLUGIN_STANDARD[0] or \
          standard > ninix.home.PLUGIN_STANDARD[1]
          return {}
        end
        for line in f
          line = line.rstrip('\r\n')
          key, value = line.split(':', 1)
          data[key] = value
        end
      rescue # except IOError as e:
        code, message = e.args
        logging.error('cannot read {0}'.format(path))
      end
      return data
    end

    def terminate_plugin
      for plugin_dir in @data.keys()
        save_data(plugin_dir)
      end
      return ## FIXME
    end

    def open_dialog(plugin_dir, message)
      @dialog[plugin_dir] = PluginDialog(plugin_dir,
                                         @queue[plugin_dir],
                                         message)
      @dialog[plugin_dir].open()
    end

    def check_queue
      for plugin_dir in @jobs.keys()
        if not @queue[plugin_dir].empty()
          data = @queue[plugin_dir].get()
          @queue[plugin_dir].task_done()
          if isinstance(data, str)
            if data.startswith('DIALOG:')
              message = data[7..-1]
              open_dialog(plugin_dir, message)
              next
            end
          elsif not isinstance(data, dict)
            continue
          end
          break_flag = false
          for name, value in data.items()
            if not isinstance(name, str) or \
              name.include?(':') or \
              not (isinstance(value, str) or value == nil)
              break_flag = true
              break
            end
          end
          if not break_flag
            #assert @data.include?(plugin_dir)
            @data[plugin_dir].update(data)
          end
        end
      end
    end

    def exec_plugin(plugin_dir, argv, caller)
      if @jobs.include?(plugin_dir) and @jobs[plugin_dir].is_alive()
        #logging.warning('plugin {0} is already running'.format(plugin_dir))
        return
      end
      module_name = File.basename(argv[0])
      ext = File.extname(argv[0])
      home_dir = ninix.home.get_ninix_home()
      target_dir = File.join(home_dir, 'plugin', plugin_dir)
      plugin_module = self.__import_module(module_name, target_dir)
      if plugin_module == nil
        return
      end
      port = self.request_parent('GET', 'get_sstp_port')
      queue = multiprocessing.JoinableQueue()
      if not @data.include?(plugin_dir)
        @data[plugin_dir] = load_data(plugin_dir)
      end
      data = @data[plugin_dir]
      p = plugin_module.Plugin(port, target_dir, argv[1..-1], home_dir, caller,
                               queue, data)
      if not isinstance(p, ninix.plugin.BasePlugin)
        return
      end
      @jobs[plugin_dir] = p
      @queue[plugin_dir] = queue
      p.daemon = true
      p.start()
#      if os.name == 'nt' and target_dir in sys.path
#        # XXX: an opposite of the BasePlugin.__init__ hack
#        sys.path.remove(target_dir)
#      end
    end

    def start_plugins(plugins)
      for plugin_name, plugin_dir, startup, menu_items in plugins
        if startup != nil
          exec_plugin(plugin_dir, startup,
                      {'name' => '', 'directory' => ''})
        end
      end
    end

    def __import_module(name, directory)
      loader = importlib.find_loader(name, [directory])
      begin
        return loader.load_module(name)
      rescue # except:
        return nil
      end
    end
  end

  class BalloonMeme < MetaMagic::Meme

    def initialize(key)
      super(key)
      @parent = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      return @parent.handle_request(event_type, event, *arglist)
    end
 
    def create_menuitem(data)
      desc, balloon = data
      subdir = balloon['balloon_dir'][0]
      name = desc.get('name', subdir)
      home_dir = Home.get_ninix_home()
      thumbnail_path = File.join(home_dir, 'balloon',
                                 subdir, 'thumbnail.png')
      if not File.exists?(thumbnail_path)
        thumbnail_path = nil
      end
      return handle_request(
               'GET', 'create_balloon_menuitem', name, @key, thumbnail_path)
    end

    def delete_by_myself
      handle_request('NOTIFY', 'delete_balloon', @key)
    end
  end

  class Ghost < MetaMagic::Holon

    def initialize(key)
        super(key)
        @parent = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      return @parent.handle_request(event_type, event, *arglist)
    end

    def create_menuitem(data)
      return self.request_parent('GET', 'create_menuitem', @key, data)
    end

    def delete_by_myself
      self.request_parent('NOTIFY', 'delete_ghost', @key)
    end

    def create_instance(data)
      return self.request_parent('GET', 'create_ghost', data)
    end
  end

  class Application

    def initialize(lockfile, sstp_port=[9801, 11000])
      @lockfile = lockfile
      @abend = nil
      @loaded = false
      @confirmed = false
      @console = Console.new(self)
      # create preference dialog
      @prefs = Prefs::PreferenceDialog.new
      @prefs.set_responsible(self)
      @sstp_controler = SSTPControler.new(sstp_port)
      @sstp_controler.set_responsible(self)
      # create usage dialog
      @usage_dialog = UsageDialog.new
      @communicate = Communicate::Communicate.new
      # create plugin manager
      @plugin_controler = PluginControler.new
      @plugin_controler.set_responsible(self)
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
      @ghosts = {} # OrderedDict
      odict_baseinfo = Home.search_ghosts()
      for key, value in odict_baseinfo
        holon = Ghost.new(key)
        holon.set_responsible(self)
        @ghosts[key] = holon 
        holon.baseinfo = value
      end
      @balloons = {} # OrderedDict
      odict_baseinfo = Home.search_balloons()
      for key, value in odict_baseinfo
        meme = BalloonMeme.new(key)
        meme.set_responsible(self)
        @balloons[key] = meme
        meme.baseinfo = value
      end
      @balloon_menu = create_balloon_menu()
      @plugins = Home.search_plugins()
      @nekoninni = Home.search_nekoninni()
      @katochan = Home.search_katochan()
      @kinoko = Home.search_kinoko()
    end

    def edit_preferences(*arglist)
      return @prefs.edit_preferences(*arglist)
    end

    def prefs_get(*arglist)
      return @prefs.get(*arglist)
    end

    def get_otherghostname(*arglist)
      return @communicate.get_otherghostname(*arglist)
    end

    def rebuild_ghostdb(*arglist)
      return @communicate.rebuild_ghostdb(*arglist)
    end

    def notify_other(*arglist)
      return @communicate.notify_other(*arglist)
    end

    def reset_sstp_flag(*arglist)
      return @sstp_controler.reset_sstp_flag(*arglist)
    end

    def get_sstp_port(*arglist)
      return @sstp_controler.get_sstp_port(*arglist)
    end

    def handle_request(event_type, event, *arglist)
      #assert ['GET', 'NOTIFY'].include?(event_type)
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
      }
      if not handlers.include?(event)
        if Application.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = nil
        end
      else
        result = method(handlers[event]).call(*arglist)
      end
      if event_type == 'GET'
        return result
      end
    end

    def set_collisionmode(flag, rect=false)
      @prefs.check_collision_button.set_active(flag)
      @prefs.check_collision_name_button.set_active((not rect))
      @prefs.update(commit=true) # XXX
      notify_preference_changed()
    end

    def do_install(filename)
      @communicate.notify_all('OnInstallBegin', [])
      begin
        filetype, target_dirs, names, errno = @installer.install(
                                        filename, Home.get_ninix_home())
      rescue # except:
        target_dirs = nil
      end
      if errno != 0
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
        # XXX: ninix-ayaでは発生しない.
        ##@communicate.notify_all('OnInstallRefuse', [])
      else
        ##@communicate.notify_all('OnInstallCompleteEx', []) # FIXME
        if filetype != 'kinoko'
          if filetype == 'ghost'
            if target_dirs[1]
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
      if target_dirs
        if filetype == 'ghost'
          add_sakura(target_dirs[0])
          ninix.sakura.ReadmeDialog().show(
            target_dirs[0],
            File.join(ninix.home.get_ninix_home(),
                      'ghost', target_dirs[0]))
          if target_dirs[1]
            add_balloon(target_dirs[1])
            ninix.sakura.ReadmeDialog().show(
              target_dirs[1],
              File.join(ninix.home.get_ninix_home(),
                        'balloon', target_dirs[1]))
          end
        elsif filetype == 'supplement'
          add_sakura(target_dirs) # XXX: reload
        elsif filetype == 'balloon'
          add_balloon(target_dirs)
          ninix.sakura.ReadmeDialog().show(
            target_dirs,
            File.join(ninix.home.get_ninix_home(),
                      'balloon', target_dirs))
        elsif filetype == 'plugin'
          @plugins = ninix.home.search_plugins()
        elsif filetype == 'nekoninni'
          @nekoninni = ninix.home.search_nekoninni()
        elsif filetype == 'katochan'
          @katochan = ninix.home.search_katochan()
        elsif filetype == 'kinoko'
          @kinoko = ninix.home.search_kinoko()
          @communicate.notify_all('OnKinokoObjectInstalled', names)
        end
      end
    end

    def notify_installedghostname(key=nil)
      installed = []
      for value in @ghosts.values()
        sakura = value.instance
        if sakura == nil
          next
        end
        installed << sakura.get_name(default='')
      end
      if key != nil
        if @ghosts.include?(key)
          sakura = @ghosts[key].instance
          sakura.notify_event('installedghostname', *installed)
        end
      else
        for sakura in get_working_ghost()
          sakura.notify_event('installedghostname', *installed)
        end
      end
    end

    def notify_installedballoonname(key=nil)
      installed = []
      for value in @balloons.values()
        desc, balloon = value.baseinfo
        subdir = balloon['balloon_dir'][0]
        installed << desc.get('name', subdir)
      end
      if key != nil
        if @ghosts.include?(key)
          sakura = @ghosts[key].instance
          sakura.notify_event('installedballoonname', *installed)
        end
      else
        for sakura in get_working_ghost()
          sakura.notify_event('installedballoonname', *installed)
        end
      end
    end

    #@property
    def current_sakura_instance
      return @ghosts[@current_sakura].instance
    end

    def create_ghost(data)
      ghost = ninix.sakura.Sakura()
      ghost.set_responsible(self)
      ghost.new(*data)
      return ghost
    end

    def get_sakura_cantalk
      return current_sakura_instance.cantalk
    end

    def get_event_response(event, *arglist, **argdict) ## FIXME
      return current_sakura_instance.get_event_response(*event)
    end

    def keep_silence(quiet)
      current_sakura_instance.keep_silence(quiet)
    end

    def get_ghost_name ## FIXME
      sakura = current_sakura_instance
      return sakura.get_ifghost()
    end

    def enqueue_event(event, *arglist, **argdict)
      current_sakura_instance.enqueue_event(event, *arglist, **argdict)
    end

    def enqueue_script(event, script, sender, handle,
                       host, show_sstp_marker, use_translator,
                       db=nil, request_handler=nil, temp_mode=false)
      sakura = current_sakura_instance
      if temp_mode
        sakura.enter_temp_mode()
      end
      sakura.enqueue_script(event, script, sender, handle,
                            host, show_sstp_marker, use_translator,
                            db, request_handler)
    end

    def get_working_ghost(cantalk=false)
      for value in @ghosts.values()
        sakura = value.instance
        if sakura == nil
          next
        end
        if not sakura.is_running()
          next
        end
        if cantalk and not sakura.cantalk
          next
        end
        yield sakura
      end
    end

    def get_sakura_prefix
      return @__menu_owner.get_prefix()
    end

    def getstring(name)
      return @__menu_owner.getstring(name)
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

    def get_current_balloon_directory ## FIXME
      return @__menu_owner.get_current_balloon_directory()
    end

    def start_sakura_cb(key, caller=nil)
      sakura_name = @ghosts[key].instance.get_selfname(default='')
      name = @ghosts[key].instance.get_name(default='')
      if caller == nil
        caller = @__menu_owner
      end
      caller.notify_event('OnGhostCalling', sakura_name, 'manual', name, key)
      start_sakura(key, init=true) # XXX
    end

    def select_sakura(key)
      if @__menu_owner.busy()
        Gdk.beep()
        return
      end
      change_sakura(@__menu_owner, key, 'manual')
    end

    def notify_site_selection(args)
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

    def network_update
      @__menu_owner.network_update()
    end

    def open_popup_menu(sakura, button, side)
      @__menu_owner = sakura
      path_background, path_sidebar, path_foreground, \
      align_background, align_sidebar, align_foreground = \
                                       @__menu_owner.get_menu_pixmap()
      @__menu.set_pixmap(
        path_background, path_sidebar, path_foreground,
        align_background, align_sidebar, align_foreground)
      background, foreground = @__menu_owner.get_menu_fontcolor()
      @__menu.set_fontcolor(background, foreground)
      mayuna_menu = @__menu_owner.get_mayuna_menu()
      @__menu.create_mayuna_menu(mayuna_menu)
      @__menu.popup(button, side)
    end

    def get_ghost_menus
      for value in @ghosts.values()
        yield value.menuitem
      end
    end

    def get_shell_menu
      return @__menu_owner.get_shell_menu()
    end

    def get_balloon_menu
      current_key = get_current_balloon_directory()
      for key in @balloons
        menuitem = @balloons[key].menuitem
        menuitem.set_sensitive(key != current_key) # not working
      end
      return @balloon_menu
    end

    def create_balloon_menuitem(balloon_name, balloon_key, thumbnail)
      return @__menu.create_meme_menuitem(
        balloon_name, balloon_key, lambda {|v| select_balloon(v) }, thumbnail)
    end

    def create_balloon_menu
      balloon_menuitems = {} # OrderedDict()
      for key in @balloons.keys()
        balloon_menuitems[key] = @balloons[key].menuitem
      end
      print("ITEMS: ", balloon_menuitems, "\n")
      return @__menu.create_meme_menu(balloon_menuitems)
    end

    def create_shell_menu(menuitems)
      return @__menu.create_meme_menu(menuitems)
    end

    def create_shell_menuitem(shell_name, shell_key, thumbnail)
      return @__menu.create_meme_menuitem(
        shell_name, shell_key, self.select_shell, thumbnail)
    end

    def create_menuitem(key, baseinfo)
      desc = baseinfo[0]
      shiori_dir = baseinfo[1]
      icon = desc.get('icon', nil)
      if icon != nil
        icon_path = File.join(shiori_dir, icon)
        if not File.exists?(icon_path)
          icon_path = nil
        end
      else
        icon_path = nil
      end
      name = desc.get('name')
      thumbnail_path = File.join(shiori_dir, 'thumbnail.png')
      if not File.exists?(thumbnail_path)
        thumbnail_path = nil
      end
      start_menuitem = @__menu.create_ghost_menuitem(
        name, icon_path, key, self.start_sakura_cb, # XXX
        thumbnail_path)
      select_menuitem = @__menu.create_ghost_menuitem(
        name, icon_path, key, self.select_sakura,
        thumbnail_path)
      menuitem = {
        'Summon' => start_menuitem,
        'Change' => select_menuitem,
      }
      return menuitem
    end

    def delete_ghost(key)
      #assert @ghosts.include?(key)
      del @ghosts[key]
    end

    def get_balloon_list ## FIXME
      balloon_list = []
      for key in @balloons.keys()
        desc, balloon = @balloons[key].baseinfo
        subdir = balloon['balloon_dir'][0]
        name = desc.get('name', subdir)
        balloon_list << [name, subdir]
      end
      return balloon_list
    end

    def get_plugin_list ## FIXME
      plugin_list = []
      for i, plugin in enumerate(@plugins)
        plugin_name = plugin[0]
        menu_items = plugin[3]
        if not menu_items
          next
        end
        item = {}
        item['name'] = plugin_name
        item['icon'] = nil
        item_list = []
        for j, menu_item in enumerate(menu_items)
          label = menu_item[0]
          value = [i, j]
          item_list << [label, value]
        end
        item['items'] = item_list
        plugin_list << item
      end
      return plugin_list
    end

    def get_nekodorif_list ## FIXME
      nekodorif_list = []
      nekoninni = @nekoninni
      for nekoninni_name, nekoninni_dir in nekoninni
        if not nekoninni_name
          next
        end
        item = {}
        item['name'] = nekoninni_name
        item['dir'] = nekoninni_dir
        nekodorif_list << item
      end
      return nekodorif_list
    end

    def get_kinoko_list ## FIXME
      return @kinoko
    end

    def load
      # load user preferences
      @prefs.load()
      # choose default ghost/shell
      directory = @prefs.get('sakura_dir')
      name = @prefs.get('sakura_name') # XXX: backward compat
      default_sakura = find_ghost_by_dir(directory) or \
      find_ghost_by_name(name) or \
      choose_default_sakura()
      # load ghost
      @current_sakura = default_sakura
      ##for i, name in enumerate(self.get_ghost_names()):
      ##    logging.info(
      ##        'GHOST({0:d}): {1}'.format(i, name))
      start_sakura(@current_sakura, init=true, abend=@abend)
    end

    def find_ghost_by_dir(directory)
      if @ghosts.include?(directory)
        return directory
      else
        return nil
      end
    end

    def find_ghost_by_name(name)
      for key in @ghosts
        sakura = @ghosts[key].instance
        begin
          if sakura.get_name(default=nil) == name
            return key
          end
        rescue # except: # old preferences(EUC-JP)
          #pass
        end
      end
      return nil
    end

    def choose_default_sakura
      return list(@ghosts.keys())[0]
    end

    def find_balloon_by_name(name)
      for key in @balloons
        desc, balloon = @balloons[key].baseinfo
        begin
          if desc.get('name') == name
            return key
          end
          if balloon['balloon_dir'][0] == ninix.home.get_normalized_path(name) # XXX
            return key
          end
        rescue # except: # old preferences(EUC-JP)
          #pass
        end
      end
      return nil
    end

    def find_balloon_by_subdir(subdir)
      for key in @balloons
        desc, balloon = @balloons[key].baseinfo
        begin
          if balloon['balloon_dir'][0] == subdir
            return key
          end
          if ninix.home.get_normalized_path(desc.get('name')) == subdir # XXX
            return key
          end
        rescue # except: # old preferences(EUC-JP)
          #pass
        end
      end
      return nil
    end

    def exit_handler(sig_no, frame=nil)
      close_all_ghosts(reason='shutdown')
    end

    def run(abend)
      @abend = abend
#      if os.name == "nt"
#        # The SIGTERM signal is not generated under Windows NT.
#        import win32api
#        win32api.SetConsoleCtrlHandler(self.exit_handler, true)
#      else
#        import signal
#        signal.signal(signal.SIGTERM, self.exit_handler)
#      end
      @timeout_id = GLib::Timeout.add(100) { do_idle_tasks } # 100[ms]
      Gtk.main()
    end

    def get_ghost_names
      for value in @ghosts.values()
        if value.instance != nil
          yield value.instance.get_selfname() ## FIXME
        end
      end
    end

    def if_ghost(if_ghost, working=false)
      instance_list = []
      for value in @ghosts.values()
        if value.instance != nil
          instance_list << value
        end
      end
      for sakura in instance_list
        if working
          if not sakura.is_running() or not sakura.cantalk
            next
          end
        end
        if sakura.ifghost(if_ghost)
          return true
        end
      end
      return false
    end

    def update_sakura(name, sender)
      key = find_ghost_by_name(name)
      if key == nil
        return
      end
      sakura = @ghosts[key].instance
      if not sakura.is_running()
        start_sakura(key, init=true)
      end
      sakura.enqueue_script(nil, '\![updatebymyself]\e', sender,
                            nil, nil, 0, 0, nil)
    end

    def select_current_sakura(ifghost=nil)
      if ifghost != nil
        break_flag = false
        for value in @ghosts.values()
          sakura = value.instance
          if sakura == nil
            next
          end
          if sakura.ifghost(ifghost)
            if not sakura.is_running()
              @current_sakura = value.key
              start_sakura(@current_sakura, init=true, temp=1) ## FIXME
            else
              @current_sakura = sakura.key
            end
            break
          else
            #pass
          end
        end
        if not break_flag
          return
        end
      else
        working_list = list(get_working_ghost(cantalk=true))
        if working_list
          @current_sakura = random.choice(working_list).key
        else
          return ## FIXME
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
      if not any(get_working_ghost())
        @prefs.set_current_sakura(sakura.key)
        quit()
      elsif @current_sakura == sakura.key
        select_current_sakura()
      end
    end

    def close_all_ghosts(reason='user')
      for sakura in get_working_ghost()
        sakura.notify_event('OnCloseAll', reason)
      end
    end

    def quit
      GLib::Source.remove(@timeout_id)
      @usage_dialog.close()
      @sstp_controler.quit() ## FIXME
      @plugin_controler.terminate_plugin() ## FIXME
      save_preferences()
      Gtk.main_quit()
    end

    def save_preferences
      begin
        @prefs.save()
      rescue # except IOError:
        #logging.error('Cannot write preferences to file (ignored).')
      rescue # except:
        #pass ## FIXME
      end
    end

    def select_ghost(sakura, sequential, event=1, vanished=false)
      keys = list(@ghosts.keys())
      if keys.length < 2
        return
      end
      # select another ghost
      if sequential
        key = (keys.index(sakura.key) + 1) % keys.length
      else
        keys.remove(sakura.key)
        key = random.choice(keys)
      end
      change_sakura(sakura, key, 'automatic', event, vanished)
    end

    def select_ghost_by_name(sakura, name, event=1, vanished=false)
      key = find_ghost_by_name(name)
      if key == nil
        return
      end
      change_sakura(sakura, key, 'automatic', event, vanished)
    end

    def change_sakura(sakura, key, method, event=1, vanished=false)
      if sakura.key == key # XXX: needs reloading?
        return
      end
      proc = lambda { stop_sakura(sakura, self.start_sakura, key, sakura.key) }
#      def proc(self=self, key=key)
#        stop_sakura(sakura, self.start_sakura, key, sakura.key)
#      end
      if vanished
        sakura.finalize()
        start_sakura(key, sakura.key, vanished)
        close_ghost(sakura)
      elsif not event
        proc()
      else
        sakura_name = @ghosts[key].instance.get_selfname(default='')
        name = @ghosts[key].instance.get_name(default='')
        sakura.enqueue_event(
          'OnGhostChanging', sakura_name, method, name, key, proc=proc)
      end
    end

    def stop_sakura(sakura, starter=nil, *args)
      sakura.finalize()
      if starter != nil
        starter(*args)
      end
      set_menu_sensitive(sakura.key, true)
      close_ghost(sakura)
    end

    def start_sakura(key, prev=nil, vanished=false, init=false, temp=false, abend=nil)
      sakura = @ghosts[key].instance
      #assert sakura != nil
      if prev != nil
        #assert @ghosts.include?(prev) ## FIXME: vanish case?
        #assert @ghosts[prev].instance != nil
      end
      if init
        ghost_changed = false
      else
        #assert prev != nil ## FIXME
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
      notify_installedghostname(key)
      notify_installedballoonname(key)
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
      for sakura in get_working_ghost()
        sakura.notify_preference_changed()
      end
    end

    def get_balloon_description(subdir) ## FIXME
      key = find_balloon_by_subdir(subdir)
      if key == nil
        ##logging.warning('Balloon {0} not found.'.format(subdir))
        default_balloon = @prefs.get('default_balloon')
        key = find_balloon_by_subdir(default_balloon)
      end
      if key == nil
        key = list(@balloons.keys())[0]
      end
      return @balloons[key].baseinfo
    end

    def reload_current_sakura(sakura)
      save_preferences()
      key = sakura.key
      ghost_dir = File.split(sakura.get_prefix())[1] # XXX
      ghost_conf = ninix.home.search_ghosts([ghost_dir])
      if ghost_conf
        @ghosts[key].baseinfo = ghost_conf[key]
      else
        close_ghost(sakura) ## FIXME
        del @ghosts[key]
        return ## FIXME
      end
      start_sakura(key, key, init=true) 
    end

    def add_sakura(ghost_dir)
      if @ghosts.include?(ghost_dir)
        exists = 1
        #logging.warning('INSTALLED GHOST CHANGED: {0}'.format(ghost_dir))
      else
        exists = 0
        #logging.info('NEW GHOST INSTALLED: {0}'.format(ghost_dir))
      end
      ghost_conf = ninix.home.search_ghosts([ghost_dir])
      if ghost_conf
        if exists
          sakura = @ghosts[ghost_dir].instance
          if sakura.is_running() # restart if working
            key = sakura.key
            proc = lambda {
              @ghosts[ghost_dir].baseinfo = ghost_conf[ghost_dir]
              logging.info('restarting....')
              start_sakura(key, key, init=true)
              logging.info('done.')
            }
#            def proc(self=self)
#              @ghosts[ghost_dir].baseinfo = ghost_conf[ghost_dir]
#              logging.info('restarting....')
#              start_sakura(key, key, init=true)
#              logging.info('done.')
#            end
            stop_sakura(sakura, proc)
          end
        else
          holon = Ghost.new(ghost_dir)
          holon.set_responsible(self.handle_request)
          @ghosts[ghost_dir] = holon
          holon.baseinfo = ghost_conf[ghost_dir]
        end
      else
        if exists
          sakura = @ghosts[ghost_dir].instance
          if sakura.is_running() # stop if working
            stop_sakura(sakura)
          end
          del @ghosts[ghost_dir]
        end
      end
      notify_installedghostname()
    end

    def add_balloon(balloon_dir)
      if @balloons.include?(balloon_dir)
        exists = 1
        #logging.warning('INSTALLED BALLOON CHANGED: {0}'.format(balloon_dir))
      else
        exists = 0
        #logging.info('NEW BALLOON INSTALLED: {0}'.format(balloon_dir))
      end
      balloon_conf = ninix.home.search_balloons([balloon_dir])
      if balloon_conf
        if exists
          @balloons[balloon_dir].baseinfo = balloon_conf[balloon_dir]
        else
          meme = BalloonMeme(balloon_dir)
          meme.set_responsible(self.handle_request)
          @balloons[balloon_dir] = meme
          meme.baseinfo = balloon_conf[balloon_dir]
        end
      else
        if exists
          del @balloons[balloon_dir]
        end
      end
      @balloon_menu = create_balloon_menu()
      notify_installedballoonname()
    end

    def vanish_sakura(sakura, next_ghost)
      # remove ghost
      prefix = sakura.get_prefix()
      Dir.foreach(prefix) { |filename|
        next if /^\.+$/ =~ filename
        if File.file?(File.join(prefix, filename))
          if filename != 'HISTORY'
            begin
              File.delete(File.join(prefix, filename))
            rescue # except:
              #logging.error(
              #  '*** REMOVE FAILED *** : {0}'.format(filename))
            end
          end
        else # dir
          begin
            FileUtils.remove_entry_secure(File.join(prefix, filename))
          rescue # except:
            #logging.error(
            #  '*** REMOVE FAILED *** : {0}'.format(filename))
          end
        end
      }
      if next_ghost != nil
        select_ghost_by_name(sakura, next_ghost, vanished=true)
      else
        select_ghost(sakura, 0, vanished=true)
      end
      del @ghosts[sakura.key]
    end

    def select_plugin(item)
      target = @__menu_owner
      i, j = item
      plugin_name, plugin_dir, startup, menu_items = @plugins[i]
      label, argv = menu_items[j]
      if label == 'Uninstall'
        home_dir = ninix.home.get_ninix_home()
        @installer.uninstall_plugin(home_dir, plugin_name)
        @plugins = ninix.home.search_plugins() # reload
        return
      end
      caller = {}
      caller['name'] = target.get_name()
      caller['directory'] = target.get_prefix()
      caller['ifghost'] = target.get_ifghost()
      @plugin_controler.exec_plugin(plugin_dir, argv, caller)
    end

    def select_nekodorif(nekodorif_dir)
      target = @__menu_owner
      ninix.nekodorif.Nekoninni().load(nekodorif_dir,
                                       @katochan, target)
    end

    def select_kinoko(data)
      target = @__menu_owner
      ninix.kinoko.Kinoko(@kinoko).load(data, target)
    end

    def open_console
      @console.open()
    end

    def open_ghost_manager
      @__ngm.show_dialog()
    end

    def show_usage
      for sakura in get_working_ghost()
        sakura.save_history()
      end
      history = {}
      for key in @ghosts
        sakura = @ghosts[key].instance
        name = sakura.get_name(default=key)
        ghost_time = 0
        prefix = sakura.get_prefix()
        path = File.join(prefix, 'HISTORY')
        if File.exists?(path)
          begin
            f = open(path, 'r')
            for line in f
              if not line.include?(',')
                next
              end
              key, value = line.split(',', 1)
              key = key.strip()
              if key == 'time'
                begin
                  ghost_time = int(value.strip())
                rescue # except:
                  #pass
                end
              end
            end
          rescue # except IOError as e:
            code, message = e.args
            logging.error('cannot read {0}'.format(path))
          end
        end
        ai_list = []
        Dir.foreach(File.join(prefix, 'shell')) { |subdir|
          next if /^\.+$/ =~ subdir
          path = File.join(prefix, 'shell', subdir, 'ai.png')
          if File.exists?(path)
            ai_list << path
          end
        }
        history[name] = [ghost_time, ai_list]
      end
      @usage_dialog.open(history)
    end

    def confirmed
      return @confirmed
    end

    def search_ghosts ## FIXME
      balloons = @balloons ## FIXME
      ghosts = @ghosts ## FIXME
      if ghosts.length > 0 and balloons.length > 0
        @confirmed = true
      end
      return ghosts.length, balloons.length
    end

    def do_idle_tasks
      if not @confirmed
        @console.open()
      else
        if not @loaded
          load()
          # start SSTP server
          @sstp_controler.start_servers()
          # start plugins
          @plugin_controler.start_plugins(@plugins)
          @loaded = true
        else
          @sstp_controler.handle_sstp_queue()
          @sstp_controler.receive_sstp_request()
          @plugin_controler.check_queue()
        end
      end
      return true
    end
  end

  class Console
    include GetText

    def initialize(app)
      @app = app
      @dialog = Gtk::Dialog.new
      @dialog.signal_connect('delete_event') do |w, e|
        #return true # XXX
      end
      #@log_handler = logging.handlers.BufferingHandler(0)
      #@log_handler.shouldFlush = self.shouldFlush
      #logging.getLogger().addHandler(self.log_handler)
      @sw = Gtk::ScrolledWindow.new
      @sw.set_policy(Gtk::PolicyType::NEVER, Gtk::PolicyType::ALWAYS)
      @sw.show()
      @tv = Gtk::TextView.new
      @tv.set_wrap_mode(Gtk::TextTag::WrapMode::CHAR)
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
      # DnD data types
      #dnd_targets = [['text/uri-list', 0, 0]]
      #@tv.drag_dest_set(Gtk::Drag::DestDefaults::ALL, dnd_targets,
      #                  Gdk::DragContext::Action::COPY)
      @tv.drag_dest_set_target_list(nil) # important
      @tv.drag_dest_add_uri_targets()
      @tv.signal_connect('drag_data_received') do |widget, context, x, y, data, info, time|
        drag_data_received(widget, context, x, y, data, info, time)
      end
      @tv.show()
      @sw.add(@tv)
      @tv.set_size_request(400, 250)
      @sw.set_size_request(400, 250)
      content_area = @dialog.content_area
      content_area.pack_start(@sw, true, true, 0)
      @dialog.add_button('Install', 1)
      @dialog.add_button(Gtk::Stock::CLOSE, Gtk::ResponseType::CLOSE)
      @dialog.signal_connect('response') do |w, e|
        response(w, e)
      end
      @file_chooser = Gtk::FileChooserDialog.new(
        :title => "Install..",
        :action => Gtk::FileChooser::Action::OPEN,
        :buttons => [[Gtk::Stock::OPEN, Gtk::ResponseType::OK],
                    [Gtk::Stock::CANCEL, Gtk::ResponseType::CANCEL]])
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

    def shouldFlush(record)
      it = @tb.get_end_iter()
      if record.levelno >= 50
        tag = @tag_critical
      elsif record.levelno >= 40
        tag = @tag_error
      elsif record.levelno >= 30
        tag = @tag_warning
      elsif record.levelno >= 20
        tag = @tag_info
      elsif record.levelno >= 10
        tag = @tag_debug
      else
        tag = @tag_notset
      end
      @tb.insert_with_tags(
        it,
        [record.levelname, ':', record.getMessage(), '\n'].join(''),
        tag)
      it = @tb.get_end_iter()
      # scroll_to_iter may not have the desired effect.
      mark = @tb.create_mark("end", it, false)
      @tv.scroll_to_mark(mark, 0.0, false, 0.5, 0.5)
    end

    def update
      ghosts, balloons = @app.search_ghosts() # XXX
      if ghosts > 0 and balloons > 0
        @dialog.set_title(_('Console'))
        #logging.info('Ghosts: {0:d}'.format(ghosts))
        #logging.info('Balloons: {0:d}'.format(balloons))
      else
        @dialog.set_title(_('Nanntokashitekudasai.'))
        if ghosts > 0
          #logging.info('Ghosts: {0:d}'.format(ghosts))
        else
          #logging.warning('Ghosts: {0:d}'.format(ghosts))
        end
        if balloons > 0
          #logging.info('Balloons: {0:d}'.format(balloons))
        else
          #logging.warning('Balloons: {0:d}'.format(balloons))
        end
      end
    end

    def open
      if @opened
        return
      end
      update()
      @dialog.show()
      @opened = true
    end

    def close
      @dialog.hide()
      @opened = false
      if not @app.confirmed ## FIXME
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
      if response == Gtk::ResponseType::OK
        filename = @file_chooser.filename
        @app.do_install(filename)
        update()
      elsif response == Gtk::ResponseType::CANCEL
        #pass
      end
      @file_chooser.hide()
    end

    def drag_data_received(widget, context, x, y, data, info, time)
      filelist = []
      for uri in data.uris
        uri_parsed = URI.parse(uri)
        pathname = URI.unescape(uri_parsed.path)
        if uri_parsed.scheme == 'file' and File.exists?(pathname)
          filelist << pathname
        elsif uri_parsed.scheme == 'http' or uri_parsed.scheme == 'ftp'
          filelist << uri
        end
      end
      if not filelist.empty?
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
        #return true # XXX
      end
      @darea = Gtk::DrawingArea.new
      @darea.set_events(Gdk::Event::EXPOSURE_MASK)
      @size = [550, 330]
      @darea.set_size_request(*@size)
      @darea.signal_connect('configure_event') do |w, e|
        configure(w, e)
      end
      @darea.signal_connect('draw') do |w, e|
        redraw(w, e)
      end
      content_area = @dialog.content_area
      content_area.pack_start(@darea, true, true, 0)
      @darea.show()
      @dialog.add_button(Gtk::Stock::CLOSE, Gtk::ResponseType::CLOSE)
      @dialog.signal_connect('response') do |w, e|
        response(w, e)
      end
      @opened = false
    end

    def open(history)
      if @opened
        return
      end
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
      if not ai_list.empty?
        path = ai_list.sample
        #assert File.exists?(path)
        @pixbuf = Pix.create_pixbuf_from_file(path, is_pnr=false)
        @pixbuf.saturate_and_pixelate(@pixbuf, 1.0, true)
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
      if @pixbuf
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
      w2 = w - w1 - w3 - w4 - 70
      x = 20
      y = 15
      x += w1 + 10
      label = 'name'
      layout.set_text(label)
      label_name_w, label_name_h = layout.pixel_size
      cr.set_source_rgb(0.8, 0.8, 0.8) # gray
      cr.move_to(x, y)
      cr.show_pango_layout(layout)
      x = x + w2 + 10
      label = 'rate'
      layout.set_text(label)
      label_rate_w, label_rate_h = layout.pixel_size
      cr.set_source_rgb(0.8, 0.8, 0.8) # gray
      cr.move_to(x + w3 - label_rate_w, y)
      cr.show_pango_layout(layout)
      x += w3 + 10
      label = 'time'
      layout.set_text(label)
      label_time_w, label_time_h = layout.pixel_size
      cr.set_source_rgb(0.8, 0.8, 0.8) # gray
      cr.move_to(x + w4 - label_time_w, y)
      cr.show_pango_layout(layout)
      y += [label_name_h, label_rate_h, label_time_h].max + 4
      for clock, name, name_w, name_h, rate, rate_w, rate_h, time, time_w, \
          time_h in rows
        x = 20
        bw = (clock / total * w1).to_i
        bh = [name_h, rate_h, time_h].max - 1
        cr.set_source_rgb(0.8, 0.8, 0.8) # gray
        cr.rectangle(x + 1, y + 1, bw, bh)
        cr.stroke()
        cr.set_source_rgb(1.0, 1.0, 1.0) # white
        cr.rectangle(x, y, bw, bh)
        cr.stroke()
        cr.set_source_rgb(0.0, 0.0, 0.0) # black
        cr.rectangle(x, y, bw, bh)
        cr.stroke()
        x += w1 + 10
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
        x += w2 + 10
        layout.set_text(rate)
        cr.set_source_rgb(0.0, 0.0, 0.0) # black
        cr.move_to(x + w3 - rate_w, y)
        cr.show_pango_layout(layout)
        x += w3 + 10
        layout.set_text(time)
        cr.set_source_rgb(0.0, 0.0, 0.0) # black
        cr.move_to(x + w4 - time_w, y)
        cr.show_pango_layout(layout)
        y += [name_h, rate_h, time_h].max + 4
      end
    end
  end
end

#if __name__ == '__main__':
#    main()
Ninix_Main.main
