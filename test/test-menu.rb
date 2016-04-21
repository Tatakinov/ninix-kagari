require_relative "../lib/ninix/menu"

module NinixTest

  class MenuTest
    
    def initialize(path)
      @test_menu = Menu::Menu.new
      @test_menu.set_responsible(self)
      @test_menu.create_mayuna_menu({}) # XXX
      @test_menu.set_pixmap(nil, nil, nil, "left", "left", "left") # XXX
      @window = Pix::TransparentWindow.new()
      @image_surface = Pix.create_surface_from_file(path)
      @window.signal_connect('delete_event') do |w, e|
        # delete(w, e)
        Gtk.main_quit
      end
      @darea = @window.darea # @window.get_child()
      @darea.set_events(Gdk::EventMask::EXPOSURE_MASK|
                        Gdk::EventMask::BUTTON_PRESS_MASK|
                        Gdk::EventMask::BUTTON_RELEASE_MASK|
                        Gdk::EventMask::POINTER_MOTION_MASK|
                        Gdk::EventMask::POINTER_MOTION_HINT_MASK|
                        Gdk::EventMask::LEAVE_NOTIFY_MASK)
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
        if event.event_type == Gdk::EventType::BUTTON_PRESS
          @test_menu.popup(event.button, 0)
        end
      elsif event.button == 3
        if event.event_type == Gdk::EventType::BUTTON_PRESS
          @test_menu.popup(event.button, 1)
        end
      end
      return true
    end

    def handle_request(type, event, *a)
#      print("EVENT: ", event, "\n")
#      print("ARGS: ", a, "\n")
      if event == 'get_ghost_menus'
        return []
      elsif event == 'get_nekodorif_list'
        return []
      elsif event == 'get_kinoko_list'
        return []
      elsif event == 'getstring'
        if a[0] == 'kero.popupmenu.visible'
          return "0"
        elsif a[0] == 'sakura.popupmenu.visible'
          return "1"
        elsif a[0] == 'vanishbuttonvisible'
          return "1"
        elsif a[0] == 'vanishbutton.visible'
          return "1"
        elsif a[0] == 'kero.recommendsites'
          return "1"
        end
      end
    end
  end
end


$:.unshift(File.dirname(__FILE__))

NinixTest::MenuTest.new(ARGV.shift)
