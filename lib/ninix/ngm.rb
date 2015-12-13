# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001-2004 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2004-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "net/http"
require "uri"
require "open-uri"
require "fileutils"

require 'gettext'
require "gtk3"

require_relative "home"
require_relative "pix"
require_relative "install"
require_relative "logging"

module NGM

  # 注意:
  # - このURLを本ゴーストマネージャクローン以外の用途で使う場合は,
  #   「できるだけ事前に」AQRS氏に連絡をお願いします.
  #   (「何かゴーストマネージャ」のページ: http://www.aqrs.jp/ngm/)
  # - アクセスには帯域を多く使用しますので,
  #   必ず日時指定の差分アクセスをし余分な負荷をかけないようお願いします.
  #   (差分アクセスの方法については本プログラムの実装が参考になると思います.)
  MASTERLIST = 'http://www.aqrs.jp/cgi-bin/ghostdb/request2.cgi'

  # 10000以上のIDを持つデータは仮登録
  IDLIMIT = 10000

  ELEMENTS = ['Name', 'SakuraName', 'KeroName', 'GhostType',
              'HPUrl', 'HPTitle', 'Author', 'PublicUrl', 'ArchiveUrl',
              'ArchiveSize', 'ArchiveTime', 'Version', 'AIName',
              'SurfaceSetFlg', 'KisekaeFlg', 'AliasName',
              'SakuraSurfaceList', 'KeroSurfaceList', 'DeleteFlg',
              'NetworkUpdateTime', 'AcceptName', 'NetworkUpdateFlg',
              'SakuraPreviewMD5', 'KeroPreviewMD5', 'ArchiveMD5',
              'InstallDir', 'ArchiveName', 'UpdateUrl',
              'AnalysisError', 'InstallCount']

  class Catalog_xml

    #public methods
    def initialize(datadir)
      @data = {}
      @url = {}
      @cgi = {}
      @datadir = datadir
      if not Dir.exists?(@datadir)
        FileUtils.mkdir_p(@datadir)
      end
      @last_update = '1970-01-01 00:00:00'
      load_MasterList()
    end

    # data handling functions
    def get(entry, key)
      if entry.include?(key)
        return entry[key]
      else
        return nil
      end
    end

    def data
      return @data
    end

    # updates etc
    def network_update#(updatehook)
      last_update = @last_update
      @last_update = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      if not @cgi.empty?
        priority = @cgi.keys.sort
        url = @cgi[priority[-1]][-1]
      else
        url = MASTERLIST
      end
      begin
        uri = URI.parse(url)
        uri.query = URI.encode_www_form({time: ['"', last_update, '"'].join(''), charset: 'UTF-8'})
        open(uri) {|f|
          import_from_fileobj(f)
        }
      rescue
        return ## FIXME
      end
      save_MasterList()
    end

    # private methods
    def load_MasterList
      begin
        f = open(File.join(@datadir, 'MasterList.xml'), 'r')
        for _ in import_from_fileobj(f)
          #pass
        end
        f.close()
      rescue # IOError
        return
      end
    end

    def save_MasterList
      f = open(File.join(@datadir, 'MasterList.xml'), 'w')
      export_to_fileobj(f)
      f.close()
    end

    def get_encoding(line)
      m = Regexp.new('<\?xml version="1.0" encoding="(.+)" \?>').match(line)
      return m[1]
    end

    def create_entry(node)
      entry = {}
      for key, text in node
        raise "assert" unless ELEMENTS.include?(key)
        entry[key] = text
      end
      return entry
    end

    def import_from_fileobj(fileobj)
      line0 = fileobj.readline()
      encoding = get_encoding(line0)
      if not Encoding.name_list.include?(encoding)
        raise SystemExit('Unsupported encoding {0}'.format(repr(encoding)))
      end
      nest = 0
      new_entry = {}
      set_id = nil
      node = []
      re_list = Regexp.compile('<GhostList>')
      re_setid = Regexp.compile('<FileSet ID="?([0-9]+)"?>')
      re_set = Regexp.compile('</FileSet>')
      re_priority = Regexp.compile('<RequestCgiUrl Priority="?([0-9]+)"?>(.+)</RequestCgiUrl>')
      re_misc = Regexp.compile('<(.+)>(.+)</(.+)>')
      for line in fileobj
        while Gtk.events_pending?
          Gtk.main_iteration()
        end
        if line.empty?
          next
        end
        line = line.force_encoding(encoding).encode("UTF-8", :invalid => :replace, :undef => :replace)
        m = re_list.match(line)
        if m != nil
          nest += 1
          next
        end
        m = re_setid.match(line)
        if m != nil
          nest += 1
          set_id = m[1].to_i
          next
        end
        m = re_set.match(line)
        if m != nil
          nest -= 1
          new_entry[set_id] = create_entry(node)
          node = []
          next
        end
        m = re_priority.match(line)
        if m != nil
          g = m
          priority = g[1].to_i
          url = g[2]
          if @cgi.include?(priority)
            @cgi[priority] << url
          else
            @cgi[priority] = [url]
          end
          next
        end
        m = re_misc.match(line)
        if m != nil
          g = m
          if set_id != nil
            key = g[1]
            text = g[2]
            text = text.sub('&apos;', '\'')                
            text = text.sub('&quot;', '"')
            text = text.sub('&gt;', '>')
            text = text.sub('&lt;', '<')
            text = text.sub('&amp;', '&')
            node << [key, text]
          else
            key = g[1]
            text = g[2]
            #assert key in ['LastUpdate', 'NGMVersion',
            #               'SakuraPreviewBaseUrl',
            #               'KeroPreviewBaseUrl',
            #               'ArcMD5BaseUrl', 'NGMUpdateBaseUrl']
            if key == 'LastUpdate'
              @last_update = text
            elsif key == 'NGMVersion'
              version = text.to_f
              if version < 0.51
                return
              else
                @version = version
              end
            elsif ['SakuraPreviewBaseUrl', 'KeroPreviewBaseUrl',
                   'ArcMD5BaseUrl', 'NGMUpdateBaseUrl'].include?(key)
              @url[key] = text
            end
          end
        end
      end
      @data.update(new_entry)        
    end

    def dump_entry(entry, fileobj)
      for key in ELEMENTS
        if entry.include?(key) and entry[key] != nil
          text = entry[key]
          text = text.gsub("&", "&amp;")
          text = text.gsub("<", "&lt;")
          text = text.gsub(">", "&gt;")
          text = text.gsub("\"", "&quot;")
          text = text.gsub("'", "&apos;'")
        else
          text = '' # fileobj.write('  <{0}/>\n'.format(key))
        end
        fileobj.write(["  <", key, ">", text, "</", key, ">\n"].join(""))
      end
    end

    def export_to_fileobj(fileobj)
      fileobj.write("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n")
      fileobj.write("<GhostList>\n")
      fileobj.write(["<LastUpdate>", @last_update, "</LastUpdate>\n"].join(""))
      for key in ["SakuraPreviewBaseUrl", "KeroPreviewBaseUrl",
                  "ArcMD5BaseUrl", "NGMUpdateBaseUrl"]
        if @url.include?(key)
          fileobj.write(["<", key, ">", @url[key], "</", key, ">\n"].join(""))
        else
          fileobj.write(["<", key, "></", key, ">\n"].join(""))
        end
      end
      fileobj.write(["<NGMVersion>", @version, "</NGMVersion>\n"].join(""))
      key_list = @cgi.keys.sort
      key_list.reverse()
      for priority in key_list
        for url in @cgi[priority]
          fileobj.write(
                        ["<RequestCgiUrl Priority=\"", priority, "\">", url, "</RequestCgiUrl>\n"].join(""))
        end
      end
      ids = @data.keys.sort
      for set_id in ids
        fileobj.write(["<FileSet ID=\"", set_id, "\">\n"].join(""))
        entry = @data[set_id]
        dump_entry(entry, fileobj)
        fileobj.write("</FileSet>\n")
      end
      fileobj.write("</GhostList>\n")
    end
  end


  class Catalog < Catalog_xml

    TYPE = ['Sakura', 'Kero']

    def image_filename(set_id, side)
      p = TYPE[side] + "_" + set_id.to_s + ".png"
      d = File.join(@datadir, p)
      if File.exists?(d)
        return d
      else
        return nil
      end
    end

    def retrieve_image(set_id, side)#, updatehook)
      p = [TYPE[side], '_', set_id, '.png'].join('')
      d = File.join(@datadir, p)
      if not File.exists?(d)
        if side == 0
          url = @url['SakuraPreviewBaseUrl']
        else
          url = @url['KeroPreviewBaseUrl']
        end
        begin
          open(d, "wb") do |file|
            open([url, p].join("")) do |data|
              file.write(data.read)
            end
          end
        rescue
          return ## FIXME
        end
      end
    end
  end


  class SearchDialog
  include GetText

    def initialize
      @parent = nil
      @dialog = Gtk::Dialog.new
      @dialog.signal_connect('delete_event') do |a|
        return true # XXX
      end
      @dialog.set_modal(true)
      @dialog.set_window_position(Gtk::Window::Position::CENTER)
      label = Gtk::Label.new(label=_('Search for'))
      content_area = @dialog.content_area
      content_area.add(label)
      @pattern_entry = Gtk::Entry.new()
      @pattern_entry.set_size_request(300, -1)
      content_area.add(@pattern_entry)
      content_area.show_all()
      @dialog.add_button("_OK", Gtk::ResponseType::OK)
      @dialog.add_button("_Cancel", Gtk::ResponseType::CANCEL)
      @dialog.signal_connect('response') do |w, r|
        response(w, r)
      end
    end

    def set_responsible(parent)
      @parent = parent
    end

    def set_pattern(text)
      @pattern_entry.set_text(text)
    end
                
    def get_pattern
      return @pattern_entry.text
    end

    def hide
      @dialog.hide()
    end

    def show(default: nil)
      if default != nil
        set_pattern(default)
      end
      @dialog.show()
    end

    def ok
      word = get_pattern()
      @parent.handle_request('NOTIFY', 'search', word)
      hide()
    end

    def cancel
      hide()
    end

    def response(widget, response)
      if response == Gtk::ResponseType::OK
        ok()
      elsif response == Gtk::ResponseType::CANCEL
        cancel()
      elsif response == Gtk::ResponseType::DELETE_EVENT
        cancel()
      else
        # should not reach here
      end
      return true
    end
  end


  class UI
  include GetText

    def initialize
      @parent = nil
      @ui_info = "
        <ui>
          <menubar name='MenuBar'>
            <menu action='FileMenu'>
              <menuitem action='Search'/>
              <menuitem action='Search Forward'/>
              <separator/>
              <menuitem action='Settings'/>
              <separator/>
              <menuitem action='DB Network Update'/>
              <separator/>
              <menuitem action='Close'/>
            </menu>
            <menu action='ViewMenu'>
              <menuitem action='Mask'/>
              <menuitem action='Reset to Default'/>
              <menuitem action='Show All'/>
            </menu>
            <menu action='ArchiveMenu'>
            </menu>
            <menu action='HelpMenu'>
            </menu>
          </menubar>
        </ui>"
      @entries = [
                  [ 'FileMenu', nil, _('_File') ],
                  [ 'ViewMenu', nil, _('_View') ],
                  [ 'ArchiveMenu', nil, _('_Archive') ],
                  [ 'HelpMenu', nil, _('_Help') ],
                  [ 'Search', nil,                  # name, stock id
                    _('Search(_F)'), '<control>F',   # label, accelerator
                    'Search',                        # tooltip
                    lambda {|a, b| open_search_dialog()} ],
                  [ 'Search Forward', nil,
                    _('Search Forward(_S)'), 'F3',
                    nil,
                    lambda {|a, b| search_forward()} ],
                  [ 'Settings', nil,
                    _('Settings(_O)'), nil,
                    nil,
                    lambda {|a, b| @parent.handle_request(
                                                          'NOTIFY', 'open_preference_dialog')} ],
                  [ 'DB Network Update', nil,
                    _('DB Network Update(_N)'), nil,
                    nil,
                    lambda {|a, b| network_update()} ],
                  [ 'Close', nil,
                    _('Close(_X)'), nil,
                    nil,
                    lambda {|a, b| close()} ],
                  [ 'Mask', nil,
                    _('Mask(_M)'), nil,
                    nil,
                    lambda {|a, b| @parent.handle_request(
                                                          'NOTIFY', 'open_mask_dialog')} ],
                  [ 'Reset to Default', nil,
                    _('Reset to Default(_Y)'), nil,
                    nil,
                    lambda {|a, b| @parent.handle_request(
                                                          'NOTIFY', 'reset_to_default')} ],
                  [ 'Show All', nil,
                    _('Show All(_Z)'), nil,
                    nil,
                    lambda {|a, b| @parent.handle_request(
                                                          'NOTIFY', 'show_all')} ],
                  ]
      @opened = false
      @textview = [nil, nil]
      @darea = [nil, nil]
      @surface = [nil, nil]
      @info = nil
      @button = {}
      @url = {}
      @search_word = ''
      @search_dialog = SearchDialog.new()
      @search_dialog.set_responsible(self)
      create_dialog()
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      #assert event_type in ['GET', 'NOTIFY']
      handlers = {
      }
      if handlers.include?(event)
        result = handlers[event].call #(*arglist)
      else
        begin
          result = public_send(event, *arglist)
        rescue
          result = @parent.handle_request(
            event_type, event, *arglist)
        end
      end
      if event_type == 'GET'
        return result
      end
    end

    def create_dialog
      @window = Gtk::Window.new()
      @window.set_title(_('Ghost Manager'))
      @window.set_resizable(false)
      @window.signal_connect('delete_event') do |a|
        close()
      end
      @window.set_window_position(Gtk::Window::Position::CENTER)
      @window.gravity = Gdk::Gravity::CENTER
      actions = Gtk::ActionGroup.new('Actions')
      actions.add_actions(@entries)
      ui = Gtk::UIManager.new()
      ui.insert_action_group(actions, 0)
      @window.add_accel_group(ui.accel_group)
      begin
        mergeid = ui.add_ui(@ui_info)
      rescue => e #except GObject.GError as msg:
        Logging::Logging.error('building menus failed: ' + e.message)
      end
      vbox = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL)
      @window.add(vbox)
      vbox.show()
      vbox.pack_start(ui.get_widget('/MenuBar'), :expand => false, :fill => false, :padding => 0)
      separator = Gtk::Separator.new(:horizontal)
      vbox.pack_start(separator, :expand => false, :fill => true, :padding => 0)
      separator.show()
      hbox = Gtk::Box.new(orientation=Gtk::Orientation::HORIZONTAL)
      vbox.pack_start(hbox, :expand => false, :fill => true, :padding => 10)
      hbox.show()
      @surface_area_sakura = create_surface_area(0)
      hbox.pack_start(@surface_area_sakura, :expand => false, :fill => true, :padding => 10)
      @surface_area_kero = create_surface_area(1)
      hbox.pack_start(@surface_area_kero, :expand => false, :fill => true, :padding => 10)
      @info_area = create_info_area()
      hbox.pack_start(@info_area, :expand => false, :fill => true, :padding => 10)
      box = Gtk::ButtonBox.new(orientation=Gtk::Orientation::HORIZONTAL)
      box.set_layout_style(Gtk::ButtonBox::Style::SPREAD)
      vbox.pack_start(box, :expand => false, :fill => true, :padding => 4)
      box.show()
      button = Gtk::Button.new(:label => _('Previous'))
      button.signal_connect('clicked') do |b, w=self|
        w.show_previous()
      end
      box.add(button)
      button.show()
      @button['previous'] = button
      button = Gtk::Button.new(:label => _('Next'))
      button.signal_connect('clicked') do |b, w=self|
        w.show_next()
      end
      box.add(button)
      button.show()
      @button['next'] = button
      @statusbar = Gtk::Statusbar.new()
      vbox.pack_start(@statusbar, :expand => false, :fill => true, :padding => 0)
      @statusbar.show()
    end

    def network_update
      @window.set_sensitive(false)
      @parent.handle_request('NOTIFY', 'network_update')#, updatehook)
      update()
      @window.set_sensitive(true)
    end

    def open_search_dialog
      @search_dialog.show(:default => @search_word)
    end

    def search(word)
      if word != nil and not word.empty?
        @search_word = word
        if @parent.handle_request('GET', 'search', word)
          update()
        else
          #pass ## FIXME
        end
      end
    end

    def search_forward
      if not @search_word.empty?
        if @parent.handle_request('GET', 'search_forward', @search_word)
          update()
        else
          #pass ## FIXME
        end
      end
    end

    def show_next
      @parent.handle_request('NOTIFY', 'go_next')
      update()
    end

    def show_previous
      @parent.handle_request('NOTIFY', 'previous')
      update()
    end

    def create_surface_area(side)
      #assert side in [0, 1]
      vbox = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL)
      vbox.show()
      textview = Gtk::TextView.new()
      textview.set_editable(false)
      textview.set_size_request(128, 16)
      vbox.pack_start(textview, :expand => false, :fill => true, :padding => 0)
      textview.show()
      @textview[side] = textview
      darea = Gtk::DrawingArea.new()
      vbox.pack_start(darea, :expand => false, :fill => true, :padding => 0)
      darea.set_events(Gdk::EventMask::EXPOSURE_MASK)
      darea.signal_connect('draw') do |w, c|
        redraw(w, c, side)
      end
      darea.show()
      @darea[side] = darea
      return vbox
    end

    def redraw(widget, cr, side)
      if @surface[side] != nil
        cr.set_source(@surface[side], 0, 0)
        cr.set_operator(Cairo::OPERATOR_OVER)
        cr.paint()
      else
        cr.set_operator(Cairo::OPERATOR_CLEAR)
        cr.paint()
      end
    end

    def update_surface_area
      for side in [0, 1]
        if side == 0
          target = 'SakuraName'
        else
          target = 'KeroName'
        end
        name = @parent.handle_request('GET', 'get', target)
        textbuffer = @textview[side].buffer
        textbuffer.set_text(name.to_s)
        filename = @parent.handle_request('GET', 'get_image_filename', side)
        darea = @darea[side]
        darea.realize()
        if filename != nil and not filename.empty?
          begin
            surface = Pix.create_surface_from_file(filename)
          rescue
            surface = nil
          end
            w = surface.width
            h = surface.height
            darea.set_size_request(w, h)
        else
          surface = nil
        end
        @surface[side] = surface
        darea.queue_draw()
      end
    end

    def create_info_area
      vbox = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL)
      vbox.show()
      hbox = Gtk::Box.new(orientation=Gtk::Orientation::HORIZONTAL)
      box = Gtk::ButtonBox.new(orientation=Gtk::Orientation::HORIZONTAL)
      box.set_layout_style(Gtk::ButtonBox::Style::SPREAD)
      box.show()
      button = Gtk::Button.new(:label => _('Install'))
      button.signal_connect(
                     'clicked') do |b, w=self|
        w.handle_request('NOTIFY', 'install_current')
      end
      box.add(button)
      button.show()
      @button['install'] = button
      button = Gtk::Button.new(:label => _('Update'))
      button.signal_connect(
                     'clicked') do |b, w=self|
        w.handle_request('NOTIFY', 'update_current')
      end
      box.add(button)
      button.show()
      @button['update'] = button
      hbox.pack_start(box, :expand => true, :fill => true, :padding => 10)
      vbox2 = Gtk::Box.new(orientation=Gtk::Orientation::VERTICAL)
      hbox.pack_start(vbox2, :expand => false, :fill => true, :padding => 0)
      vbox2.show()
      button = Gtk::Button.new(:label => '') # with GtkLabel
      button.set_relief(Gtk::ReliefStyle::NONE)
      @url['HP'] = [nil, button.child]
      vbox2.pack_start(button, :expand => false, :fill => true, :padding => 0)
      button.signal_connect(
                     'clicked') do |b|
        webbrowser.open(@url['HP'][0])
      end
      button.show()
      button = Gtk::Button.new(:label => '')
      button.set_relief(Gtk::ReliefStyle::NONE)
      button.set_use_underline(true)
      @url['Public'] = [nil, button.child]
      vbox2.pack_start(button, :expand => false, :fill => true, :padding => 0)
      button.signal_connect(
                     'clicked') do |b|
        webbrowser.open(@url['Public'][0])
      end
      button.show()
      vbox.pack_start(hbox, :expand => false, :fill => true, :padding => 0)
      hbox.show()
      textview = Gtk::TextView.new()
      textview.set_editable(false)
      textview.set_size_request(256, 144)
      vbox.pack_start(textview, :expand => false, :fill => true, :padding => 0)
      textview.show()
      @info = textview
      return vbox
    end

    def update_info_area
      info_list = [[_('Author:'), 'Author'],
                   [_('ArchiveTime:'), 'ArchiveTime'],
                   [_('ArchiveSize:'), 'ArchiveSize'],
                   [_('NetworkUpdateTime:'), 'NetworkUpdateTime'],
                   [_('Version:'), 'Version'],
                   [_('AIName:'), 'AIName']]
      text = ''
      text = [text, @parent.handle_request('GET', 'get', 'Name'), "\n"].join('')
      for item in info_list
        text = [text, item[0],
                @parent.handle_request('GET', 'get', item[1]), "\n"].join('')
      end
      text = [text,
              @parent.handle_request('GET', 'get', 'SakuraName'),
              _('SurfaceList:'),
              @parent.handle_request('GET', 'get', 'SakuraSurfaceList'),
              "\n"].join('')
      text = [text,
              @parent.handle_request('GET', 'get', 'KeroName'),
              _('SurfaceList:'),
              @parent.handle_request('GET', 'get', 'KeroSurfaceList'),
              "\n"].join('')
      textbuffer = @info.buffer
      textbuffer.set_text(text)
      url = @parent.handle_request('GET', 'get', 'HPUrl')
      text = @parent.handle_request('GET', 'get', 'HPTitle')
      @url['HP'][0] = url
      label = @url['HP'][1]
      label.set_markup('<span foreground="blue">' + text.to_s + '</span>')
      url = @parent.handle_request('GET', 'get', 'PublicUrl')
      text = [@parent.handle_request('GET', 'get', 'Name'),
              _(' Web Page')].join('')
      @url['Public'][0] = url
      label = @url['Public'][1]
      label.set_markup('<span foreground="blue">' + text.to_s + '</span>')
      target_dir = File.join(
                             @parent.handle_request('GET', 'get_home_dir'),
                             'ghost',
                             @parent.handle_request('GET', 'get', 'InstallDir'))
      @button['install'].set_sensitive(
                                       (not File.directory?(target_dir) and
                                       @parent.handle_request('GET', 'get', 'ArchiveUrl') != 'No data'))
      @button['update'].set_sensitive(
                                      (File.directory?(target_dir) and
                                       @parent.handle_request('GET', 'get', 'GhostType') == 'ゴースト' and
                                       @parent.handle_request('GET', 'get', 'UpdateUrl') != 'No data'))
    end

    def update
      update_surface_area()
      update_info_area()
      @button['next'].set_sensitive(
                                    @parent.handle_request('GET', 'exist_next'))
      @button['previous'].set_sensitive(
                                        @parent.handle_request('GET', 'exist_previous'))
    end

    def show
      if @opened
        return
      end
      update()
      @window.show()
      @opened = true
    end

    def close
      @window.hide()
      @opened = false
      return true
    end
  end


  class NGM

    def initialize
      @parent = nil
      @current = 0
      @opened = false
      @home_dir = Home.get_ninix_home()
      @catalog = Catalog.new(File.join(@home_dir, 'ngm/data'))
      @installer = Install::Installer.new()
      @ui = UI.new()
      @ui.set_responsible(self)
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      #assert event_type in ['GET', 'NOTIFY']
      handlers = {
        'get_home_dir' => lambda {|*a| return  @home_dir },
        'network_update' => lambda {|*a| return network_update },
        'get' => lambda {|*a| return get(a[0]) }
      }
      if handlers.include?(event)
        result = handlers[event].call(*arglist)
      else
        begin
          result = public_send(event, *arglist)
        rescue
          result = @parent.handle_request(event_type, event, *arglist)
        end
      end
      if event_type == 'GET'
        return result
      end
    end

    def get(element)
      if @catalog.data.include?(@current)
        entry = @catalog.data[@current]
        text = @catalog.get(entry, element)
        if text != nil
          return text
        end
      end
      return 'No data'
    end

    def get_image_filename(side)
      return @catalog.image_filename(@current, side)
    end

    def search(word, set_id: 0)
      while set_id < IDLIMIT
        if @catalog.data.include?(set_id)
          entry = @catalog.data[set_id]
          for element in ['Name', 'SakuraName', 'KeroName',
                          'Author', 'HPTitle']
            text = @catalog.get(entry, element)
            if text == nil or text.empty?
              next
            end
            if text.include?(word)
              @current = set_id
              return true
            end
          end
        end
        set_id += 1
      end
      return false
    end

    def search_forward(word)
      return search(word, :set_id => @current + 1)
    end

    def open_preference_dialog
      #pass
    end

    def network_update#(updatehook)
      @catalog.network_update#(updatehook)
      for set_id in @catalog.data.keys
        for side in [0, 1]
          @catalog.retrieve_image(set_id, side)#, updatehook)
        end
      end
    end

    def open_mask_dialog
      #pass
    end

    def reset_to_default
      #pass
    end

    def show_all
      #pass
    end

    def go_next
      next_index = @current + 1
      if next_index < IDLIMIT and @catalog.data.include?(next_index)
        @current = next_index
      end
    end

    def exist_next
      next_index = @current + 1
      return (next_index < IDLIMIT and @catalog.data.include?(next_index))
    end

    def previous
      previous = @current - 1
      #assert previous < IDLIMIT
      if @catalog.data.include?(previous)
        @current = previous
      end
    end

    def exist_previous
      previous = @current - 1
      #assert previous < IDLIMIT
      return @catalog.data.include?(previous)
    end

    def show_dialog
      @ui.show()
    end

    def install_current
      begin
        filetype, target_dir = @installer.install(get('ArchiveUrl'),
                                                  Home.get_ninix_home())
      rescue
        target_dir = nil
      end
      assert filetype == 'ghost'
      if target_dir != nil
        @parent.handle_request('NOTIFY', 'add_sakura', target_dir)
      end
    end

    def update_current
      @parent.handle_request('NOTIFY', 'update_sakura', get('Name'), 'NGM')
    end
  end
end
