# -*- coding: utf-8 -*-
#
#  Copyright (C) 2003-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'gettext'
require "gtk3"

require "ninix/pix"

module Menu

  class Menu
    include GetText

    bindtextdomain("ninix-aya")

    def initialize
#        self.request_parent = lambda *a: None # dummy
      @parent = nil
      ui_info = "
        <ui>
          <popup name='popup'>
            <menu action='Recommend'>
            </menu>
            <menu action='Portal'>
            </menu>
            <separator/>
            <menu action='Plugin'>
            </menu>
            <menuitem action='Stick'/>
            <separator/>
            <menu action='Options'>
            <menuitem action='Update'/>
            <menuitem action='Vanish'/>
            <menuitem action='Preferences'/>
            <menuitem action='Console'/>
            <menuitem action='Manager'/>
            </menu>
            <separator/>
            <menu action='Change'>
            </menu>
            <menu action='Summon'>
            </menu>
            <menu action='Shell'>
            </menu>
            <menu action='Costume'>
            </menu>
            <menu action='Balloon'>
            </menu>
            <separator/>
            <menu action='Information'>
            <menuitem action='Usage'/>
            <menuitem action='Version'/>
            </menu>
            <separator/>
            <menu action='Nekodorif'>
            </menu>
            <menu action='Kinoko'>
            </menu>
            <separator/>
            <menuitem action='Close'/>
            <menuitem action='Quit'/>
          </popup>
        </ui>
        "
        @__menu_list = {
            'Portal' => {
                'entry' => ['Portal', nil, _('Portal sites(_P)'), nil],
                'visible' => 1},
            'Recommend' => {
                'entry' => ['Recommend', nil, _('Recommend sites(_R)'), nil],
                'visible' => 1},
            'Options' => {
                'entry' => ['Options', nil, _('Options(_F)'), nil],
                'visible' => 1},
            'Options/Update' => {
                'entry' => ['Update', nil, _('Network Update(_U)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'network_update')}],
                'visible' => 1},
            'Options/Vanish' => {
                'entry' => ['Vanish', nil, _('Vanish(_F)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'vanish')}],
                'visible' => 1},
            'Options/Preferences' => {
                'entry' => ['Preferences', nil, _('Preferences...(_O)'), nil,
                           '', lambda {|a, b| @parent.handle_request('NOTIFY', 'edit_preferences')}],
                'visible' => 1},
            'Options/Console' => {
                'entry' => ['Console', nil, _('Console(_C)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'open_console')}],
                'visible' => 1},
            'Options/Manager' => {
                'entry' => ['Manager', nil, _('Ghost Manager(_M)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'open_ghost_manager')}],
                'visible' => 1},
            'Information' => {
                'entry' => ['Information', nil, _('Information(_I)'), nil],
                'visible' => 1},
            'Information/Usage' => {
                'entry' => ['Usage', nil, _('Usage graph(_A)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'show_usage')}],
                'visible' => 1},
            'Information/Version' => {
                'entry' => ['Version', nil, _('Version(_V)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'about')}],
                'visible' => 1},
            'Close' => {
                'entry' => ['Close', nil, _('Close(_W)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'close_sakura')}],
                'visible' => 1},
            'Quit' => {
                'entry' => ['Quit', nil, _('Quit(_Q)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'close_all')}],
                'visible' => 1},
            'Change' => {
                'entry' => ['Change', nil, _('Change(_G)'), nil],
                'visible' => 1},
            'Summon' => {
                'entry' => ['Summon', nil, _('Summon(_X)'), nil],
                'visible' => 1},
            'Shell' => {
                'entry' => ['Shell', nil, _('Shell(_S)'), nil],
                'visible' => 1},
            'Balloon' => {
                'entry' => ['Balloon', nil, _('Balloon(_B)'), nil],
                'visible' => 1},
            'Costume' => {
                'entry' => ['Costume', nil, _('Costume(_C)'), nil],
                'visible' => 1},
            'Stick' => {
                'entry' => ['Stick', nil, _('Stick(_Y)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'stick_window')},
                          false],
                'visible' => 1},
            'Nekodorif' => {
                'entry' => ['Nekodorif', nil, _('Nekodorif(_N)'), nil],
                'visible' => 1},
            'Kinoko' => {
                'entry' => ['Kinoko', nil, _('Kinoko(_K)'), nil],
                'visible' => 1},
            'Plugin' => {
                'entry' => ['Plugin', nil, _('Plugin(_P)'), nil],
                'visible' => 1},
            }
      @__fontcolor = {
        'normal' => [0, 0, 0],
        'prelight' => [255, 255, 255]
      }
      @__imagepath = {
        'background' => nil,
        'foreground' => nil,
        'background_with_sidebar' => nil,
        'foreground_with_sidebar' => nil
      }
      @__align = {
        'background' => nil,
        'foreground' => nil,
        'sidebar' => nil
      }
      actions = Gtk::ActionGroup.new('Actions')
      entry = []
#      for key, value in @__menu_list.items()
      for key in @__menu_list.keys
        value = @__menu_list[key]
        if key != 'Stick'
          entry << value['entry']
        end
      end
      actions.add_actions(entry)
      actions.add_toggle_actions([@__menu_list['Stick']['entry']])
      @ui_manager = Gtk::UIManager.new()
      @ui_manager.insert_action_group(actions, 0)
      @ui_manager.add_ui(ui_info)
      @__popup_menu = @ui_manager.get_widget('/popup')
      @__popup_menu.signal_connect('realize') do |i, *a|
          set_stylecontext_with_sidebar(i, *a)
      end
      for key in @__menu_list.keys
        item = @ui_manager.get_widget(['/popup/', key].join(''))
        item.signal_connect('draw') do |i, *a|
          set_stylecontext(i, *a)
        end
        submenu = item.submenu
        if submenu
          submenu.signal_connect('realize') do |i, *a|
            set_stylecontext(i, *a)
          end
        end
      end
    end

    def set_responsible(parent)
      @parent = parent
    end

    def set_fontcolor(background, foreground)
      @__fontcolor['normal'] = background
      @__fontcolor['prelight'] = foreground
    end

    def set_pixmap(path_background, path_sidebar, path_foreground,
                   align_background, align_sidebar, align_foreground)
      @__imagepath['background'] = nil
      @__imagepath['foreground'] = nil
      @__imagepath['background_with_sidebar'] = nil
      @__imagepath['foreground_with_sidebar'] = nil
      @__align['background'] = align_background
      @__align['foreground'] = align_foreground
      @__align['sidebar'] = align_sidebar
      if path_background != nil and os.path.exists(path_background)
        begin
          color = ninix.pix.get_png_lastpix(path_background)
          @__imagepath['background'] = ["background-image: url('",
                                        path_background, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if path_sidebar != nil and os.path.exists(path_sidebar)
              sidebar_width, sidebar_height = ninix.pix.get_png_size(path_sidebar)
            @__imagepath['background_with_sidebar'] = ["background-image: url('",
                                                       path_sidebar,
                                                       "'),url('",
                                                       path_background, "');\n",
                                                       "background-repeat: no-repeat, repeat-x;\n",
                                                       "background-color: ", color, ";\n"].join('')
            @sidebar_width = sidebar_width
          else
            @sidebar_width = 0
          end
        rescue #except:
          # pass
        end
      end
      if @__imagepath['background'] == nil
        @__imagepath['background'] = ["background-image: none;\n",
                                      "background-color: transparent;\n"].join('')
      end
      if path_foreground != nil and os.path.exists(path_foreground)
        begin
          color = ninix.pix.get_png_lastpix(path_foreground)
          @__imagepath['foreground'] = ["background-image: url('",
                                        path_foreground, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if path_sidebar != nil and os.path.exists(path_sidebar)
            sidebar_width, sidebar_height = ninix.pix.get_png_size(path_sidebar)
            @__imagepath['foreground_with_sidebar'] = ["background-image: url('",
                                                       path_sidebar, "'),url('",
                                                       path_foreground, "');\n",
                                                       "background-repeat: no-repeat, repeat-x;\n",
                                                       "background-color: ", color, ";\n"].join('')
            @sidebar_width = sidebar_width
          else
            @sidebar_width = 0
          end
        rescue # except:
          @pass
        end
      end
      if @__imagepath['foreground'] == nil
        @__imagepath['foreground'] = ["background-image: none;\n",
                                        "background-color: transparent;\n"].join('')
      end
    end

    def __set_mayuna_menu(side)
      if @__mayuna_menu.length > side and @__mayuna_menu[side] != nil
        menuitem = @ui_manager.get_widget(['/popup/', 'Costume'].join(''))
        menuitem.set_submenu(@__mayuna_menu[side])
        __set_visible('Costume', 1)
      else
        __set_visible('Costume', 0)
      end
    end

    def create_mayuna_menu(mayuna_menu)
      @__mayuna_menu = []
      for side in mayuna_menu
        if side == 'sakura'
          index = 0
        elsif side == 'kero'
          index = 1
        elsif side.startswith('char')
          begin
            index = int(side[4, side.length])
          rescue #except:
            next
          end
        else
          next
        end
        for _ in range(@__mayuna_menu.length, index + 1)
          @__mayuna_menu << nil
        end
        if mayuna_menu[side]
          @__mayuna_menu[index] = Gtk::Menu.new()
          item = Gtk::TearoffMenuItem.new()
          item.show()
          @__mayuna_menu[index] << item
          for j in range(mayuna_menu[side].length)
            key, name, state = mayuna_menu[side][j]
            if key != '-'
              item = Gtk::CheckMenuItem.new(name)
              item.set_name('popup menu item')
              item.set_active(bool(state))
              item.signal_connect('activate') do |a, k|
                @parent.handle_request(
                                       'NOTIFY', 'toggle_bind', index, key)
              end
              item.signal_connect('draw') do |i, *a|
                  set_stylecontext(i, *a)
              end
            else
              item = Gtk::SeparatorMenuItem.new()
            end
            item.show()
            @__mayuna_menu[index] << item
          end
          @__mayuna_menu[index].signal_connect('realize') do |i, *a|
            set_stylecontext(i, *a)
          end
        end
      end
    end

    __re_shortcut = Regexp.new('&(?=[\x21-\x7e])')

    def __modify_shortcut(caption)
      return self.__re_shortcut.sub('_', caption)
    end

    __re_mnemonic = Regexp.new('\(_.\)|_')

    def __cut_mnemonic(caption)
      return self.__re_mnemonic.sub('', caption)
    end

    def __update_ui(side)
      @__ui = {
        'Options/Update' => [[['updatebuttoncaption', 'updatebutton.caption'],
                              ['updatebuttoncaption', 'updatebutton.caption']],
                             '(_U)', [[],[]]],
        'Options/Vanish' => [[['vanishbuttoncaption', 'vanishbutton.caption'],
                              ['vanishbuttoncaption', 'vanishbutton.caption']],
                             '(_F)',
                             [['vanishbuttonvisible', 'vanishbutton.visible'],
                              ['vanishbuttonvisible', 'vanishbutton.visible']]],
        'Portal' => [[['sakura.portalbuttoncaption',
                       'portalrootbutton.caption'], []], '(_P)', [[], nil]],
        'Recommend' => [[['sakura.recommendbuttoncaption',
                          'recommendrootbutton.caption'],
                         ['kero.recommendbuttoncaption']], '(_R)', [[], []]],
      }
      for key in @__ui.keys
        #assert @__menu_list.include?(key)
        if side > 1
          if ['Options/Update', 'Options/Vanish'].include?(key)
            name_list = @__ui[key][0][1] # same as 'kero'
          elsif key == 'Portal'
            name_list = [] # same as 'kero'
          elsif key == 'Recommend'
            name_list = ['char{0:d}.recommendbuttoncaption'.format(side)]
          else
            name_list = @__ui[key][0][side]
          end
          if name_list # caption
            for name in name_list
              caption = @parent.handle_request('GET', 'getstring', name)
              if caption
                break
              end
              if caption
                caption = __modify_shortcut(caption)
                if caption == __cut_mnemonic(caption)
                  caption = [caption, @__ui[key][1]].join('')
                end
                __set_caption(key, caption)
              end
            end
          end
        end
        if side > 1
          name_list = @__ui[key][2][1] # same as 'kero'
        else
          name_list = @__ui[key][2][side]
        end
        if name_list # visible
          for name in name_list
            visible = @parent.handle_request('GET', 'getstring', name)
            if visible != nil
              break
            end
            if visible == '0'
              __set_visible(key, 0)
            else
              __set_visible(key, 1)
            end
          end
        elsif name_list == nil
          __set_visible(key, 0)
        end
      end
    end

    def popup(button, side)
      @__popup_menu.unrealize()
      for key in @__menu_list.keys
        item = @ui_manager.get_widget(['/popup/', key].join(''))
        submenu = item.submenu
        if submenu
          submenu.unrealize()
        end
      end
      if side > 1
        string = 'char{0:d}'.format(side)
      else
        #assert [0, 1].include?(side) ## FIXME
        string = ['sakura', 'kero'][side]
      end
      string = [string, '.popupmenu.visible'].join('')
      if @parent.handle_request('GET', 'getstring', string) == '0'
        return
      end
      __update_ui(side)
      if side == 0
        portal = @parent.handle_request(
                                        'GET', 'getstring', 'sakura.portalsites')
      else
        portal = nil
      end
      __set_portal_menu(side, portal)
      if side > 1
        string = 'char{0:d}'.format(side)
      else
        #assert [0, 1].include?(side) ## FIXME
        string = ['sakura', 'kero'][side]
      end
      string = [string, '.recommendsites'].join('')
      recommend = @parent.handle_request('GET', 'getstring', string)
      __set_recommend_menu(recommend)
      __set_ghost_menu()
      __set_shell_menu()
      __set_balloon_menu()
      __set_plugin_menu()
      __set_mayuna_menu(side)
      __set_nekodorif_menu()
      __set_kinoko_menu()
      for key in @__menu_list.keys
        item = @ui_manager.get_widget(['/popup/', key].join(''))
        visible = @__menu_list[key]['visible']
        if item
          if visible
            item.show()
          else
            item.hide()
          end
        end
      end
      @__popup_menu.popup(nil, nil, button,
                          Gtk.current_event_time())
    end

    def __set_caption(name, caption)
      #assert @__menu_list.include?(name)
      #assert isinstance(caption, str)
      item = @ui_manager.get_widget(['/popup/', name].join(''))
      if item
        label = item.get_children()[0]
        label.set_text_with_mnemonic(caption)
      end
    end

    def __set_visible(name, visible)
      #assert @__menu_list.include?(name)
      #assert [0, 1].include?(visible)
      @__menu_list[name]['visible'] = visible
    end

    def __set_portal_menu(side, portal)
      if side >= 1
        __set_visible('Portal', 0)
      else
            if portal
              menu = Gtk::Menu.new()
              portal_list = portal.split(chr(2))
              for site in portal_list
                entry = site.split(chr(1))
                if not entry
                  continue
                end
                title = entry[0]
                if title == '-'
                  item = Gtk::SeparatorMenuItem.new()
                else
                  item = Gtk::MenuItem.new(title)
                  if entry.length < 2
                    item.set_sensitive(false)
                  end
                  if entry.length > 1    
                    url = entry[1]
                  end
                  if entry.length > 2
                    base_path = @parent.handle_request(
                                                       'GET', 'get_prefix')
                    filename = entry[2].lower()
                    head, tail = os.path.splitext(filename)
                    if not tail
                      for ext in ['.png', '.jpg', '.gif']
                        filename = [filename, ext].join('')
                        banner = os.path.join(
                                              base_path, 'ghost/master/banner',
                                              os.fsencode(filename))
                        if not os.path.exists(banner)
                          banner = nil
                        else
                          break
                        end
                      end
                    else
                      banner = os.path.join(
                                            base_path, 'ghost/master/banner',
                                            os.fsencode(filename))
                      if not os.path.exists(banner)
                        banner = nil
                      end
                    end
                  else
                    banner = nil
                  end
                  if entry.length > 1    
                    item.signal_connect('activate') do |a, i|
                  @parent.handle_request(
                                         'NOTIFY', 'notify_site_selection', title, url)
                end
                    item.set_has_tooltip(true)
                    item.signal_connect('query-tooltip') do ||
                    on_tooltip(banner)
                end
                  end
                end
                item.signal_connect('draw') do |i, *a|
              set_stylecontext(i, *a)
            end
                menu.add(item)
                item.show()
              end
              menuitem = @ui_manager.get_widget(['/popup/', 'Portal'].join(''))
              menuitem.set_submenu(menu)
              menu.signal_connect('realize') do |i, *a|
            set_stylecontext(i, *a)
          end
              menu.show()
              __set_visible('Portal', 1)
            else
              __set_visible('Portal', 0)
            end
      end
    end

    def __set_recommend_menu(recommend)
      if recommend
        menu = Gtk::Menu.new()
        recommend_list = recommend.split(chr(2))
        for site in recommend_list
          entry = site.split(chr(1))
          if not entry
            continue
          end
          title = entry[0]
          if title == '-'
            item = Gtk::SeparatorMenuItem.new()
          else
            item = Gtk::MenuItem.new(title)
            if entry.length < 2
              item.set_sensitive(false)
            end
            if entry.length > 1
              url = entry[1]
            end
            if entry.length > 2
              base_path = @parent.handle_request('GET', 'get_prefix')
              filename = entry[2].lower()
              head, tail = os.path.splitext(filename)
              if not tail
                for ext in ['.png', '.jpg', '.gif']
                  filename = [filename, ext].join('')
                  banner = os.path.join(
                                        base_path, 'ghost/master/banner',
                                        os.fsencode(filename))
                  if not os.path.exists(banner)
                    banner = nil
                  else
                    break
                  end
                end
              else
                banner = os.path.join(
                                      base_path, 'ghost/master/banner',
                                      os.fsencode(filename))
                if not os.path.exists(banner)
                  banner = nil
                end
              end
            else
              banner = nil
            end
            if entry.length > 1
              item.signal_connect('activate') do |a, i|
                @parent.handle_request('NOTIFY', 'notify_site_selection', title, url)
              end
              item.set_has_tooltip(true)
              item.signal_connect('query-tooltip') do ||
                  on_tooltip(banner)
              end
            end
          end
          item.signal_connect('draw') do |i, *a|
            set_stylecontext(i, *a)
          end
          menu.add(item)
          item.show()
        end
        menuitem =  @ui_manager.get_widget(['/popup/', 'Recommend'].join(''))
        menuitem.set_submenu(menu)
        menu.signal_connect('realize') do |i, *a|
          set_stylecontext(i, *a)
        end
        menu.show()
        __set_visible('Recommend', 1)
      else
        __set_visible('Recommend', 0)
      end
    end

    def create_ghost_menuitem(name, icon, key, handler, thumbnail)
      if icon != nil
        pixbuf = ninix.pix.create_icon_pixbuf(icon)
        if pixbuf == nil
          item = Gtk::MenuItem.new(name)
        else
          image = Gtk::Image.new()
          image.set_from_pixbuf(pixbuf)
          image.show()
          item = Gtk::ImageMenuItem.new(name)
          item.set_image(image)
          item.set_always_show_image(true) # XXX
        end
      else
        item = Gtk::MenuItem.new(name)
      end
      item.set_name('popup menu item')
      item.show()
      item.signal_connect('activate') do |a, v|
        handler(key)
      end
      item.set_has_tooltip(true)
      item.signal_connect('query-tooltip') do ||
          on_tooltip(thumbnail)
      end
      item.signal_connect('draw') do |i, *a|
        set_stylecontext(i, *a)
      end
      return item
    end

    def set_stylecontext(item, *args)
      _, offset_y = item.translate_coordinates(item.parent, 0, 0)
      style_context = item.style_context
      provider = Gtk::CssProvider.new()
      provider.load(data: ["GtkMenu {\n",
                           @__imagepath['background'],
                           "background-repeat: repeat-y;\n",
                           "color: ",
                           "\#",
                           sprintf("%02x", @__fontcolor['normal'][0]),
                           sprintf("%02x", @__fontcolor['normal'][1]),
                           sprintf("%02x", @__fontcolor['normal'][2]),
                           ";\n",
                           ["background-position: ", @__align['background'], " ", (-offset_y).to_s, "px;\n"].join(''),
                           "}\n",
                           "\n",
                           "GtkMenu :insensitive {\n",
                           @__imagepath['background'],
                           "background-repeat: repeat-y;\n",
                           ["background-position: ", @__align['background'], " ", (-offset_y).to_s, "px;\n"].join(''),
                           "}\n",
                           "\n",
                           "GtkMenu :prelight {\n",
                           @__imagepath['foreground'],
                           "background-repeat: repeat-y;\n",
                           "color: ",
                           "\#",
                           sprintf("%02x", @__fontcolor['prelight'][0]),
                           sprintf("%02x", @__fontcolor['prelight'][1]),
                           sprintf("%02x", @__fontcolor['prelight'][2]),
                           ";\n",
                           ["background-position: ", @__align['foreground'], " ", (-offset_y).to_s, "px;\n"].join(''),
                           "}"
                          ].join(""))
      style_context.add_provider(provider, 800) # STYLE_PROVIDER_PRIORITY_USER
    end

    def set_stylecontext_with_sidebar(item, *args)
      if @__imagepath['background_with_sidebar'] == nil or \
        @__imagepath['foreground_with_sidebar'] == nil or \
        @sidebar_width <= 0
        set_stylecontext(item, *args)
        return
      end
      _, offset_y = item.translate_coordinates(item.parent, 0, 0)
      style_context = item.style_context
      provider = Gtk::CssProvider.new()
      provider.load(data: ["GtkMenu {\n",
                           @__imagepath['background_with_sidebar'],
                           "background-repeat: repeat-y;\n",
                           "color: ",
                           "\#",
                           sprintf("%02x", @__fontcolor['normal'][0]),
                           sprintf("%02x", @__fontcolor['normal'][1]),
                           sprintf("%02x", @__fontcolor['normal'][2]),
                           ";\n",
                           ["background-position: ", "0px ", (-offset_y).to_s, "px", ", ",
                            @sidebar_width.to_s, "px", " ", (-offset_y).to_s, "px;\n"].join(''),
                           ["padding-left: ", @sidebar_width.to_s, "px;\n"].join(''),
                           "}\n",
                           "\n",
                           "GtkMenu :insensitive {\n",
                           @__imagepath['background_with_sidebar'],
                           "background-repeat: repeat-y;\n",
                           ["background-position: ", "0px ", (-offset_y).to_s, "px", ", ",
                            @sidebar_width.to_s, "px", " ", (-offset_y).to_s, "px;\n"].join(''),
                           ["padding-left: ", @sidebar_width.to_s, "px;\n"].join(''),
                           "}\n",
                           "\n",
                           "GtkMenu :prelight {\n",
                           @__imagepath['foreground_with_sidebar'],
                           "background-repeat: repeat-y;\n",
                           "color: ",
                           "\#",
                           sprintf("%02x", @__fontcolor['prelight'][0]),
                           sprintf("%02x", @__fontcolor['prelight'][1]),
                           sprintf("%02x", @__fontcolor['prelight'][2]),
                           ";\n",
                           ["background-position: ", "0px ", (-offset_y).to_s, "px", ", ",
                            @sidebar_width.to_s, "px", " ", (-offset_y).to_s, "px;\n"].join(''),
                           ["padding-left: ", @sidebar_width.to_s, "px;\n"].join(''),
                           "}"
                          ].join(''))
      style_context.add_provider(provider, 800) # STYLE_PROVIDER_PRIORITY_USER
    end

    def on_tooltip(widget, x, y, keyboard_mode, tooltip, thumbnail)
      if thumbnail == nil
        return false
      end
      pixbuf = ninix.pix.create_pixbuf_from_file(thumbnail, is_pnr=false)
      tooltip.set_icon(pixbuf)
      return true
    end

    def __set_ghost_menu
      for path in ['Summon', 'Change']
        ghost_menu = Gtk::Menu.new()
        for items in @parent.handle_request('GET', 'get_ghost_menus')
          item = items[path]
          if item.get_parent()
            item.reparent(ghost_menu)
          else
            ghost_menu << item
          end
        end
        menuitem = @ui_manager.get_widget(['/popup/', path].join(''))
        menuitem.set_submenu(ghost_menu)
        ghost_menu.signal_connect('realize') do |i, *a|
            set_stylecontext(i, *a)
        end
      end
    end

    def __set_shell_menu
      shell_menu = @parent.handle_request('GET', 'get_shell_menu')
      menuitem = @ui_manager.get_widget(['/popup/', 'Shell'].join(''))
      menuitem.set_submenu(shell_menu)
    end

    def __set_balloon_menu
      balloon_menu = @parent.handle_request('GET', 'get_balloon_menu')
      menuitem = @ui_manager.get_widget(['/popup/', 'Balloon'].join(''))
      menuitem.set_submenu(balloon_menu)
    end

    def create_meme_menu(menuitem)
      menu = Gtk::Menu.new()
      for item in menuitem.values()
        if item.get_parent()
          item.reparent(menu)
        else
          menu << item
        end
      end
      menu.signal_connect('realize') do |i, *a|
        set_stylecontext(i, *a)
      end
      return menu
    end

    def create_meme_menuitem(name, value, handler, thumbnail)
      item = Gtk::MenuItem.new(name)
      item.set_name('popup menu item')
      item.show()
      item.signal_connect('activate') do |a, v|
        handler(value)
      end
      item.set_has_tooltip(true)
      item.signal_connect('query-tooltip') do ||
          on_tooltip(thumbnail)
      end
      item.signal_connect('draw') do |i, *a|
        set_stylecontext(i, *a)
      end
      return item
    end

    def __set_plugin_menu
      plugin_list = @parent.handle_request('GET', 'get_plugin_list')
      plugin_menu = Gtk::Menu.new()
      for i in 0..(plugin_list.length - 1)
        name = plugin_list[i]['name']
        item = Gtk::MenuItem.new(name)
        item.set_name('popup menu item')
        item.signal_connect('draw') do |i, *a|
            set_stylecontext(i, *a)
        end
        item.show()
        plugin_menu << item
        item_list = plugin_list[i]['items']
        if item_list.length <= 1
          label, value = item_list[0]
          item.signal_connect('activate') do |a, v|
            @parent.handle_request('NOTIFY', 'select_plugin', value)
          end
          item.signal_connect('draw') do |i, *a|
              set_stylecontext(i, *a)
          end
          ##if working:
          ##    item.set_sensitive(false)
        else
          submenu = Gtk::Menu.new()
          submenu.set_name('popup menu')
          item.set_submenu(submenu)
          for label, value in item_list
            item = Gtk::MenuItem.new(label)
            item.set_name('popup menu item')
            item.signal_connect('activate') do |a, v|
              @parent.handle_request('NOTIFY', 'select_plugin', value)
            end
            item.signal_connect('draw') do |i, *a|
                set_stylecontext(i, *a)
            end
            item.show()
            ##if working:
            ##    item.set_sensitive(false)
            submenu << item
          end
          submenu.signal_connect('realize') do |i, *a|
            set_stylecontext(i, *a)
          end
        end
      end
      menuitem = @ui_manager.get_widget(['/popup/', 'Plugin'].join(''))
      menuitem.set_submenu(plugin_menu)
      plugin_menu.signal_connect('realize') do |i, *a|
        set_stylecontext(i, *a)
      end
    end

    def __set_nekodorif_menu
      nekodorif_list = @parent.handle_request('GET', 'get_nekodorif_list')
      nekodorif_menu = Gtk::Menu.new()
      for i in 0..(nekodorif_list.length - 1)
        name = nekodorif_list[i]['name']
        item = Gtk::MenuItem.new(name)
        item.set_name('popup menu item')
        item.show()
        nekodorif_menu << item
        item.signal_connect('activate') do |a, n|
          @parent.handle_request('NOTIFY', 'select_nekodorif', nekodorif_list[i]['dir'])
        end
        item.signal_connect('draw') do |i, *a|
            set_stylecontext(i, *a)
        end
        ##if working:
        ##    item.set_sensitive(false)
      end
      menuitem = @ui_manager.get_widget(['/popup/', 'Nekodorif'].join(''))
      menuitem.set_submenu(nekodorif_menu)
      nekodorif_menu.signal_connect('realize') do |i, *a|
        set_stylecontext(i, *a)
      end
    end

    def __set_kinoko_menu
      kinoko_list = @parent.handle_request('GET', 'get_kinoko_list')
      kinoko_menu = Gtk::Menu.new()
      for i in 0..(kinoko_list.length - 1)
        name = kinoko_list[i]['title']
        item = Gtk::MenuItem.new(name)
        item.set_name('popup menu item')
        item.show()
        kinoko_menu << item
        item.signal_connect('activate') do |a, k|
          @parent.handle_request(
                                 'NOTIFY', 'select_kinoko', kinoko_list[i])
        end
        item.signal_connect('draw') do |i, *a|
            set_stylecontext(i, *a)
        end
        ##if working:
        ##    item.set_sensitive(false)
      end
      menuitem = @ui_manager.get_widget(['/popup/', 'Kinoko'].join(''))
      menuitem.set_submenu(kinoko_menu)
      kinoko_menu.signal_connect('realize') do |i, *a|
        set_stylecontext(i, *a)
      end
    end

    def get_stick
      item = @ui_manager.get_widget(['/popup/', 'Stick'].join(''))
      if item != nil and item.get_active()
        return 1 #true
      else
        return 0 #false
      end
    end
  end

  class TEST
    
    def initialize
      @test_menu = Menu.new()
      @test_menu.set_responsible(self)
      @test_menu.create_mayuna_menu([]) # XXX
      @test_menu.set_pixmap(nil, nil, nil, "left", "left", "left") # XXX
      @window = Pix::TransparentWindow.new()
      @image_surface = Pix.create_surface_from_file('test1.png')
      @window.signal_connect('delete_event') do |w, e|
        # delete(w, e)
        Gtk.main_quit
      end
      @darea = @window.darea # @window.get_child()
      @darea.set_events(Gdk::Event::EXPOSURE_MASK|
                        Gdk::Event::BUTTON_PRESS_MASK|
                        Gdk::Event::BUTTON_RELEASE_MASK|
                        Gdk::Event::POINTER_MOTION_MASK|
                        Gdk::Event::POINTER_MOTION_HINT_MASK|
                        Gdk::Event::LEAVE_NOTIFY_MASK)
      @darea.signal_connect('button_press_event') do |w, e|
        button_press(w, e)
      end
      @darea.signal_connect('draw') do |w, cr|
        redraw(w, cr)
      end
      @window.set_default_size(@image_surface.width, @image_surface.height)
      @window.show_all()
      Gtk.main
    end

    def redraw(widget, cr)
      #scale = @__scale
      scale = 100.0
      cr.scale(scale / 100.0, scale / 100.0)
      cr.set_source(@image_surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint()
    end

    def button_press(widget, event)
      if event.button == 1
        if event.event_type == Gdk::Event::BUTTON_PRESS
          @test_menu.popup(event.button, 0)
        end
      elsif event.button == 3
        if event.event_type == Gdk::Event::BUTTON_PRESS
          @test_menu.popup(event.button, 1)
        end
      end
      return true
    end

    def handle_request(type, event, *a) # dummy
      if event == 'get_ghost_menus'
        return []
      end
      if event == 'get_plugin_list'
        return []
      end
      if event == 'get_nekodorif_list'
        return []
      end
      if event == 'get_kinoko_list'
        return []
      end
    end
  end
end

Menu::TEST.new