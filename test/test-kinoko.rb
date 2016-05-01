require_relative "../lib/ninix/home"
require_relative "../lib/ninix/kinoko"

module NinixTest

  class KinokoTest

    def initialize(path)
      @win = Pix::TransparentWindow.new
      @win.signal_connect('destroy') do
        Gtk.main_quit
      end
      @win.darea.signal_connect('draw') do |w, cr|
        expose_cb(w, cr)
      end
      @surface = Pix.create_surface_from_file(path, :is_pnr => true, :use_pna => true)
      @win.set_default_size(@surface.width, @surface.height)
      @win.show_all
      kinoko_list = Home.search_kinoko()
      print("K: ", kinoko_list, "\n")
      kinoko = Kinoko::Kinoko.new(kinoko_list)
      #print("K: ", kinoko, "\n")
      kinoko.load(kinoko_list.sample, self)
      Gtk.main
    end

    def notify_event(event, *args) # dummy
    end

    def get_window # dummy
      return @win
    end

    def get_kinoko_position(baseposition) # dummy
      return 100, 200
    end

    def handle_request(type, event, *a) # dummy
      if event == 'get_preference' and a[0] == 'animation_quality'
        return 1
      end
    end

    def get_target_window
      return @win
    end

    def attach_observer(arg) # dummy
    end

    def detach_observer(arg) # dummy
    end

    def get_surface_scale() # dummy
      return 100
    end

    def expose_cb(widget, cr)
      cr.set_source(@surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint
      region = Cairo::Region.new()
      data = @surface.data
      for i in 0..(data.size / 4 - 1)
        if (data[i * 4 + 3].ord) != 0
          x = (i % @surface.width)
          y = (i / @surface.width)
          region.union!(x, y, 1, 1)
        end
      end
      @win.input_shape_combine_region(region)
    end
  end
end

$:.unshift(File.dirname(__FILE__))

NinixTest::KinokoTest.new(ARGV.shift)
