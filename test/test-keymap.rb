require_relative "../lib/ninix/keymap"

module NinixTest

  class KeymapTest

    def key_press(widget, event)
      begin
        print(Keymap::Keymap_old[event.keyval], " ",
              Keymap::Keymap_new[event.keyval], " ",
              event.keyval, "\n")
      rescue # except KeyError:
        print('unknown keyval: ', event.keyval,
              "(", Gdk::Keyval.to_name(event.keyval), ")\n")
      end
    end

    def initialize
      @win = Gtk::Window.new
      @win.set_events(Gdk::EventMask::KEY_PRESS_MASK)
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

NinixTest::KeymapTest.new
