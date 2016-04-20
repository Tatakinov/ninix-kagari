# -*- coding: utf-8 -*-
#
#  Copyright (C) 2003-2016 by Shyouzou Sugitani <shy@users.osdn.me>
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

require_relative "pix"

module Menu

  class Menu
    include GetText

    bindtextdomain("ninix-aya")

    def initialize
      @parent = nil
      ui_info = "
        <ui>
          <popup name='popup'>
            <menu action='Recommend'>
            </menu>
            <menu action='Portal'>
            </menu>
            <separator/>
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
                'visible' => true},
            'Recommend' => {
                'entry' => ['Recommend', nil, _('Recommend sites(_R)'), nil],
                'visible' => true},
            'Options' => {
                'entry' => ['Options', nil, _('Options(_F)'), nil],
                'visible' => true},
            'Options/Update' => {
                'entry' => ['Update', nil, _('Network Update(_U)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'network_update')}],
                'visible' => true},
            'Options/Vanish' => {
                'entry' => ['Vanish', nil, _('Vanish(_F)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'vanish')}],
                'visible' => true},
            'Options/Preferences' => {
                'entry' => ['Preferences', nil, _('Preferences...(_O)'), nil,
                           '', lambda {|a, b| @parent.handle_request('NOTIFY', 'edit_preferences')}],
                'visible' => true},
            'Options/Console' => {
                'entry' => ['Console', nil, _('Console(_C)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'open_console')}],
                'visible' => true},
            'Options/Manager' => {
                'entry' => ['Manager', nil, _('Ghost Manager(_M)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'open_ghost_manager')}],
                'visible' => true},
            'Information' => {
                'entry' => ['Information', nil, _('Information(_I)'), nil],
                'visible' => true},
            'Information/Usage' => {
                'entry' => ['Usage', nil, _('Usage graph(_A)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'show_usage')}],
                'visible' => true},
            'Information/Version' => {
                'entry' => ['Version', nil, _('Version(_V)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'about')}],
                'visible' => true},
            'Close' => {
                'entry' => ['Close', nil, _('Close(_W)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'close_sakura')}],
                'visible' => true},
            'Quit' => {
                'entry' => ['Quit', nil, _('Quit(_Q)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'close_all')}],
                'visible' => true},
            'Change' => {
                'entry' => ['Change', nil, _('Change(_G)'), nil],
                'visible' => true},
            'Summon' => {
                'entry' => ['Summon', nil, _('Summon(_X)'), nil],
                'visible' => true},
            'Shell' => {
                'entry' => ['Shell', nil, _('Shell(_S)'), nil],
                'visible' => true},
            'Balloon' => {
                'entry' => ['Balloon', nil, _('Balloon(_B)'), nil],
                'visible' => true},
            'Costume' => {
                'entry' => ['Costume', nil, _('Costume(_C)'), nil],
                'visible' => true},
            'Stick' => {
                'entry' => ['Stick', nil, _('Stick(_Y)'), nil,
                          '', lambda {|a, b| @parent.handle_request('NOTIFY', 'stick_window')},
                          false],
                'visible' => true},
            'Nekodorif' => {
                'entry' => ['Nekodorif', nil, _('Nekodorif(_N)'), nil],
                'visible' => true},
            'Kinoko' => {
                'entry' => ['Kinoko', nil, _('Kinoko(_K)'), nil],
                'visible' => true},
            }
      @__fontcolor = {
        'normal' => [0, 0, 0],
        'hover' => [255, 255, 255]
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
      provider = create_css_provider_for(@__popup_menu)
      @__popup_menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext_with_sidebar(i, *a, :provider => provider)
      end
      for key in @__menu_list.keys
        item = @ui_manager.get_widget(['/popup/', key].join(''))
        provider = create_css_provider_for(item)
        item.signal_connect('draw', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        submenu = item.submenu
        if submenu != nil
          provider = create_css_provider_for(submenu)
          submenu.signal_connect('realize', provider) do |i, *a, provider|
            next set_stylecontext(i, *a, :provider => provider)
          end
        end
      end
    end

    def create_css_provider_for(item)
      provider = Gtk::CssProvider.new()
      style_context = item.style_context
      style_context.add_provider(provider, 800) # XXX: 800 == Gtk::StyleProvider::PRIORITY_USER
      return provider
    end

    def set_responsible(parent)
      @parent = parent
    end

    def set_fontcolor(background, foreground)
      @__fontcolor['normal'] = background
      @__fontcolor['hover'] = foreground
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
      if path_background != nil and File.exists?(path_background)
        begin
          color = Pix.get_png_lastpix(path_background)
          @__imagepath['background'] = ["background-image: url('",
                                        path_background, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if path_sidebar != nil and File.exists?(path_sidebar)
              sidebar_width, sidebar_height = Pix.get_png_size(path_sidebar)
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
        rescue
          # pass
        end
      end
      if @__imagepath['background'] == nil
        @__imagepath['background'] = ["background-image: none;\n",
                                      "background-color: transparent;\n"].join('')
      end
      if path_foreground != nil and File.exists?(path_foreground)
        begin
          color = Pix.get_png_lastpix(path_foreground)
          @__imagepath['foreground'] = ["background-image: url('",
                                        path_foreground, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if path_sidebar != nil and File.exists?(path_sidebar)
            sidebar_width, sidebar_height = Pix.get_png_size(path_sidebar)
            @__imagepath['foreground_with_sidebar'] = ["background-image: url('",
                                                       path_sidebar, "'),url('",
                                                       path_foreground, "');\n",
                                                       "background-repeat: no-repeat, repeat-x;\n",
                                                       "background-color: ", color, ";\n"].join('')
            @sidebar_width = sidebar_width
          else
            @sidebar_width = 0
          end
        rescue
          #pass
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
        __set_visible('Costume', true)
      else
        __set_visible('Costume', false)
      end
    end

    def create_mayuna_menu(mayuna_menu)
      @__mayuna_menu = []
      for side in mayuna_menu.keys
        if side == 'sakura'
          index = 0
        elsif side == 'kero'
          index = 1
        elsif side.start_with?('char')
          begin
            index = Integer(side[4, side.length])
          rescue
            next
          end
        else
          next
        end
        for _ in @__mayuna_menu.length..index 
          @__mayuna_menu << nil
        end
        if mayuna_menu[side] != nil
          @__mayuna_menu[index] = Gtk::Menu.new()
          item = Gtk::TearoffMenuItem.new()
          item.show()
          @__mayuna_menu[index] << item
          for j in 0..mayuna_menu[side].length-1
            key, name, state = mayuna_menu[side][j]
            if key != '-'
              item = Gtk::CheckMenuItem.new(name)
              item.set_name('popup menu item')
              item.set_active(state)
              item.signal_connect('activate', [index, key]) do |a, ik|
                @parent.handle_request('NOTIFY', 'toggle_bind', ik)
                next true
              end
              provider = create_css_provider_for(item)
              item.signal_connect('draw', provider) do |i, *a, provider|
                next set_stylecontext(i, *a, :provider => provider)
              end
            else
              item = Gtk::SeparatorMenuItem.new()
            end
            item.show()
            @__mayuna_menu[index] << item
          end
          provider = create_css_provider_for(@__mayuna_menu[index])
          @__mayuna_menu[index].signal_connect('realize', provider) do |i, *a, provider|
            next set_stylecontext(i, *a, :provider => provider)
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
        rasie "assert" unless @__menu_list.include?(key)
        if side > 1
          if ['Options/Update', 'Options/Vanish'].include?(key)
            name_list = @__ui[key][0][1] # same as 'kero'
          elsif key == 'Portal'
            name_list = [] # same as 'kero'
          elsif key == 'Recommend'
            name_list = ['char' + side.to_s + '.recommendbuttoncaption']
          else
            name_list = @__ui[key][0][side]
          end
          if not name_list.empty? # caption
            for name in name_list
              caption = @parent.handle_request('GET', 'getstring', name)
              if caption != nil and not caption.empty?
                break
              end
            end
            if caption != nil and not caption.empty?
              caption = __modify_shortcut(caption)
              if caption == __cut_mnemonic(caption)
                caption = [caption, @__ui[key][1]].join('')
              end
              __set_caption(key, caption)
            end
          end
        end
        if side > 1
          name_list = @__ui[key][2][1] # same as 'kero'
        else
          name_list = @__ui[key][2][side]
        end
        if name_list != nil and not name_list.empty? # visible
          for name in name_list
            visible = @parent.handle_request('GET', 'getstring', name)
            if visible != nil
              break
            end
          end
          if visible == '0'
            __set_visible(key, false)
          else
            __set_visible(key, true)
          end
        else
          __set_visible(key, false)
        end
      end
    end

    def popup(button, side)
      @__popup_menu.unrealize()
      for key in @__menu_list.keys
        item = @ui_manager.get_widget(['/popup/', key].join(''))
        submenu = item.submenu
        if submenu != nil
          submenu.unrealize()
        end
      end
      if side > 1
        string = 'char' + side.to_s
      else
        fail "assert" unless [0, 1].include?(side)
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
        string = 'char' + side.to_s
      else
        fail "assert" unless [0, 1].include?(side)
        string = ['sakura', 'kero'][side]
      end
      string = [string, '.recommendsites'].join('')
      recommend = @parent.handle_request('GET', 'getstring', string)
      __set_recommend_menu(recommend)
      __set_ghost_menu()
      __set_shell_menu()
      __set_balloon_menu()
      __set_mayuna_menu(side)
      __set_nekodorif_menu()
      __set_kinoko_menu()
      for key in @__menu_list.keys
        item = @ui_manager.get_widget(['/popup/', key].join(''))
        visible = @__menu_list[key]['visible']
        if item != nil
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
      fail "assert" unless @__menu_list.include?(name)
      fail "assert" unless caption.is_a?(String)
      item = @ui_manager.get_widget(['/popup/', name].join(''))
      if item != nil
        label = item.get_children()[0]
        label.set_text_with_mnemonic(caption)
      end
    end

    def __set_visible(name, visible)
      fail "assert" unless @__menu_list.include?(name)
      fail "assert" unless [false, true].include?(visible)
      @__menu_list[name]['visible'] = visible
    end

    def __set_portal_menu(side, portal)
      if side >= 1
        __set_visible('Portal', false)
      else
        if portal != nil and not portal.empty?
          menu = Gtk::Menu.new()
          portal_list = portal.split(2.chr, 0)
          for site in portal_list
            entry = site.split(1.chr, 0)
            if entry.empty?
              next
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
                filename = entry[2].downcase
                tail = File.extname(filename)
                if tail.empty?
                  for ext in ['.png', '.jpg', '.gif']
                    filename = [filename, ext].join('')
                    banner = File.join(
                      base_path, 'ghost/master/banner', filename)
                    if not File.exists?(banner)
                      banner = nil
                    else
                      break
                    end
                  end
                else
                  banner = File.join(
                    base_path, 'ghost/master/banner', filename)
                  if not File.exists?(banner)
                    banner = nil
                  end
                end
              else
                banner = nil
              end
              if entry.length > 1    
                item.signal_connect('activate', title, url) do |a, title, url|
                  @parent.handle_request(
                    'NOTIFY', 'notify_site_selection', title, url)
                  next true
                end
                if banner != nil
                  item.set_has_tooltip(true)
                  pixbuf = Pix.create_pixbuf_from_file(banner, :is_pnr => false)
                  item.signal_connect('query-tooltip') do |widget, x, y, keyboard_mode, tooltip|
                    next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
                  end
                else
                  item.set_has_tooltip(false)
                end
              end
            end
            provider = create_css_provider_for(item)
            item.signal_connect('draw', provider) do |i, *a, provider|
              next set_stylecontext(i, *a, :provider => provider)
            end
            menu.add(item)
            item.show()
          end
          menuitem = @ui_manager.get_widget(['/popup/', 'Portal'].join(''))
          menuitem.set_submenu(menu)
          provider = create_css_provider_for(menu)
          menu.signal_connect('realize', provider) do |i, *a, provider|
            next set_stylecontext(i, *a, :provider => provider)
          end
          menu.show()
          __set_visible('Portal', true)
        else
          __set_visible('Portal', false)
        end
      end
    end

    def __set_recommend_menu(recommend)
      if recommend != nil and not recommend.empty?
        menu = Gtk::Menu.new()
        recommend_list = recommend.split(2.chr, 0)
        for site in recommend_list
          entry = site.split(1.chr, 0)
          if entry.empty?
            next
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
              filename = entry[2].downcase
              tail = File.extname(filename)
              if tail.empty?
                for ext in ['.png', '.jpg', '.gif']
                  filename = [filename, ext].join('')
                  banner = File.join(
                    base_path, 'ghost/master/banner', filename)
                  if not File.exists?(banner)
                    banner = nil
                  else
                    break
                  end
                end
              else
                banner = File.join(
                  base_path, 'ghost/master/banner', filename)
                if not File.exists?(banner)
                  banner = nil
                end
              end
            else
              banner = nil
            end
            if entry.length > 1
              item.signal_connect('activate', title, url) do |a, title, url|
                @parent.handle_request('NOTIFY', 'notify_site_selection', title, url)
                next true
              end
              if banner != nil
                item.set_has_tooltip(true)
                pixbuf = Pix.create_pixbuf_from_file(banner, :is_pnr => false)
                item.signal_connect('query-tooltip') do |widget, x, y, keyboardmode, tooltip|
                  next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
                end
              else
                item.set_has_tooltip(false)
              end
            end
          end
          provider = create_css_provider_for(item)
          item.signal_connect('draw', provider) do |i, *a, provider|
            next set_stylecontext(i, *a, :provider => provider)
          end
          menu.add(item)
          item.show()
        end
        menuitem =  @ui_manager.get_widget(['/popup/', 'Recommend'].join(''))
        menuitem.set_submenu(menu)
        provider = create_css_provider_for(menu)
        menu.signal_connect('realize', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        menu.show()
        __set_visible('Recommend', true)
      else
        __set_visible('Recommend', false)
      end
    end

    def create_ghost_menuitem(name, icon, key, handler, thumbnail)
      if icon != nil
        pixbuf = Pix.create_icon_pixbuf(icon)
        if pixbuf == nil
          item = Gtk::MenuItem.new(name)
        else
          image = Gtk::Image.new
          image.pixbuf = pixbuf
          image.show
          item = Gtk::ImageMenuItem.new(:label => name)
          item.set_image(image)
          item.set_always_show_image(true) # XXX
        end
      else
        item = Gtk::MenuItem.new(name)
      end
      item.set_name('popup menu item')
      item.show()
      item.signal_connect('activate') do |a, v|
        handler.call(key)
        next true
      end
      if thumbnail != nil
        item.set_has_tooltip(true)
        pixbuf = Pix.create_pixbuf_from_file(thumbnail, :is_pnr => false)
        item.signal_connect('query-tooltip') do |widget, x, y, keyboard_mode, tooltip|
          next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
        end
      else
        item.set_has_tooltip(false)
      end
      provider = create_css_provider_for(item)
      item.signal_connect('draw', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
      return item
    end

    def set_stylecontext(item, *args, provider: nil)
      _, offset_y = item.translate_coordinates(item.parent, 0, 0)
      provider.load(data: ["menu {\n",
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
                           "menu :disabled {\n",
                           @__imagepath['background'],
                           "background-repeat: repeat-y;\n",
                           ["background-position: ", @__align['background'], " ", (-offset_y).to_s, "px;\n"].join(''),
                           "}\n",
                           "\n",
                           "menu :hover {\n",
                           @__imagepath['foreground'],
                           "background-repeat: repeat-y;\n",
                           "color: ",
                           "\#",
                           sprintf("%02x", @__fontcolor['hover'][0]),
                           sprintf("%02x", @__fontcolor['hover'][1]),
                           sprintf("%02x", @__fontcolor['hover'][2]),
                           ";\n",
                           ["background-position: ", @__align['foreground'], " ", (-offset_y).to_s, "px;\n"].join(''),
                           "}"
                          ].join(""))
      return false
    end

    def set_stylecontext_with_sidebar(item, *args, provider: nil)
      if @__imagepath['background_with_sidebar'] == nil or \
        @__imagepath['foreground_with_sidebar'] == nil or \
        @sidebar_width <= 0
        set_stylecontext(item, *args, :provider => provider)
        return false
      end
      _, offset_y = item.translate_coordinates(item.parent, 0, 0)
      provider.load(data: ["menu {\n",
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
                           "menu :disabled {\n",
                           @__imagepath['background_with_sidebar'],
                           "background-repeat: repeat-y;\n",
                           ["background-position: ", "0px ", (-offset_y).to_s, "px", ", ",
                            @sidebar_width.to_s, "px", " ", (-offset_y).to_s, "px;\n"].join(''),
                           ["padding-left: ", @sidebar_width.to_s, "px;\n"].join(''),
                           "}\n",
                           "\n",
                           "menu :hover {\n",
                           @__imagepath['foreground_with_sidebar'],
                           "background-repeat: repeat-y;\n",
                           "color: ",
                           "\#",
                           sprintf("%02x", @__fontcolor['hover'][0]),
                           sprintf("%02x", @__fontcolor['hover'][1]),
                           sprintf("%02x", @__fontcolor['hover'][2]),
                           ";\n",
                           ["background-position: ", "0px ", (-offset_y).to_s, "px", ", ",
                            @sidebar_width.to_s, "px", " ", (-offset_y).to_s, "px;\n"].join(''),
                           ["padding-left: ", @sidebar_width.to_s, "px;\n"].join(''),
                           "}"
                          ].join(''))
      return false
    end

    def on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
      if pixbuf == nil
        return false
      end
      tooltip.set_icon(pixbuf)
      return true
    end

    def __set_ghost_menu
      for path in ['Summon', 'Change']
        ghost_menu = Gtk::Menu.new()
        for items in @parent.handle_request('GET', 'get_ghost_menus')
          item = items[path]
          if item.parent != nil
            item.reparent(ghost_menu)
          else
            ghost_menu << item
          end
        end
        menuitem = @ui_manager.get_widget(['/popup/', path].join(''))
        menuitem.set_submenu(ghost_menu)
        provider = create_css_provider_for(ghost_menu)
        ghost_menu.signal_connect('realize', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
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
        if item.parent != nil
          item.reparent(menu)
        else
          menu << item
        end
      end
      provider = create_css_provider_for(menu)
      menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
      return menu
    end

    def create_meme_menuitem(name, value, handler, thumbnail)
      item = Gtk::MenuItem.new(name)
      item.set_name('popup menu item')
      item.show()
      item.signal_connect('activate') do |a, v|
        handler.call(value)
        next true
      end
      if thumbnail != nil
        item.set_has_tooltip(true)
        pixbuf = Pix.create_pixbuf_from_file(thumbnail, :is_pnr => false)
        item.signal_connect('query-tooltip') do |widget, x, y, keyboard_mode, tooltip|
          next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
        end
      else
        item.set_has_tooltip(false)
      end
      provider = create_css_provider_for(item)
      item.signal_connect('draw', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
      return item
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
        item.signal_connect('activate', nekodorif_list[i]['dir']) do |a, dir|
          @parent.handle_request('NOTIFY', 'select_nekodorif', dir)
          next true
        end
        provider = create_css_provider_for(item)
        item.signal_connect('draw', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        ##if working
        ##  item.set_sensitive(false)
      end
      menuitem = @ui_manager.get_widget(['/popup/', 'Nekodorif'].join(''))
      menuitem.set_submenu(nekodorif_menu)
      provider = create_css_provider_for(nekodorif_menu)
      nekodorif_menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
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
        item.signal_connect('activate', kinoko_list[i]) do |a, k|
          @parent.handle_request('NOTIFY', 'select_kinoko', k)
          next true
        end
        provider = create_css_provider_for(item)
        item.signal_connect('draw', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        ##if working
        ##  item.set_sensitive(false)
      end
      menuitem = @ui_manager.get_widget(['/popup/', 'Kinoko'].join(''))
      menuitem.set_submenu(kinoko_menu)
      provider = create_css_provider_for(kinoko_menu)
      kinoko_menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
    end

    def get_stick
      item = @ui_manager.get_widget(['/popup/', 'Stick'].join(''))
      if item != nil and item.active?
        return true
      else
        return false
      end
    end
  end
end
