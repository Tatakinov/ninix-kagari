# -*- coding: utf-8 -*-
#
#  Copyright (C) 2003-2019 by Shyouzou Sugitani <shy@users.osdn.me>
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
require "gtk4"

require_relative "pix"

module Menu

  class Menu
    include GetText

    bindtextdomain("ninix-kagari")

    def initialize(parent, window)
      set_responsible(parent)
      @__fontcolor = {
        'normal' => [],
        'hover' => []
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
      model = Gio::Menu.new
      @__popup_menu = Gtk::PopoverMenu.new(model)
      window.set_child(@__popup_menu)
      item = Gio::Menu.new
      model.append_submenu(_('Recommend sites(_R)'), item)
      @__menu_list['Recommend'] = {:entry => item, :visible => true}
      item = Gio::Menu.new
      model.append_submenu(_('Portal sites(_P)'), item)
      @__menu_list['Portal'] = {:entry => item, :visible => true}
=begin FIXME separate
      #item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
=end
      model.append(_('Stick(_Y)'), 'win.stick')
      action = Gio::SimpleAction.new('stick')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:NOTIFY, :stick_window)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Stick'] = {:entry => item, :visible => true}
=begin FIXME separate
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
=end
      item = Gio::Menu.new
      model.append_submenu(_('Options(_F)'), item)
      @__menu_list['Options'] = {:entry => item, :visible => true}
      item.append(_('Network Update(_U)'), 'win.update')
      action = Gio::SimpleAction.new('update')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:NOTIFY, :network_update)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Options/Update'] = {:entry => item, :visible => true}
      item.append(_('Vanish(_F)'), 'win.vanish')
      action = Gio::SimpleAction.new('vanish')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :vanish)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Options/Vanish'] = {:entry => item, :visible => true}
      item.append(_('Preferences...(_O)'), 'win.edit_preference')
      action = Gio::SimpleAction.new('edit_preference')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :edit_preferences)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Options/Preferences'] = {:entry => item, :visible => true}
      item.append(_('Console(_C)'), 'win.open_console')
      action = Gio::SimpleAction.new('open_console')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :open_console)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Options/Console'] = {:entry => item, :visible => true}
      item.append(_('Ghost Manager(_M)'), 'win.ghost_manager')
      action = Gio::SimpleAction.new('ghost_manager')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :open_ghost_manager)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Options/Manager'] = {:entry => item, :visible => true}
      item.append(_('Script Log(_L)'), 'win.script_log')
      action = Gio::SimpleAction.new('script_log')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :open_script_log)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Options/ScriptLog'] = {entry: item, visible: true}
      item.append(_('Input Script(_L)'), 'win.scriptinputbox')
      action = Gio::SimpleAction.new('scriptinputbox')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :open_scriptinputbox)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Options/ScriptLog'] = {entry: item, visible: true}
=begin FIXME alternative
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
=end
      item = Gio::Menu.new
      model.append_submenu(_('Change(_G)'), item)
      @__menu_list['Change'] = {:entry => item, :visible => true}
      item = Gio::Menu.new
      model.append_submenu(_('Summon(_X)'), item)
      @__menu_list['Summon'] = {:entry => item, :visible => true}
      item = Gio::Menu.new
      model.append_submenu(_('Shell(_S)'), item)
      @__menu_list['Shell'] = {:entry => item, :visible => true}
      item = Gio::Menu.new
      model.append_submenu(_('Costume(_C)'), item)
      @__menu_list['Costume'] = {:entry => item, :visible => true}
      item = Gio::Menu.new
      model.append_submenu(_('Balloon(_B)'), item)
      @__menu_list['Balloon'] = {:entry => item, :visible => true}
=begin FIXME alternative
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
=end
      item = Gio::Menu.new
      model.append_submenu(_('Information(_I)'), item)
      @__menu_list['Information'] = {:entry => item, :visible => true}
      item.append(_('Usage graph(_A)'), 'win.usage')
      action = Gio::SimpleAction.new('usage')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :show_usage)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Information/Usage'] = {:entry => item, :visible => true}
      item.append(_('Version(_V)'), 'win.version')
      action = Gio::SimpleAction.new('version')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:GET, :about)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Information/Version'] = {:entry => item, :visible => true}
=begin FIXME alternative
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
=end
      item = Gio::Menu.new
      model.append_submenu(_('Nekodorif(_N)'), item)
      @__menu_list['Nekodorif'] = {:entry => item, :visible => true}
      item = Gio::Menu.new
      model.append_submenu(_('Kinoko(_K)'), item)
      @__menu_list['Kinoko'] = {:entry => item, :visible => true}
=begin FIXME alternative
      item = Gtk::SeparatorMenuItem.new()
      @__popup_menu.add(item)
=end
      model.append(_('Close(_W)'), 'win.close')
      action = Gio::SimpleAction.new('close')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:NOTIFY, :close_sakura)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Close'] = {:entry => item, :visible => true}
      model.append(_('Quit(_Q)'), 'win.quit')
      action = Gio::SimpleAction.new('quit')
      action.signal_connect('activate') do |a, param|
        @parent.handle_request(:NOTIFY, :close_all)
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
      # FIXME alternative
      #@__menu_list['Quit'] = {:entry => item, :visible => true}
      #@__popup_menu.show
      provider = create_css_provider_for(@__popup_menu)
=begin FIXME implement
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
=end
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
      if not path_background.nil? and File.exist?(path_background)
        begin
          color = Pix.get_png_lastpix(path_background)
          @__imagepath['background'] = ["background-image: url('",
                                        path_background, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if not path_sidebar.nil? and File.exist?(path_sidebar)
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
        @__imagepath['background'] = ""
=begin
        @__imagepath['background'] = ["background-image: none;\n",
                                      "background-color: transparent;\n"].join('')
=end
      end
      if not path_foreground.nil? and File.exist?(path_foreground)
        begin
          color = Pix.get_png_lastpix(path_foreground)
          @__imagepath['foreground'] = ["background-image: url('",
                                        path_foreground, "');\n",
                                        "background-color: ",
                                        color, ";\n"].join('')
          if not path_sidebar.nil? and File.exist?(path_sidebar)
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
        @__imagepath['foreground'] = ""
=begin
        @__imagepath['foreground'] = ["background-image: none;\n",
                                        "background-color: transparent;\n"].join('')
=end
      end
    end

    def __set_mayuna_menu(side)
      if @__mayuna_menu.length > side and not @__mayuna_menu[side].nil?
        menuitem = @__menu_list['Costume'][:entry]
        # FIXME conflict
        menuitem.append_submenu('Costume', @__mayuna_menu[side])
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
          @__mayuna_menu[index] = Gio::Menu.new
          mayuna_menu[side].length.times do |j|
            key, name, state = mayuna_menu[side][j]
            if key != '-'
              # FIXME conflict
              action = Gio::SimpleAction.new("toggle_bind#{j}")
              action.signal_connect('activate', [index, key]) do |a, param, ik|
                @parent.handle_request(:NOTIFY, :toggle_bind, ik, 'user')
              end
              @parent.handle_request(:NOTIFY, :add_action, action)
=begin TODO delete?
              provider = create_css_provider_for(item)
              item.signal_connect('draw', provider) do |i, *a, provider|
                next set_stylecontext(i, *a, :provider => provider)
              end
=end
            else
=begin FIXME alternative
              item = Gtk::SeparatorMenuItem.new()
=end
              item = nil
            end
            #item.show()
            #@__mayuna_menu[index] << item unless item.nil?
            @__mayuna_menu[index].append(name, "win.toggle_bind#{j}")
          end
=begin TODO delete?
          provider = create_css_provider_for(@__mayuna_menu[index])
          @__mayuna_menu[index].signal_connect('realize', provider) do |i, *a, provider|
            next set_stylecontext(i, *a, :provider => provider)
          end
=end
        end
      end
    end

    @@__re_shortcut = Regexp.new('&(?=[\x21-\x7e])')

    def __modify_shortcut(caption)
      caption.sub(@@__re_shortcut, '_')
      #@@__re_shortcut.sub('_', caption)
    end

    @@__re_mnemonic = Regexp.new('\(_.\)|_')

    def __cut_mnemonic(caption)
      caption.sub(@@__re_mnemonic, '')
      #@@__re_mnemonic.sub('', caption)
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
        #raise "assert" unless @__menu_list.include?(key)
        next unless @__menu_list.include?(key)
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
              caption = @parent.handle_request(:GET, :getstring, name)
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
            visible = @parent.handle_request(:GET, :getstring, name)
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

    def popup(side, x, y, upper)
      @__popup_menu.popdown
=begin TODO delete?
      @__popup_menu.unrealize()
      for key in @__menu_list.keys
        item = @__menu_list[key][:entry]
        submenu = item.submenu
        submenu.unrealize() unless submenu.nil?
      end
=end
      if side > 1
        string = 'char' + side.to_s
      else
        fail "assert" unless [0, 1].include?(side)
        string = ['sakura', 'kero'][side]
      end
      string = [string, '.popupmenu.visible'].join('')
      return if @parent.handle_request(:GET, :getstring, string) == '0'
      __update_ui(side)
      if side.zero?
        portal = @parent.handle_request(
          :GET, :getstring, 'sakura.portalsites')
      else
        portal = nil
      end
      # FIXME implement
      __set_portal_menu(side, portal)
      if side > 1
        string = 'char' + side.to_s
      else
        fail "assert" unless [0, 1].include?(side)
        string = ['sakura', 'kero'][side]
      end
      string = [string, '.recommendsites'].join('')
      recommend = @parent.handle_request(:GET, :getstring, string)
      __set_recommend_menu(recommend)
      __set_ghost_menu()
      __set_shell_menu()
      __set_balloon_menu()
      __set_mayuna_menu(side)
      __set_nekodorif_menu()
      __set_kinoko_menu()
=begin FIXME alternative
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
=end
      @__popup_menu.set_pointing_to(Gdk::Rectangle.new(x, y, 1, 1))
=begin
      if upper
        @__popup_menu.set_position(Gtk::PositionType::BOTTOM)
      else
        @__popup_menu.set_position(Gtk::PositionType::TOP)
      end
=end
      @__popup_menu.popup
    end

    def __set_caption(name, caption)
      fail "assert" unless @__menu_list.include?(name)
      fail "assert" unless caption.is_a?(String)
      item = @__menu_list[name][:entry]
      unless item.nil?
        label = item.children[0]
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
          menu = @__menu_list['Portal'][:entry]
          menu.remove_all
          portal_list = portal.split(2.chr, 0)
          portal_list.each_with_index do |site, i|
            entry = site.split(1.chr, 0)
            next if entry.empty?
            title = entry[0]
            if title == '-'
              #item = Gtk::SeparatorMenuItem.new()
              item = nil
            else
              item = Gio::SimpleAction.new("open_portal#{i}")
=begin FIXME implement
              if entry.length < 2
                item.set_sensitive(false)
              end
=end
              if entry.length > 1    
                url = entry[1]
              end
              if entry.length > 2
                base_path = @parent.handle_request(
                  :GET, :get_prefix)
                filename = entry[2].downcase
                tail = File.extname(filename)
                if tail.empty?
                  for ext in ['.png', '.jpg', '.gif']
                    filename = [filename, ext].join('')
                    banner = File.join(
                      base_path, 'ghost/master/banner', filename)
                    unless File.exist?(banner)
                      banner = nil
                    else
                      break
                    end
                  end
                else
                  banner = File.join(
                    base_path, 'ghost/master/banner', filename)
                  unless File.exist?(banner)
                    banner = nil
                  end
                end
              else
                banner = nil
              end
              if entry.length > 1    
                item.signal_connect('activate', title, url) do |a, param, title, url|
                  @parent.handle_request(
                    :GET, :notify_site_selection, title, url)
                  next true
                end
=begin FIXME implement
                unless banner.nil?
                  item.set_has_tooltip(true)
                  pixbuf = Pix.create_pixbuf_from_file(banner)
                  item.signal_connect('query-tooltip') do |widget, x, y, keyboard_mode, tooltip|
                    next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
                  end
                else
                  item.set_has_tooltip(false)
                end
=end
                @parent.handle_request(:NOTIFY, :add_action, item)
                menu.append(title, "win.open_portal#{i}")
              end
            end
=begin TODO delete?
            provider = create_css_provider_for(item)
            item.signal_connect('draw', provider) do |i, *a, provider|
              next set_stylecontext(i, *a, :provider => provider)
            end
            menu.add(item)
            #item.show()
=end
          end
=begin TODO elete?
          menuitem = @__menu_list['Portal'][:entry]
          menuitem.set_submenu(menu)
          provider = create_css_provider_for(menu)
          menu.signal_connect('realize', provider) do |i, *a, provider|
            next set_stylecontext(i, *a, :provider => provider)
          end
          #menu.show()
=end
          __set_visible('Portal', true)
        else
          __set_visible('Portal', false)
        end
      end
    end

    def __set_recommend_menu(recommend)
      unless recommend.nil? or recommend.empty?
        menu =  @__menu_list['Recommend'][:entry]
        menu.remove_all
        recommend_list = recommend.split(2.chr, 0)
        recommend_list.each_with_index do |site, i|
          entry = site.split(1.chr, 0)
          next if entry.empty?
          title = entry[0]
          if title == '-'
            #item = Gtk::SeparatorMenuItem.new()
            item = nil
          else
            item = Gio::SimpleAction.new("open_recommend#{i}")
            if entry.length < 2
              #item.set_sensitive(false)
            end
            if entry.length > 1
              url = entry[1]
            end
            if entry.length > 2
              base_path = @parent.handle_request(:GET, :get_prefix)
              filename = entry[2].downcase
              tail = File.extname(filename)
              if tail.empty?
                for ext in ['.png', '.jpg', '.gif']
                  filename = [filename, ext].join('')
                  banner = File.join(
                    base_path, 'ghost/master/banner', filename)
                  unless File.exist?(banner)
                    banner = nil
                  else
                    break
                  end
                end
              else
                banner = File.join(
                  base_path, 'ghost/master/banner', filename)
                unless File.exist?(banner)
                  banner = nil
                end
              end
            else
              banner = nil
            end
            if entry.length > 1
              item.signal_connect('activate', title, url) do |a, param, title, url|
                @parent.handle_request(:GET, :notify_site_selection, title, url)
                next true
              end
=begin FIXME implement
              unless banner.nil?
                item.set_has_tooltip(true)
                pixbuf = Pix.create_pixbuf_from_file(banner)
                item.signal_connect('query-tooltip') do |widget, x, y, keyboardmode, tooltip|
                  next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
                end
              else
                item.set_has_tooltip(false)
              end
=end
              menu.append(title, "win.open_recommend#{i}")
              @parent.handle_request(:GET, :add_action, item)
            end
          end
=begin FIXME implement
          provider = create_css_provider_for(item)
          item.signal_connect('draw', provider) do |i, *a, provider|
            next set_stylecontext(i, *a, :provider => provider)
          end
          menu.add(item)
          #item.show()
=end
        end
=begin TODO delete?
        menuitem =  @__menu_list['Recommend'][:entry]
        menuitem.set_submenu(menu)
=end
=begin FIXME implement
        provider = create_css_provider_for(menu)
        menu.signal_connect('realize', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        #menu.show()
=end
        #__set_visible('Recommend', true)
      else
        #__set_visible('Recommend', false)
      end
    end

    def create_ghost_menuitem(name, icon, key, handler, thumbnail, menu)
      item = Gio::MenuItem.new(name, "win.#{menu.downcase}#{key}")
      unless icon.nil?
        fileicon = Gio::FileIcon.new(Gio::File.new_for_path(icon))
        item.set_icon(fileicon)
      end
      action = Gio::SimpleAction.new("#{menu.downcase}#{key}")
      action.signal_connect('activate') do |a, v|
        handler.call(key)
        next true
      end
      @parent.handle_request(:NOTIFY, :add_action, action)
=begin TODO delete?
      unless thumbnail.nil?
        item.set_has_tooltip(true)
        pixbuf = Pix.create_pixbuf_from_file(thumbnail)
        item.signal_connect('query-tooltip') do |widget, x, y, keyboard_mode, tooltip|
          next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
        end
      else
        item.set_has_tooltip(false)
      end
=end
=begin TODO stub
      provider = create_css_provider_for(item)
      item.signal_connect('draw', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
=end
      return item
    end

    def set_stylecontext(item, *args, provider: nil)
      _, offset_y = item.translate_coordinates(item.parent, 0, 0)
      color_normal = ""
      unless @__fontcolor['normal'].empty?
        color_normal = [
            "color: ",
            "\#",
            sprintf("%02x", @__fontcolor['normal'][0]),
            sprintf("%02x", @__fontcolor['normal'][1]),
            sprintf("%02x", @__fontcolor['normal'][2]),
            ";\n"
        ].join("")
      end
      color_hover = ""
      unless @__fontcolor['hover'].empty?
        color_hover = [
            "color: ",
            "\#",
            sprintf("%02x", @__fontcolor['hover'][0]),
            sprintf("%02x", @__fontcolor['hover'][1]),
            sprintf("%02x", @__fontcolor['hover'][2]),
            ";\n"
        ].join("")
      end
      provider.load(data: ["menu {\n",
                           @__imagepath['background'],
                           "background-repeat: repeat-y;\n",
                           color_normal,
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
                           color_hover,
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
      color_normal = ""
      unless @__fontcolor['normal'].empty?
        color_normal = [
            "color: ",
            "\#",
            sprintf("%02x", @__fontcolor['normal'][0]),
            sprintf("%02x", @__fontcolor['normal'][1]),
            sprintf("%02x", @__fontcolor['normal'][2]),
            ";\n"
        ].join("")
      end
      color_hover = ""
      unless @__fontcolor['hover'].empty?
        color_hover = [
            "color: ",
            "\#",
            sprintf("%02x", @__fontcolor['hover'][0]),
            sprintf("%02x", @__fontcolor['hover'][1]),
            sprintf("%02x", @__fontcolor['hover'][2]),
            ";\n"
        ].join("")
      end
      provider.load(data: ["menu {\n",
                           @__imagepath['background_with_sidebar'],
                           "background-repeat: repeat-y;\n",
                           color_normal,
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
                           color_hover,
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
        ghost_menu = @__menu_list[path][:entry]
        ghost_menu.remove_all
        @parent.handle_request(:GET, :get_ghost_menus).each_with_index do |items, i|
          item = items[path]
=begin FIXME implement
          unless item.parent.nil?
            item.reparent(ghost_menu)
          else
            ghost_menu << item
          end
=end
          ghost_menu.append_item(items[path])
        end
=begin TODO delete?
        menuitem = @__menu_list[path][:entry]
        menuitem.set_submenu(ghost_menu)
=end
=begin FIXME implement
        provider = create_css_provider_for(ghost_menu)
        ghost_menu.signal_connect('realize', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
=end
      end
    end

    def __set_shell_menu
=begin TODO delete?
      shell_menu = @parent.handle_request(:GET, :get_shell_menu)
      menuitem = @__menu_list['Shell'][:entry]
      menuitem.set_submenu(shell_menu)
=end
    end

    def __set_balloon_menu
=begin TODO delete?
      balloon_menu = @parent.handle_request(:GET, :get_balloon_menu)
      menuitem = @__menu_list['Balloon'][:entry]
      menuitem.set_submenu(balloon_menu)
=end
    end

    def create_meme_menu(menuitem, menu)
      menu = @__menu_list[menu][:entry]
      menu.remove_all
      for item in menuitem.values()
=begin TODO delete?
        unless item.parent.nil?
          item.reparent(menu)
        else
          menu.add_child(item, item.label)
        end
=end
        menu.append_item(item)
      end
=begin FIXME implement
      provider = create_css_provider_for(menu)
      menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
=end
      return menu
    end

    def create_meme_menuitem(name, value, handler, thumbnail, menu)
      #item = Gtk::ImageMenuItem.new(:label => name)
      item = Gio::MenuItem.new(name, "win.#{menu.downcase}#{value}")
      action = Gio::SimpleAction.new("#{menu.downcase}#{value}")
      action.signal_connect('activate') do |a, param|
        handler.call(value)
      end
      unless thumbnail.nil?
        fileicon = Gio::FileIcon.new(Gio::File.new_for_path(thumbnail))
        item.set_icon(fileicon)
=begin FIXME implement
        item.set_has_tooltip(true)
        pixbuf = Pix.create_pixbuf_from_file(thumbnail)
        item.signal_connect('query-tooltip') do |widget, x, y, keyboard_mode, tooltip|
          next on_tooltip(widget, x, y, keyboard_mode, tooltip, pixbuf)
        end
=end
      else
        #item.set_has_tooltip(false)
      end
=begin TODO stub
      provider = create_css_provider_for(item)
      item.signal_connect('draw', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
=end
      return item
    end

    def __set_nekodorif_menu
      nekodorif_list = @parent.handle_request(:GET, :get_nekodorif_list)
      nekodorif_menu = @__menu_list['Nekodorif'][:entry]
      nekodorif_menu.remove_all
      nekodorif_list.length.times do |i|
        name = nekodorif_list[i]['name']
        item = Gio::MenuItem(name, "win.nekodorif#{i}")
        nekodorif_menu.append_item(item)
        action = Gio::SimpleAction("nekodorif#{i}")
        action.signal_connect('activate', nekodorif_list[i]['dir']) do |a, dir|
          @parent.handle_request(:GET, :select_nekodorif, dir)
          next true
        end
        @parent.handle_request(:NOTIFY, :add_action, action)
=begin FIXME implement
        provider = create_css_provider_for(item)
        item.signal_connect('draw', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        ##if working
        ##  item.set_sensitive(false)
=end
      end
=begin FIXME implement
      provider = create_css_provider_for(nekodorif_menu)
      nekodorif_menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
=end
    end

    def __set_kinoko_menu
      kinoko_list = @parent.handle_request(:GET, :get_kinoko_list)
      kinoko_menu = @__menu_list['Kinoko'][:entry]
      kinoko_menu.remove_all
      kinoko_list.length.times do |i|
        name = kinoko_list[i]['title']
        item = Gio::MenuItem(name, "win.kinoko#{i}")
        kinoko_menu.append_item(item)
        action = Gio::SimpleAction("kinoko#{i}")
        action.signal_connect('activate', kinoko_list[i]) do |a, k|
          @parent.handle_request(:GET, :select_kinoko, k)
          next true
        end
        @parent.handle_request(:NOTIFY, :add_action, action)
=begin FIXME implement
        provider = create_css_provider_for(item)
        item.signal_connect('draw', provider) do |i, *a, provider|
          next set_stylecontext(i, *a, :provider => provider)
        end
        ##if working
        ##  item.set_sensitive(false)
=end
      end
=begin FIXME implement
      provider = create_css_provider_for(kinoko_menu)
      kinoko_menu.signal_connect('realize', provider) do |i, *a, provider|
        next set_stylecontext(i, *a, :provider => provider)
      end
=end
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
