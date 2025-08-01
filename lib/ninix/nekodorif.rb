# -*- coding: utf-8 -*-
#
#  Copyright (C) 2004-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

# TODO:
# - 「きのこ」へのステータス送信.
# - 「きのこ」の情報の参照.
# - SERIKO/1.2ベースのアニメーション
# - (スキン側の)katochan.txt
# - balloon.txt
# - surface[0/1/2]a.txt(@ゴースト)
# - 自爆イベント
# - headrect.txt : 頭の当たり判定領域データ
#   当たり領域のleft／top／right／bottomを半角カンマでセパレートして記述.
#   1行目がsurface0、2行目がsurface1の領域データ.
#   このファイルがない場合、領域は自動計算される.
# - speak.txt
# - katochan が無い場合の処理.(本体の方のpopup menuなども含めて)
# - 設定ダイアログ : [会話/反応]タブ -> [SEND SSTP/1.1] or [SHIORI]
# - 見切れ連続20[s]、もしくは画面内で静止20[s]でアニメーション記述ミスと見なし自動的に落ちる
# - 発言中にバルーンをダブルクリックで即閉じ
# - @ゴースト名は#nameと#forには使えない. もし書いても無視されすべて有効になる
# - 連続落し不可指定
#   チェックしておくと落下物を2個以上同時に落とせなくなる
# - スキンチェンジ時も起動時のトークを行う
# - ファイルセット設定機能
#   インストールされたスキン／落下物のうち使用するものだけを選択できる
# - ターゲットのアイコン化への対応
# - アイコン化されているときは自動落下しない
# - アイコン化されているときのDirectSSTP SEND/DROPリクエストはエラー(Invisible)
# - 落下物の透明化ON/OFF
# - 落下物が猫どりふ自身にも落ちてくる
#   不在時に1/2、ランダム/全員落し時に1/10の確率で自爆
# - 一定時間間隔で勝手に物を落とす
# - ターゲット指定落し、ランダム落し、全員落し
# - 出現即ヒットの場合への対応

# - 複数ゴーストでの当たり判定.
# - 透明ウィンドウ

require "gettext"
require "gtk3"

require_relative "pix"
require_relative "home"
require_relative "logging"

module Nekodorif

  class Menu
  include GetText

  bindtextdomain("ninix-kagari")

    def initialize(accelgroup)
      @parent = nil
      @__katochan_list = nil
      @__menu_list = {}
      @__popup_menu = Gtk::Menu.new
      item = Gtk::MenuItem.new(:label => _('Settings...(_O)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request(:GET, :edit_preferences)
      end
      @__popup_menu.add(item)
      @__menu_list['settings'] = item
      item = Gtk::MenuItem.new(:label => _('Katochan(_K)'), :use_underline => true)
      @__popup_menu.add(item)
      @__menu_list['katochan'] = item
      item = Gtk::MenuItem.new(:label => _('Exit(_Q)'), :use_underline => true)
      item.signal_connect('activate') do |a, b|
        @parent.handle_request(:GET, :close)
      end
      @__popup_menu.add(item)
      @__menu_list['exit'] = item
      @__popup_menu.show_all
    end

    def set_responsible(parent)
      @parent = parent
    end

    def popup()
      katochan_list = @parent.handle_request(:GET, :get_katochan_list)
      __set_katochan_menu(katochan_list)
      @__popup_menu.popup_at_pointer(nil)
    end

    def __set_katochan_menu(list)
      key = 'katochan'
      unless list.empty?
        menu = Gtk::Menu.new()
        for katochan in list
          item = Gtk::MenuItem.new(:label => katochan['name'])
          item.signal_connect('activate', katochan) do |a, k|
            @parent.handle_request(:GET, :select_katochan, k)
            next true
          end
          menu.add(item)
          item.show()
        end
        @__menu_list[key].set_submenu(menu)
        menu.show()
        @__menu_list[key].show()
      else
        @__menu_list[key].hide()
      end
    end
  end

  class Nekoninni

    def initialize
      @mode = 1 # 0: SEND SSTP1.1, 1: SHIORI/2.2
      @__running = false
      @skin = nil
      @katochan = nil
    end

    def observer_update(event, args)
      if ['set position', 'set surface'].include?(event)
        @skin.set_position() unless @skin.nil?
        if not @katochan.nil? and @katochan.loaded
          @katochan.set_position()
        end
      elsif event == 'set scale'
        scale = @target.get_surface_scale()
        @skin.set_scale(scale) unless @skin.nil?
        @katochan.set_scale(scale) unless @katochan.nil?
      elsif event == 'finalize'
        finalize()
      else
        Logging::Logging.debug("OBSERVER(nekodorif): ignore - #{event}")
      end
    end

    def load(dir, katochan, target)
      return 0 if katochan.empty?
      @dir = dir
      @target = target
      @target.attach_observer(self)
      @accelgroup = Gtk::AccelGroup.new()
      scale = @target.get_surface_scale()
      @skin = Skin.new(@dir, @accelgroup, scale)
      @skin.set_responsible(self)
      @skin.setup
      return 0 if @skin.nil?
      @katochan_list = katochan
      @katochan = nil
      launch_katochan(@katochan_list[0])
      @__running = true
      GLib::Timeout.add(50) { do_idle_tasks } # 50[ms]
      return 1
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless [:GET, :NOTIFY].include?(event_type)
      handlers = {
        :get_katochan_list =>  lambda { return @katochan_list },
        :get_mode =>  lambda { return @mode },
        :get_workarea => lambda { return @target.get_workarea },
      }
      if handlers.include?(event)
        result = handlers[event].call # no argument
      else
        if Nekoninni.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = nil # XXX
        end
      end
      return result if event_type == 'GET'
    end

    def do_idle_tasks
      return false unless @__running
      @skin.update()
      @katochan.update() unless @katochan.nil?
      #process_script()
      return true
    end

    def send_event(event)
      if not ['Emerge', # 可視領域内に出現
              'Hit',    # ヒット
              'Drop',   # 再落下開始
              'Vanish', # ヒットした落下物が可視領域内から消滅
              'Dodge'   # よけられてヒットしなかった落下物が可視領域内から消滅
             ].include?(event)
        return
      end
      args = [@katochan.get_name(),
              @katochan.get_ghost_name(),
              @katochan.get_category(),
              @katochan.get_kinoko_flag(),
              @katochan.get_target()]
      @target.notify_event('OnNekodorifObject' + event.to_s, *args)
    end

    def has_katochan
      unless @katochan.nil?
        return true
      else
        return false
      end
    end

    def select_katochan(args)
      launch_katochan(args)
    end

    def drop_katochan
      @katochan.drop()
    end

    def delete_katochan
      @katochan.destroy()
      @katochan = nil
      @skin.reset()
    end

    def launch_katochan(katochan)
      delete_katochan unless @katochan.nil?
      @katochan = Katochan.new(@target)
      @katochan.set_responsible(self)
      @katochan.load(katochan)
    end

    def edit_preferences
    end

    def finalize
      @__running = false
      @target.detach_observer(self)
      @katochan.destroy() unless @katochan.nil?
      @skin.destroy() unless @skin.nil?
      ##if self.balloon is not None:
      ##    self.balloon.destroy()
    end

    def close
      finalize()
    end
  end

  class Skin
    HANDLERS = {
    }

    def initialize(dir, accelgroup, scale)
      @dir = dir
      @accelgroup = accelgroup
      @parent = nil
      @dragged = false
      @x_root = nil
      @y_root = nil
      @__scale = scale
      @__menu = Menu.new(@accelgroup)
      @__menu.set_responsible(self)
      path = File.join(@dir, 'omni.txt')
      if File.file?(path) and File.size(path).zero?
        @omni = 1
      else
        @omni = 0
      end
      @window = Pix::TransparentWindow.new()
      name, top_dir = Home.read_profile_txt(dir) # XXX
      @window.set_title(name)
      @window.signal_connect('delete_event') do |w, e|
        delete(w, e)
        next true
      end
      @window.signal_connect('key_press_event') do |w, e|
        next key_press(w, e)
      end
      @window.add_accel_group(@accelgroup)
      @darea = @window.darea
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK|
                        Gdk::EventMask::BUTTON_PRESS_MASK|
                        Gdk::EventMask::BUTTON_RELEASE_MASK|
                        Gdk::EventMask::POINTER_MOTION_MASK|
                        Gdk::EventMask::POINTER_MOTION_HINT_MASK|
                        Gdk::EventMask::LEAVE_NOTIFY_MASK)
      @darea.signal_connect('draw') do |w, cr|
        redraw(w, cr)
        next true
      end
      @darea.signal_connect('button_press_event') do |w, e|
        next button_press(w, e)
      end
      @darea.signal_connect('button_release_event') do |w, e|
        next button_release(w, e)
      end
      @darea.signal_connect('motion_notify_event') do |w, e|
        next motion_notify(w, e)
      end
      @darea.signal_connect('leave_notify_event') do |w, e|
        leave_notify(w, e)
        next true
      end
      @id = [0, nil]
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless [:GET, :NOTIFY].include?(event_type)
      unless HANDLERS.include?(event)
        result = @parent.handle_request(event_type, event, *arglist)
      else
        if Skin.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = nil
        end
      end
      return result if event_type == 'GET'
    end

    def setup
      set_surface()
      set_position(:reset => 1)
      @window.show_all()
    end

    def set_scale(scale)
      @__scale = scale
      set_surface()
      set_position()
    end

    def redraw(widget, cr)
      @window.set_surface(cr, @image_surface, @__scale, @reshape)
      @window.set_shape(cr, @reshape)
      @reshape = false
    end

    def delete(widget, event)
      @parent.handle_request(:GET, :finalize)
    end

    def key_press(window, event)
      if event.state & (Gdk::ModifierType::CONTROL_MASK | Gdk::ModifierType::SHIFT_MASK)
        if event.keyval == Gdk::Keyval::KEY_F12
          Logging::Logging.info('reset skin position')
          set_position(:reset => 1)
        end
      end
      return true
    end

    def destroy
      @window.destroy()
    end

    def button_press(widget, event)
      if event.button == 1
        if event.event_type == Gdk::EventType::BUTTON_PRESS
          @x_root = event.x_root
          @y_root = event.y_root
        elsif event.event_type == Gdk::EventType::DOUBLE_BUTTON_PRESS # double click
          if @parent.handle_request(:GET, :has_katochan)
            start()
            @parent.handle_request(:GET, :drop_katochan)
          end
        end
      elsif event.button == 3
        if event.event_type == Gdk::EventType::BUTTON_PRESS
          @__menu.popup()
        end
      end
      return true
    end

    def set_surface
      unless @id[1].nil?
        path = File.join(@dir, 'surface' + @id[0].to_s + @id[1].to_s + '.png')
        unless File.exist?(path)
          @id[1] = nil
          set_surface()
          return
        end
      else
        path = File.join(@dir, 'surface' + @id[0].to_s + '.png')
      end
      begin
        new_surface = Pix.create_surface_from_file(path)
        w = [8, (new_surface.width * @__scale / 100).to_i].max
        h = [8, (new_surface.height * @__scale / 100).to_i].max
      rescue
        @parent.handle_request(:GET, :finalize)
        return
      end
      @w, @h = w, h
      @reshape = true
      @image_surface = new_surface
      @darea.queue_draw()
    end

    def set_position(reset: 0)
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea)
      unless reset.zero?
        @x = left
        @y = (top + scrn_h - @h)
      else
        @y = (top + scrn_h - @h) unless @omni.zero?
      end
      @window.move(@x, @y)
    end

    def move(x_delta, y_delta)
      @x = (@x + x_delta)
      @y = (@y + y_delta) unless @omni.zero?
      set_position()
    end

    def update
      unless @id[1].nil?
        @id[1] += 1
      else
        return unless Random.rand(0..99).zero? ## XXX
        @id[1] = 0
      end
      set_surface()
    end

    def start
      @id[0] = 1
      set_surface()
    end

    def reset
      @id[0] = 0
      set_surface()
    end

    def button_release(widget, event)
      if @dragged
        @dragged = false
        set_position()
      end
      @x_root = nil
      @y_root = nil
      return true
    end

    def motion_notify(widget, event)
      x, y, state = event.x, event.y, event.state
      if state & Gdk::ModifierType::BUTTON1_MASK
        unless @x_root.nil? or @y_root.nil?
          @dragged = true
          x_delta = (event.x_root - @x_root).to_i
          y_delta = (event.y_root - @y_root).to_i
          move(x_delta, y_delta)
          @x_root = event.x_root
          @y_root = event.y_root
        end
      end
      if event.is_hint == 1
        Gdk::Event.request_motions(event)
      end
      return true
    end

    def leave_notify(widget, event) ## FIXME
    end
  end

  class Balloon

    def initialize
    end

    def destroy ## FIXME
        #pass
    end
  end

  class Katochan
    attr_reader :loaded

    CATEGORY_LIST = ['pain',      # 痛い
                     'stab',      # 刺さる
                     'surprise',  # びっくり
                     'hate',      # 嫌い、気持ち悪い
                     'huge',      # 巨大
                     'love',      # 好き、うれしい
                     'elegant',   # 風流、優雅
                     'pretty',    # かわいい
                     'food',      # 食品
                     'reference', # 見る／読むもの
                     'other'      # 上記カテゴリに当てはまらないもの
                     ]

    def initialize(target)
      @side = 0
      @target = target
      @parent = nil
      @settings = {}
      @settings['state'] = 'before'
      @settings['fall.type'] = 'gravity'
      @settings['fall.speed'] = 1
      @settings['slide.type'] = 'none'
      @settings['slide.magnitude'] = 0
      @settings['slide.sinwave.degspeed'] = 30
      @settings['wave'] = nil
      @settings['wave.loop'] = 0
      @__scale = 100
      @loaded = false
    end

    def set_responsible(parent)
      @parent = parent
    end

    def get_name
      @data['name']
    end

    def get_category
      @data['category']
    end

    def get_kinoko_flag ## FIXME
      return 0 # 0/1 = きのこに当たっていない(ない場合を含む)／当たった
    end

    def get_target
      if @side.zero?
        return @target.get_selfname()
      else
        return @target.get_keroname()
      end
    end

    def get_ghost_name
      if @data.include?('for') # 落下物が主に対象としているゴーストの名前
        return @data['for']
      else
        return ''
      end
    end

    def destroy
      @window.destroy()
    end

    def delete(widget, event)
      destroy()
    end

    def redraw(widget, cr)
      @window.set_surface(cr, @image_surface, @__scale, @reshape)
      @window.set_shape(cr, @reshape)
      @reshape = false
    end

    def set_movement(timing)
      key = (timing + 'fall.type')
      if @data.include?(key) and \
        ['gravity', 'evenspeed', 'none'].include?(@data[key])
          @settings['fall.type'] = @data[key]
      else
        @settings['fall.type'] = 'gravity'
      end
      if @data.include?(timing + 'fall.speed')
        @settings['fall.speed'] = @data[timing + 'fall.speed']
      else
        @settings['fall.speed'] = 1
      end
      if @settings['fall.speed'] < 1
        @settings['fall.speed'] = 1
      end
      if @settings['fall.speed'] > 100
        @settings['fall.speed'] = 100
      end
      key = (timing + 'slide.type')
      if @data.include?(key) and \
        ['none', 'sinwave', 'leaf'].include?(@data[key])
        @settings['slide.type'] = @data[key]
      else
        @settings['slide.type'] = 'none'
      end
      if @data.include?(timing + 'slide.magnitude')
        @settings['slide.magnitude'] = @data[timing + 'slide.magnitude']
      else
        @settings['slide.magnitude'] = 0
      end
      if @data.include?(timing + 'slide.sinwave.degspeed')
        @settings['slide.sinwave.degspeed'] = @data[timing + 'slide.sinwave.degspeed']
        else
        @settings['slide.sinwave.degspeed'] = 30
      end
      if @data.include?(timing + 'wave')
        @settings['wave'] = @data[timing + 'wave']
      else
        @settings['wave'] = nil
      end
      if @data.include?(timing + 'wave.loop')
        if @data[timing + 'wave.loop'] == 'on'
          @settings['wave.loop'] = 1
        else
          @settings['wave.loop'] = 0
        end
      else
        @settings['wave.loop'] = 0
      end
    end

    def set_scale(scale)
      @__scale = scale
      set_surface()
      set_position()
    end

    def set_position
      return if @settings['state'] != 'before'
      target_x, target_y = @target.get_surface_position(@side)
      target_w, target_h = @target.get_surface_size(@side)
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea)
      @x = (target_x + target_w / 2 - @w / 2 + (@offset_x * @__scale / 100).to_i)
      @y = (top + (@offset_y * @__scale / 100).to_i)
      @window.move(@x, @y)
    end

    def set_surface
      path = File.join(@data['dir'], 'surface' + @id.to_s + '.png')
      begin
        new_surface = Pix.create_surface_from_file(path)
        w = [8, (new_surface.width * @__scale / 100).to_i].max
        h = [8, (new_surface.height * @__scale / 100).to_i].max
      rescue
        @parent.handle_request(:GET, :finalize)
        return
      end
      @w, @h = w, h
      @reshape = true
      @image_surface = new_surface
      @darea.queue_draw()
    end

    def load(data)
      @data = data
      @__scale = @target.get_surface_scale()
      set_state('before')
      if @data.include?('category')
        category = @data['category'].split(',', 0)
        unless category.empty?
          unless CATEGORY_LIST.include?(category[0])
            Logging::Logging.warning('WARNING: unknown major category - ' + category[0])
            ##@data['category'] = CATEGORY_LIST[-1]
          end
        else
          @data['category'] = CATEGORY_LIST[-1]
        end
      else
        @data['category'] = CATEGORY_LIST[-1]
      end
      if @data.include?('target')
        if @data['target'] == 'sakura'
          @side = 0
        elsif @data['target'] == 'kero'
          @side = 1
        else
          @side = 0 # XXX
        end
      else
        @side = 0 # XXX
      end
      if @parent.handle_request(:GET, :get_mode) == 1
        @parent.handle_request(:GET, :send_event, 'Emerge')
      else
        if @data.include?('before.script')
          #pass ## FIXME
        else
          #pass ## FIXME
        end
      end
      set_movement('before')
      if @data.include?('before.appear.direction')
        #pass ## FIXME
      else
        #pass ## FIXME
      end
      if @data.include?('before.appear.ofset.x')
        offset_x = @data['before.appear.ofset.x']
      else
        offset_x = 0
      end
      if offset_x < -32768
        offset_x = -32768
      end
      if offset_x > 32767
        offset_x = 32767
      end
      if @data.include?('before.appear.ofset.y')
        offset_y = @data['before.appear.ofset.y']
      else
        offset_y = 0
      end
      if offset_y < -32768
        offset_y = -32768
      end
      if offset_y > 32767
        offset_y = 32767
      end
      @offset_x = offset_x
      @offset_y = offset_y
      @window = Pix::TransparentWindow.new()
      @window.set_title(@data['name'])
      @window.set_skip_taskbar_hint(true) # XXX
      @window.signal_connect('delete_event') do |w, e|
        delete(w, e)
        next true
      end
      @darea = @window.darea
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK)
      @darea.signal_connect('draw') do |w, cr|
        redraw(w, cr)
        next true
      end
      @window.show()
      @id = 0
      set_surface()
      set_position()
      @loaded = true
    end

    def drop
      set_state('fall')
    end

    def set_state(state)
      @settings['state'] = state
      @time = 0
      @hit = 0
      @hit_stop = 0
    end

    def update_surface ## FIXME
      #pass
    end

    def update_position ## FIXME
      if @settings['slide.type'] == 'leaf'
        #pass
      else
        if @settings['fall.type'] == 'gravity'
          @y += (@settings['fall.speed'].to_i * \
          (@time / 20.0)**2)
        elsif @settings['fall.type'] == 'evenspeed'
          @y += @settings['fall.speed']
        else
          #pass
        end
        if @settings['slide.type'] == 'sinwave'
          #pass ## FIXME
        else
          #pass
        end
      end
      @window.move(@x, @y)
    end

    def check_collision ## FIXME: check self position
      for side in [0, 1]
        target_x, target_y = @target.get_surface_position(side)
        target_w, target_h = @target.get_surface_size(side)
        center_x = (@x + @w / 2)
        center_y = (@y + @h / 2)
        if target_x < center_x and center_x < (target_x + target_w) and \
          target_y < center_y and center_y < (target_y + target_h)
          @side = side
          return 1
        end
      end
      return 0
    end

    def check_mikire
      left, top, scrn_w, scrn_h = @parent.handle_request(:GET, :get_workarea)
      if (@x + @w - @w / 3) > (left + scrn_w) or \
        (@x + @w / 3) < left or \
        (@y + @h - @h / 3) > (top + scrn_h) or \
        (@y + @h / 3) < top
        return 1
      else
        return 0
      end
    end

    def update
      if @settings['state'] == 'fall'
        update_surface()
        update_position()
        unless check_collision().zero?
          set_state('hit')
          @hit = 1
          if @parent.handle_request(:GET, :get_mode) == 1
            @id = 1
            set_surface()
            @parent.handle_request(:GET, :send_event, 'Hit')
          else
            #pass ## FIXME
          end
        end
        set_state('dodge') unless check_mikire().zero?
      elsif @settings['state'] == 'hit'
        if @data.include?('hit.waittime')
          wait_time = @data['hit.waittime']
        else
          wait_time = 0
        end
        if @hit_stop >= wait_time
          set_state('after')
          set_movement('after')
          if @parent.handle_request(:GET, :get_mode) == 1
            @id = 2
            set_surface()
            @parent.handle_request(:GET, :send_event, 'Drop')
          else
            #pass ## FIXME
          end
        else
          @hit_stop += 1
          update_surface()
        end
      elsif @settings['state'] == 'after'
        update_surface()
        update_position()
        set_state('end') unless check_mikire().zero?
      elsif @settings['state'] == 'end'
        if @parent.handle_request(:GET, :get_mode) == 1
          @parent.handle_request(:GET, :send_event, 'Vanish')
        else
          #pass ## FIXME
        end
        @parent.handle_request(:GET, :delete_katochan)
        return false
      elsif @settings['state'] == 'dodge'
        if @parent.handle_request(:GET, :get_mode) == 1
          @parent.handle_request(:GET, :send_event, 'Dodge')
        else
          #pass ## FIXME
        end
        @parent.handle_request(:GET, :delete_katochan)
        return false
      else
        ## check collision and mikire
      end
      @time += 1
      return true
    end
  end
end
