# -*- coding: utf-8 -*-
#
#  Copyright (C) 2002 by Tamito KAJIYAMA
#  Copyright (C) 2003-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"

module Keymap

  Keymap_old = {
    Gdk::Keyval::GDK_KEY_BackSpace => 'back',
    Gdk::Keyval::GDK_KEY_Tab => 'tab',
    Gdk::Keyval::GDK_KEY_KP_Tab => 'tab',
    Gdk::Keyval::GDK_KEY_Clear => 'clear',
    Gdk::Keyval::GDK_KEY_Return => 'return',
    Gdk::Keyval::GDK_KEY_KP_Enter => 'return',
    Gdk::Keyval::GDK_KEY_Menu => '',
    Gdk::Keyval::GDK_KEY_Pause => 'pause',
    Gdk::Keyval::GDK_KEY_Kanji => '',
    Gdk::Keyval::GDK_KEY_Escape => 'escape',
    Gdk::Keyval::GDK_KEY_Henkan => '',
    Gdk::Keyval::GDK_KEY_Muhenkan => '',
    Gdk::Keyval::GDK_KEY_space => 'space',
    Gdk::Keyval::GDK_KEY_Prior => 'prior',
    Gdk::Keyval::GDK_KEY_Next => 'next',
    Gdk::Keyval::GDK_KEY_End => 'end',
    Gdk::Keyval::GDK_KEY_Home => 'home',
    Gdk::Keyval::GDK_KEY_Left => 'left',
    Gdk::Keyval::GDK_KEY_Up => 'up',
    Gdk::Keyval::GDK_KEY_Right => 'right',
    Gdk::Keyval::GDK_KEY_Down => 'down',
    Gdk::Keyval::GDK_KEY_Select => '',
    Gdk::Keyval::GDK_KEY_Print => '',
    Gdk::Keyval::GDK_KEY_Execute => '',
    Gdk::Keyval::GDK_KEY_Insert => '',
    Gdk::Keyval::GDK_KEY_Delete => 'delete',
    Gdk::Keyval::GDK_KEY_Help => '',
    Gdk::Keyval::GDK_KEY_0 => '0',
    Gdk::Keyval::GDK_KEY_1 => '1',
    Gdk::Keyval::GDK_KEY_2 => '2',
    Gdk::Keyval::GDK_KEY_3 => '3',
    Gdk::Keyval::GDK_KEY_4 => '4',
    Gdk::Keyval::GDK_KEY_5 => '5',
    Gdk::Keyval::GDK_KEY_6 => '6',
    Gdk::Keyval::GDK_KEY_7 => '7',
    Gdk::Keyval::GDK_KEY_8 => '8',
    Gdk::Keyval::GDK_KEY_9 => '9',
    Gdk::Keyval::GDK_KEY_a => 'a',
    Gdk::Keyval::GDK_KEY_b => 'b',
    Gdk::Keyval::GDK_KEY_c => 'c',
    Gdk::Keyval::GDK_KEY_d => 'd',
    Gdk::Keyval::GDK_KEY_e => 'e',
    Gdk::Keyval::GDK_KEY_f => 'f',
    Gdk::Keyval::GDK_KEY_g => 'g',
    Gdk::Keyval::GDK_KEY_h => 'h',
    Gdk::Keyval::GDK_KEY_i => 'i',
    Gdk::Keyval::GDK_KEY_j => 'j',
    Gdk::Keyval::GDK_KEY_k => 'k',
    Gdk::Keyval::GDK_KEY_l => 'l',
    Gdk::Keyval::GDK_KEY_m => 'm',
    Gdk::Keyval::GDK_KEY_n => 'n',
    Gdk::Keyval::GDK_KEY_o => 'o',
    Gdk::Keyval::GDK_KEY_p => 'p',
    Gdk::Keyval::GDK_KEY_q => 'q',
    Gdk::Keyval::GDK_KEY_r => 'r',
    Gdk::Keyval::GDK_KEY_s => 's',
    Gdk::Keyval::GDK_KEY_t => 't',
    Gdk::Keyval::GDK_KEY_u => 'u',
    Gdk::Keyval::GDK_KEY_v => 'v',
    Gdk::Keyval::GDK_KEY_w => 'w',
    Gdk::Keyval::GDK_KEY_x => 'x',
    Gdk::Keyval::GDK_KEY_y => 'y',
    Gdk::Keyval::GDK_KEY_z => 'z',
    Gdk::Keyval::GDK_KEY_KP_0 => '0',
    Gdk::Keyval::GDK_KEY_KP_1 => '1',
    Gdk::Keyval::GDK_KEY_KP_2 => '2',
    Gdk::Keyval::GDK_KEY_KP_3 => '3',
    Gdk::Keyval::GDK_KEY_KP_4 => '4',
    Gdk::Keyval::GDK_KEY_KP_5 => '5',
    Gdk::Keyval::GDK_KEY_KP_6 => '6',
    Gdk::Keyval::GDK_KEY_KP_7 => '7',
    Gdk::Keyval::GDK_KEY_KP_8 => '8',
    Gdk::Keyval::GDK_KEY_KP_9 => '9',
    Gdk::Keyval::GDK_KEY_KP_Multiply => '*',
    Gdk::Keyval::GDK_KEY_KP_Add => '+',
    Gdk::Keyval::GDK_KEY_KP_Separator => '',
    Gdk::Keyval::GDK_KEY_KP_Subtract => '-',
    Gdk::Keyval::GDK_KEY_KP_Decimal => '',
    Gdk::Keyval::GDK_KEY_KP_Divide => '/',
    Gdk::Keyval::GDK_KEY_F1 => 'f1',
    Gdk::Keyval::GDK_KEY_F2 => 'f2',
    Gdk::Keyval::GDK_KEY_F3 => 'f3',
    Gdk::Keyval::GDK_KEY_F4 => 'f4',
    Gdk::Keyval::GDK_KEY_F5 => 'f5',
    Gdk::Keyval::GDK_KEY_F6 => 'f6',
    Gdk::Keyval::GDK_KEY_F7 => 'f7',
    Gdk::Keyval::GDK_KEY_F8 => 'f8',
    Gdk::Keyval::GDK_KEY_F9 => 'f9',
    Gdk::Keyval::GDK_KEY_F10 => 'f10',
    Gdk::Keyval::GDK_KEY_F11 => 'f11',
    Gdk::Keyval::GDK_KEY_F12 => 'f12',
    Gdk::Keyval::GDK_KEY_F13 => 'f13',
    Gdk::Keyval::GDK_KEY_F14 => 'f14',
    Gdk::Keyval::GDK_KEY_F15 => 'f15',
    Gdk::Keyval::GDK_KEY_F16 => 'f16',
    Gdk::Keyval::GDK_KEY_F17 => 'f17',
    Gdk::Keyval::GDK_KEY_F18 => 'f18',
    Gdk::Keyval::GDK_KEY_F19 => 'f19',
    Gdk::Keyval::GDK_KEY_F20 => 'f20',
    Gdk::Keyval::GDK_KEY_F21 => 'f21',
    Gdk::Keyval::GDK_KEY_F22 => 'f22',
    Gdk::Keyval::GDK_KEY_F23 => 'f23',
    Gdk::Keyval::GDK_KEY_F24 => 'f24',
    Gdk::Keyval::GDK_KEY_Num_Lock => '',
    Gdk::Keyval::GDK_KEY_Scroll_Lock => '',
    Gdk::Keyval::GDK_KEY_Shift_L => '',
    Gdk::Keyval::GDK_KEY_Shift_R => '',
    Gdk::Keyval::GDK_KEY_Control_L => '',
    Gdk::Keyval::GDK_KEY_Control_R => '',
    }

  Keymap_new = {
    Gdk::Keyval::GDK_KEY_BackSpace => '8',
    Gdk::Keyval::GDK_KEY_Tab => '9',
    Gdk::Keyval::GDK_KEY_KP_Tab => '9',
    Gdk::Keyval::GDK_KEY_Clear => '12',
    Gdk::Keyval::GDK_KEY_Return => '13',
    Gdk::Keyval::GDK_KEY_KP_Enter => '13',
    Gdk::Keyval::GDK_KEY_Menu => '18',
    Gdk::Keyval::GDK_KEY_Pause => '19',
    Gdk::Keyval::GDK_KEY_Kanji => '25',
    Gdk::Keyval::GDK_KEY_Escape => '27',
    Gdk::Keyval::GDK_KEY_Henkan => '28',
    Gdk::Keyval::GDK_KEY_Muhenkan => '29',
    Gdk::Keyval::GDK_KEY_space => '32',
    Gdk::Keyval::GDK_KEY_Prior => '33',
    Gdk::Keyval::GDK_KEY_Next => '34',
    Gdk::Keyval::GDK_KEY_End => '35',
    Gdk::Keyval::GDK_KEY_Home => '36',
    Gdk::Keyval::GDK_KEY_Left => '37',
    Gdk::Keyval::GDK_KEY_Up => '38',
    Gdk::Keyval::GDK_KEY_Right => '39',
    Gdk::Keyval::GDK_KEY_Down => '40',
    Gdk::Keyval::GDK_KEY_Select => '41',
    Gdk::Keyval::GDK_KEY_Print => '42',
    Gdk::Keyval::GDK_KEY_Execute => '43',
    Gdk::Keyval::GDK_KEY_Insert => '45',
    Gdk::Keyval::GDK_KEY_Delete => '46',
    Gdk::Keyval::GDK_KEY_Help => '47',
    Gdk::Keyval::GDK_KEY_0 => '48',
    Gdk::Keyval::GDK_KEY_1 => '49',
    Gdk::Keyval::GDK_KEY_2 => '50',
    Gdk::Keyval::GDK_KEY_3 => '51',
    Gdk::Keyval::GDK_KEY_4 => '52',
    Gdk::Keyval::GDK_KEY_5 => '53',
    Gdk::Keyval::GDK_KEY_6 => '54',
    Gdk::Keyval::GDK_KEY_7 => '55',
    Gdk::Keyval::GDK_KEY_8 => '56',
    Gdk::Keyval::GDK_KEY_9 => '57',
    Gdk::Keyval::GDK_KEY_a => '65',
    Gdk::Keyval::GDK_KEY_b => '66',
    Gdk::Keyval::GDK_KEY_c => '67',
    Gdk::Keyval::GDK_KEY_d => '68',
    Gdk::Keyval::GDK_KEY_e => '69',
    Gdk::Keyval::GDK_KEY_f => '70',
    Gdk::Keyval::GDK_KEY_g => '71',
    Gdk::Keyval::GDK_KEY_h => '72',
    Gdk::Keyval::GDK_KEY_i => '73',
    Gdk::Keyval::GDK_KEY_j => '74',
    Gdk::Keyval::GDK_KEY_k => '75',
    Gdk::Keyval::GDK_KEY_l => '76',
    Gdk::Keyval::GDK_KEY_m => '77',
    Gdk::Keyval::GDK_KEY_n => '78',
    Gdk::Keyval::GDK_KEY_o => '79',
    Gdk::Keyval::GDK_KEY_p => '80',
    Gdk::Keyval::GDK_KEY_q => '81',
    Gdk::Keyval::GDK_KEY_r => '82',
    Gdk::Keyval::GDK_KEY_s => '83',
    Gdk::Keyval::GDK_KEY_t => '84',
    Gdk::Keyval::GDK_KEY_u => '85',
    Gdk::Keyval::GDK_KEY_v => '86',
    Gdk::Keyval::GDK_KEY_w => '87',
    Gdk::Keyval::GDK_KEY_x => '88',
    Gdk::Keyval::GDK_KEY_y => '89',
    Gdk::Keyval::GDK_KEY_z => '90',
    Gdk::Keyval::GDK_KEY_KP_0 => '96',
    Gdk::Keyval::GDK_KEY_KP_1 => '97',
    Gdk::Keyval::GDK_KEY_KP_2 => '98',
    Gdk::Keyval::GDK_KEY_KP_3 => '99',
    Gdk::Keyval::GDK_KEY_KP_4 => '100',
    Gdk::Keyval::GDK_KEY_KP_5 => '101',
    Gdk::Keyval::GDK_KEY_KP_6 => '102',
    Gdk::Keyval::GDK_KEY_KP_7 => '103',
    Gdk::Keyval::GDK_KEY_KP_8 => '104',
    Gdk::Keyval::GDK_KEY_KP_9 => '105',
    Gdk::Keyval::GDK_KEY_KP_Multiply => '106',
    Gdk::Keyval::GDK_KEY_KP_Add => '107',
    Gdk::Keyval::GDK_KEY_KP_Separator => '108',
    Gdk::Keyval::GDK_KEY_KP_Subtract => '109',
    Gdk::Keyval::GDK_KEY_KP_Decimal => '110',
    Gdk::Keyval::GDK_KEY_KP_Divide => '111',
    Gdk::Keyval::GDK_KEY_F1 => '112',
    Gdk::Keyval::GDK_KEY_F2 => '113',
    Gdk::Keyval::GDK_KEY_F3 => '114',
    Gdk::Keyval::GDK_KEY_F4 => '115',
    Gdk::Keyval::GDK_KEY_F5 => '116',
    Gdk::Keyval::GDK_KEY_F6 => '117',
    Gdk::Keyval::GDK_KEY_F7 => '118',
    Gdk::Keyval::GDK_KEY_F8 => '119',
    Gdk::Keyval::GDK_KEY_F9 => '120',
    Gdk::Keyval::GDK_KEY_F10 => '121',
    Gdk::Keyval::GDK_KEY_F11 => '122',
    Gdk::Keyval::GDK_KEY_F12 => '123',
    Gdk::Keyval::GDK_KEY_F13 => '124',
    Gdk::Keyval::GDK_KEY_F14 => '125',
    Gdk::Keyval::GDK_KEY_F15 => '126',
    Gdk::Keyval::GDK_KEY_F16 => '127',
    Gdk::Keyval::GDK_KEY_F17 => '128',
    Gdk::Keyval::GDK_KEY_F18 => '129',
    Gdk::Keyval::GDK_KEY_F19 => '130',
    Gdk::Keyval::GDK_KEY_F20 => '131',
    Gdk::Keyval::GDK_KEY_F21 => '132',
    Gdk::Keyval::GDK_KEY_F22 => '133',
    Gdk::Keyval::GDK_KEY_F23 => '134',
    Gdk::Keyval::GDK_KEY_F24 => '135',
    Gdk::Keyval::GDK_KEY_Num_Lock => '144',
    Gdk::Keyval::GDK_KEY_Scroll_Lock => '145',
    Gdk::Keyval::GDK_KEY_Shift_L => '160',
    Gdk::Keyval::GDK_KEY_Shift_R => '161',
    Gdk::Keyval::GDK_KEY_Control_L => '162',
    Gdk::Keyval::GDK_KEY_Control_R => '163',
    }

  class Test

    def key_press(widget, event)
      begin
        print(Keymap_old[event.keyval], " ",
              Keymap_new[event.keyval], " ",
              event.keyval, "\n")
      rescue # except KeyError:
        print('unknown keyval: ', event.keyval,
              "(", Gdk::Keyval.to_name(event.keyval), ")\n")
      end
    end

    def initialize
      @win = Gtk::Window.new
      @win.set_events(Gdk::Event::KEY_PRESS_MASK)
      @win.signal_connect('destroy') do
        Gtk.main_quit
      end
      @win.signal_connect('key_press_event') do |w, e|
        key_press(w, e)
      end
      @win.show
      Gtk.main
    end
  end
end

Keymap::Test.new