# -*- coding: utf-8 -*-
#
#  Copyright (C) 2003-2017 by Shyouzou Sugitani <shy@users.osdn.me>
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
      @__menu_list = {}
      @__popup_menu = Gtk::Menu.new
      item = Gtk::MenuItem.new(:label => _('Recommend sites(_R)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Recommend'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Portal sites(_P)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Portal'] = {:entry => item, :visible => true}
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
      item = Gtk::CheckMenuItem.new(:label => _('Stick(_Y)'), :use_underline => true)
      item.set_active(false)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'stick_window')
      end
      @__popup_menu.add(item)
      @__menu_list['Stick'] = {:entry => item, :visible => true}
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
      item = Gtk::MenuItem.new(:label => _('Options(_F)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Options'] = {:entry => item, :visible => true}
      menu = Gtk::Menu.new()
      item.set_submenu(menu)

      item = Gtk::MenuItem.new(:label => _('Network Update(_U)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'network_update')
      end
      menu.add(item)
      @__menu_list['Options/Update'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Vanish(_F)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'vanish')
      end
      menu.add(item)
      @__menu_list['Options/Vanish'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Preferences...(_O)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'edit_preferences')
      end
      menu.add(item)
      @__menu_list['Options/Preferences'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Console(_C)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'open_console')
      end
      menu.add(item)
      @__menu_list['Options/Console'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Ghost Manager(_M)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'open_ghost_manager')
      end
      menu.add(item)
      @__menu_list['Options/Manager'] = {:entry => item, :visible => true}
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
      item = Gtk::MenuItem.new(:label => _('Change(_G)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Change'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Summon(_X)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Summon'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Shell(_S)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Shell'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Costume(_C)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Costume'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Balloon(_B)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Balloon'] = {:entry => item, :visible => true}
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
      item = Gtk::MenuItem.new(:label => _('Information(_I)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Information'] = {:entry => item, :visible => true}
      menu = Gtk::Menu.new()
      item.set_submenu(menu)
      item = Gtk::MenuItem.new(:label => _('Usage graph(_A)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'show_usage')
      end
      menu.add(item)
      @__menu_list['Information/Usage'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Version(_V)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'about')
      end
      menu.add(item)
      @__menu_list['Information/Version'] = {:entry => item, :visible => true}
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
      item = Gtk::MenuItem.new(:label => _('Nekodorif(_N)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Nekodorif'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Kinoko(_K)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['Kinoko'] = {:entry => item, :visible => true}
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
      item = Gtk::MenuItem.new(:label => _('Close(_W)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'close_sakura')
      end
      @__popup_menu.add(item)
      @__menu_list['Close'] = {:entry => item, :visible => true}
      item = Gtk::MenuItem.new(:label => _('Quit(_Q)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request('NOTIFY', 'close_all')
      end
      @__popup_menu.add(item)
      @__menu_list['Quit'] = {:entry => item, :visible => true}
      @__popup_menu.show_all
      provider = create_css_provider_for(@__popup_menu)
      @__popup_menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext_with_sidebar(i, *a, :provider => provider)
      end
      for key in @__menu_list.keys
        item = @__menu_list[key][:entry]
        provider = create_css_provider_for(item)
        item.signal_connect('draw', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        submenu = item.submenu
        unless submenu.nil?
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
      style_context.add_provider(provider, Gtk::StyleProvider::PRIORITY_USER)
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
      if not path_background.nil? and File.exists?(path_background)
        begin
          color = Pix.get_png_lastpix(path_background)
          @__imagepath['background'] = ["background-image: url('",
                                        path_background, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if not path_sidebar.nil? and File.exists?(path_sidebar)
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
      if @__imagepath['background'].nil?
        @__imagepath['background'] = ["background-image: none;\n",
                                      "background-color: transparent;\n"].join('')
      end
      if not path_foreground.nil? and File.exists?(path_foreground)
        begin
          color = Pix.get_png_lastpix(path_foreground)
          @__imagepath['foreground'] = ["background-image: url('",
                                        path_foreground, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if not path_sidebar.nil? and File.exists?(path_sidebar)
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
      if @__imagepath['foreground'].nil?
        @__imagepath['foreground'] = ["background-image: none;\n",
                                        "background-color: transparent;\n"].join('')
      end
    end

    def __set_mayuna_menu(side)
      if @__mayuna_menu.length > side and not @__mayuna_menu[side].nil?
        menuitem = @__menu_list['Costume'][:entry]
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
        unless mayuna_menu[side].nil?
          @__mayuna_menu[index] = Gtk::Menu.new()
          for j in 0..mayuna_menu[side].length-1
            key, name, state = mayuna_menu[side][j]
            if key != '-'
              item = Gtk::CheckMenuItem.new(:label => name)
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
      self.__re_shortcut.sub('_', caption)
    end

    __re_mnemonic = Regexp.new('\(_.\)|_')

    def __cut_mnemonic(caption)
      self.__re_mnemonic.sub('', caption)
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
          unless name_list.empty? # caption
            for name in name_list
              caption = @parent.handle_request('GET', 'getstring', name)
              break unless caption.nil? or caption.empty?
            end
            unless caption.nil? or caption.empty?
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
        if not name_list.nil? and not name_list.empty? # visible
          for name in name_list
            visible = @parent.handle_request('GET', 'getstring', name)
            break unless visible.nil? or visible.empty?
          end
          if visible == '0'
            __set_visible(key, false)
          else
            __set_visible(key, true)
          end
        elsif name_list.nil?
          __set_visible(key, false)
        end
      end
    end

    def popup(side)
      @__popup_menu.unrealize()
      for key in @__menu_list.keys
        item = @__menu_list[key][:entry]
        submenu = item.submenu
        submenu.unrealize() unless submenu.nil?
      end
      if side > 1
        string = 'char' + side.to_s
      else
        fail "assert" unless [0, 1].include?(side)
        string = ['sakura', 'kero'][side]
      end
      string = [string, '.popupmenu.visible'].join('')
      return if @parent.handle_request('GET', 'getstring', string) == '0'
      __update_ui(side)
      if side.zero?
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
        item = @__menu_list[key][:entry]
        visible = @__menu_list[key][:visible]
        unless item.nil?
          if visible
            item.show()
          else
            item.hide()
          end
        end
      end
      @__popup_menu.popup_at_pointer(nil)
    end

    def __set_caption(name, caption)
      fail "assert" unless @__menu_list.include?(name)
      fail "assert" unless caption.is_a?(String)
      item = @__menu_list[name][:entry]
      unless item.nil?
        label = item.get_children()[0]
        label.set_text_with_mnemonic(caption)
      end
    end

    def __set_visible(name, visible)
      fail "assert" unless @__menu_list.include?(name)
      fail "assert" unless [false, true].include?(visible)
      @__menu_list[name][:visible] = visible
    end

    def __set_portal_menu(side, portal)
      if side >= 1
        __set_visible('Portal', false)
      else
        unless portal.nil? or portal.empty?
          menu = Gtk::Menu.new()
          portal_list = portal.split(2.chr, 0)
          for site in portal_list
            entry = site.split(1.chr, 0)
            next if entry.empty?
            title = entry[0]
            if title == '-'
              item = Gtk::SeparatorMenuItem.new()
            else
              item = Gtk::MenuItem.new(:label => title)
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
                    unless File.exists?(banner)
                      banner = nil
                    else
                      break
                    end
                  end
                else
                  banner = File.join(
                    base_path, 'ghost/master/banner', filename)
                  unless File.exists?(banner)
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
                unless banner.nil?
                  item.set_has_tooltip(true)
                  pixbuf = Pix.create_pixbuf_from_file(banner)
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
          menuitem = @__menu_list['Portal'][:entry]
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
      unless recommend.nil? or recommend.empty?
        menu = Gtk::Menu.new()
        recommend_list = recommend.split(2.chr, 0)
        for site in recommend_list
          entry = site.split(1.chr, 0)
          next if entry.empty?
          title = entry[0]
          if title == '-'
            item = Gtk::SeparatorMenuItem.new()
          else
            item = Gtk::MenuItem.new(:label => title)
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
                  unless File.exists?(banner)
                    banner = nil
                  else
                    break
                  end
                end
              else
                banner = File.join(
                  base_path, 'ghost/master/banner', filename)
                unless File.exists?(banner)
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
              unless banner.nil?
                item.set_has_tooltip(true)
                pixbuf = Pix.create_pixbuf_from_file(banner)
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
        menuitem =  @__menu_list['Recommend'][:entry]
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
      item = Gtk::MenuItem.new()
      box = Gtk::Box.new(Gtk::Orientation::HORIZONTAL, 6)
      unless icon.nil?
        pixbuf = Pix.create_icon_pixbuf(icon)
        unless pixbuf.nil?
          image = Gtk::Image.new
          image.pixbuf = pixbuf
          image.show
          box.pack_start(image, :expand => false, :fill => false, :padding => 0)
        end
      end
      label = Gtk::Label.new(name)
      label.xalign = 0.0
      label.show
      box.pack_end(label, :expand => true, :fill => true, :padding => 0)
      box.show
      item.add(box)
      item.set_name('popup menu item')
      item.show()
      item.signal_connect('activate') do |a, v|
        handler.call(key)
        next true
      end
      unless thumbnail.nil?
        item.set_has_tooltip(true)
        pixbuf = Pix.create_pixbuf_from_file(thumbnail)
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
      if @__imagepath['background_with_sidebar'].nil? or \
        @__imagepath['foreground_with_sidebar'].nil? or \
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
      return false if pixbuf.nil?
      tooltip.set_icon(pixbuf)
      return true
    end

    def __set_ghost_menu
      for path in ['Summon', 'Change']
        ghost_menu = Gtk::Menu.new()
        for items in @parent.handle_request('GET', 'get_ghost_menus')
          item = items[path]
          unless item.parent.nil?
            item.reparent(ghost_menu)
          else
            ghost_menu << item
          end
        end
        menuitem = @__menu_list[path][:entry]
        menuitem.set_submenu(ghost_menu)
        provider = create_css_provider_for(ghost_menu)
        ghost_menu.signal_connect('realize', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
      end
    end

    def __set_shell_menu
      shell_menu = @parent.handle_request('GET', 'get_shell_menu')
      menuitem = @__menu_list['Shell'][:entry]
      menuitem.set_submenu(shell_menu)
    end

    def __set_balloon_menu
      balloon_menu = @parent.handle_request('GET', 'get_balloon_menu')
      menuitem = @__menu_list['Balloon'][:entry]
      menuitem.set_submenu(balloon_menu)
    end

    def create_meme_menu(menuitem)
      menu = Gtk::Menu.new()
      for item in menuitem.values()
        unless item.parent.nil?
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
      item = Gtk::MenuItem.new(:label => name)
      item.set_name('popup menu item')
      item.show()
      item.signal_connect('activate') do |a, v|
        handler.call(value)
        next true
      end
      unless thumbnail.nil?
        item.set_has_tooltip(true)
        pixbuf = Pix.create_pixbuf_from_file(thumbnail)
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
        item = Gtk::MenuItem.new(:label => name)
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
      menuitem = @__menu_list['Nekodorif'][:entry]
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
        item = Gtk::MenuItem.new(:label => name)
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
      menuitem = @__menu_list['Kinoko'][:entry]
      menuitem.set_submenu(kinoko_menu)
      provider = create_css_provider_for(kinoko_menu)
      kinoko_menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
    end

    def get_stick
      item = @__menu_list['Stick'][:entry]
      if not item.nil? and item.active?
        return true
      else
        return false
      end
    end
  end
end
