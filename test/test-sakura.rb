require "ninix/home"
require "ninix/sakura"

module NinixTest

  class SakuraTest

    def initialize
      @sakura = Sakura::Sakura.new
      @sakura.set_responsible(self)
      @ghosts = Home.search_ghosts(target=nil, check_shiori=false)
      key = @ghosts.keys.sample
      @baseinfo = @ghosts[key]
      @sakura.new_(*@baseinfo)
    end

    def update
      @sakura.__yen_0([])
      @sakura.__yen_s([@index])
      @sakura.__yen_1([])
      @sakura.__yen_s([10 + @index])
#      @sakura.set_surface_position(0, 300, 400)
#      @sakura.set_surface_position(1, 600, 500)
      print("POS0: ", @sakura.get_surface_position(0), "\n")
      print("POS1: ", @sakura.get_surface_position(1), "\n")
      @index = (@index + 1) % 10
      return true
    end      
    
    def do_tests
      @index = 0
      #INIT#OK#@sakura.initialize
      #INIT#OK#@sakura.set_responsible(parent)
      #INIT#OK#@sakura.new_(desc, shiori_dir, use_makoto, surface_set, prefix,
      ##@sakura.handle_request(event_type, event, *arglist, **argdict)
      #OK#@sakura.attach_observer(self)
      #OK#@sakura.notify_observer("OBSERVER TEST", args=nil)
      #OK#@sakura.detach_observer(self)
      #OK#@sakura.set_SSP_mode(true)
      #OK#@sakura.set_SSP_mode(false)
      #OK#@sakura.enter_temp_mode()
      #OK#@sakura.leave_temp_mode()
      surface_set = @baseinfo[3]
      key = surface_set.keys.sample
      name, surface_dir, desc, surface_alias, surface_info, tooltips, seriko_descript = surface_set[key]
      @sakura.set_surface(desc, surface_alias, surface_info, name, surface_dir, tooltips, seriko_descript)
      balloons = Home.search_balloons()
      key = balloons.keys.sample
#      print("BALLOON: ", key, " ", balloons[key], "\n")
      @sakura.set_balloon(*balloons[key])
      @sakura.set_surface_default
      @sakura.position_balloons()
#      @sakura.align_top(0)
      @sakura.align_bottom(0)
      @sakura.align_bottom(1)
      @sakura.align_current()
#      @sakura.__yen_0([])
#      @sakura.__yen_s([10])
      @sakura.stand_by(true)
      GLib::Timeout.add(3000) { update }
      Gtk.main
#      @sakura.raise_surface(0)
#      @sakura.raise_surface(1)
#      @sakura.lower_surface(1)
#      @sakura.lower_surface(0)
      #SHELL##@sakura.get_lock_repaint()
      #SHELL##@sakura.delete_shell(key)
      #SHELL##@sakura.notify_installedshellname()
#      @sakura.get_shell_menu()
#      @sakura.save_history()
#      @sakura.save_settings()
#      @sakura.load_history()
#      @sakura.load_settings()
#      @sakura.load_shiori()
#      @sakura.finalize()
#      @sakura.is_listening(key)
#      @sakura.on_audio_message(bus, message)
#      @sakura.update_balloon_offset(side, x_delta, y_delta)
#      @sakura.enqueue_script(event, script, sender, handle, host, show_sstp_marker, use_translator, db=nil, request_handler=nil)
#      @sakura.check_event_queue()
#      @sakura.enqueue_event(event, *arglist, **argdict) ## FIXME
#      @sakura.handle_event() ## FIXME
#      @sakura.is_running()
#      @sakura.is_paused()
#      @sakura.is_talking()
#      @sakura.busy(check_updateman=true)
#      @sakura.get_silent_time()
#      @sakura.keep_silence(quiet)
#      @sakura.get_idle_time()
#      @sakura.reset_idle_time()
#      @sakura.notify_preference_changed() ## FIXME
#      @sakura.set_balloon_position(side, base_x, base_y)
#      @sakura.set_balloon_direction(side, direction)
#      @sakura.get_balloon_size(side)
#      @sakura.get_balloon_windowposition(side)
#      @sakura.get_balloon_position(side)
#      @sakura.balloon_is_shown(side)
#      @sakura.surface_is_shown(side)
#      @sakura.is_URL(s)
#      @sakura.is_anchor(link_id)
#      @sakura.vanish()
#      @sakura.vanish_by_myself(next_ghost)
#      @sakura.get_ifghost()
#      @sakura.ifghost(ifghost)
#      @sakura.get_name(default=_('Sakura&Unyuu'))
#      @sakura.get_username()
#      @sakura.get_selfname(default=_('Sakura'))
#      @sakura.get_selfname2()
#      @sakura.get_keroname()
#      @sakura.get_friendname()
#      @sakura.getaistringrandom() # obsolete
#      @sakura.getdms()
#      @sakura.getword(word_type)
#      @sakura.getstring(name)
#      @sakura.translate(s)
#      @sakura.get_value(response) # FIXME: check return code
#      @sakura.get_event_response_with_communication(event, *arglist, **argdict)
#      @sakura.get_event_response(event, *arglist, **argdict)
#      @sakura.notify_start(init, vanished, ghost_changed, name, prev_name, prev_shell, path, last_script, abend=nil)
#      @sakura.notify_vanish_selected()
#      @sakura.notify_vanish_canceled()
#      @sakura.notify_iconified()
#      @sakura.notify_deiconified()
#      @sakura.notify_link_selection(link_id, text, number)
#      @sakura.notify_site_selection(args)
#      @sakura.notify_surface_click(button, click, side, x, y)
#      @sakura.notify_balloon_click(button, click, side)
#      @sakura.notify_surface_mouse_motion(side, x, y, part)
#      @sakura.notify_user_teach(word)
#      @sakura.notify_event(event, *arglist, **argdict)
#      @sakura.get_prefix()
#      @sakura.stick_window(flag)
#      @sakura.toggle_bind(args)
#      @sakura.get_menu_pixmap()
#      @sakura.get_menu_fontcolor()
#      @sakura.get_mayuna_menu()
#      @sakura.get_current_balloon_directory()
#      @sakura.get_current_shell()
#      @sakura.get_current_shell_name()
#      @sakura.get_default_shell()
#      @sakura.get_balloon_default_id()
#      @sakura.select_shell(shell_key)
#      @sakura.select_balloon(item, desc, balloon)
#      @sakura.surface_bootup(flag_break=false)
#      @sakura.get_uptime()
#      @sakura.hide_all()
#      @sakura.identify_window(win)
#      @sakura.set_surface_default(side=nil)
#      @sakura.get_surface_scale()
#      @sakura.get_surface_size(side)
#      @sakura.set_surface_id(side, id)
#      @sakura.get_surface_id(side)
#      @sakura.surface_is_shown(side)
#      @sakura.get_kinoko_position(baseposition)
#      @sakura.raise_all()
#      @sakura.lower_all()
#      @sakura.start(key, init, temp, vanished, ghost_changed, prev_self_name, prev_name, prev_shell, last_script, abend)
#      @sakura.restart()
#      @sakura.stop()
#      @sakura.process_script()
#      @sakura.do_idle_tasks()
#      @sakura.quit()
#      @sakura.start_script(script, origin=nil)
#      @sakura.__yen_e(args)
#      @sakura.__yen_0(args)
#      @sakura.__yen_1(args)
#      @sakura.__yen_p(args)
#      @sakura.__yen_4(args)
#      @sakura.__yen_5(args)
#      @sakura.__yen_s(args)
#      @sakura.__yen_b(args)
#      @sakura.__yen__b(args)
#      @sakura.__yen_n(args)
#      @sakura.__yen_c(args)
#      @sakura.__set_weight(value, unit)
#      @sakura.__yen_w(args)
#      @sakura.__yen__w(args)
#      @sakura.__yen_t(args)
#      @sakura.__yen__q(args)
#      @sakura.__yen__s(args)
#      @sakura.__yen__e(args)
#      @sakura.__yen_q(args)
#      @sakura.__yen_URL(args)
#      @sakura.__yen__a(args)
#      @sakura.__yen_x(args)
#      @sakura.__yen_a(args)
#      @sakura.__yen_i(args)
#      @sakura.__yen_j(args)
#      @sakura.__yen_minus(args)
#      @sakura.__yen_plus(args)
#      @sakura.__yen__plus(args)
#      @sakura.__yen_m(args)
#      @sakura.__yen_and(args)
#      @sakura.__yen__m(args)
#      @sakura.__yen__u(args)
#      @sakura.__yen__v(args)
#      @sakura.__yen_8(args)
#      @sakura.__yen__V(args)
#      @sakura.__yen_exclamation(args) ## FIXME
#      @sakura.__yen___c(args)
#      @sakura.__yen___t(args)
#      @sakura.__yen_v(args)
#      @sakura.__yen_f(args)
#      @sakura.interpret_script()
#      @sakura.reset_script(reset_all=0)
#      @sakura.set_synchronized_session(list=[], reset=0)
#      @sakura.expand_meta(text_node)
#      @sakura._send_sstp_handle(data)
#      @sakura.write_sstp_handle(data)
#      @sakura.close_sstp_handle()
#      @sakura.close(reason='user')
#      @sakura.about()
#      @sakura.__update()
#      @sakura.network_update()
    end

    def observer_update(*args)
#      print('OBSERVER:', args, "\n")
    end
    
    def handle_request(event_type, event, *arglist, **argdict)
      if event_type == "NOTIFY"
#        print("NOTIFY: ", event, "\n")
      elsif event_type == "GET"
#        print("GET: ", event, " ", arglist,  "\n")
        if event == "get_preference"
          if arglist[0] == "surface_scale"
            return 100
          elsif arglist[0] == "animation_quality"
            return 1
          end
        elsif event == "lock_repaint"
          return false
        end
        return "" # XXX
v      end
    end
  end
end

test = NinixTest::SakuraTest.new
test.do_tests
