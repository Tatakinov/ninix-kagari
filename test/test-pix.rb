require "ninix/pix"

module NinixTest

  class PixTest

    def initialize(path)
      @win = Pix::TransparentWindow.new
      @win.signal_connect('destroy') do
        Gtk.main_quit
      end
      @win.darea.signal_connect('draw') do |w, cr|
        expose_cb(w, cr)
      end
      @surface = Pix.create_surface_from_file(path, true, true)
      @win.set_default_size(@surface.width, @surface.height)
      @win.show_all
      Gtk.main
    end

    def expose_cb(widget, cr)
      cr.set_source(@surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint
      region = Cairo::Region.new()
      data = @surface.data
      for i in 0..(data.size / 4 - 1)
        if (data[i * 4 + 3].ord) != 0
          x = i % @surface.width
          y = i / @surface.width
          region.union!(x, y, 1, 1)
        end
      end
      @win.input_shape_combine_region(region)
    end
  end
end


$:.unshift(File.dirname(__FILE__))

NinixTest::PixTest.new(ARGV.shift)
