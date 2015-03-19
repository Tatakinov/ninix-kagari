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
      ext = File.extname(path).downcase
      if ext == ".ico"
        pixbuf = Pix.create_icon_pixbuf(path)
        @surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32,
                                           pixbuf.width, pixbuf.height)
        cr = Cairo::Context.new(@surface)
        cr.set_source_pixbuf(pixbuf, 0, 0)
        cr.set_operator(Cairo::OPERATOR_SOURCE)
        cr.paint()
      elsif ext == ".ddp"
        #print("DDP size:", Pix.get_png_size(path), "\n")
        pixbuf = Pix.create_pixbuf_from_DDP_file(path)
        @surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32,
                                           pixbuf.width, pixbuf.height)
        cr = Cairo::Context.new(@surface)
        cr.set_source_pixbuf(pixbuf, 0, 0)
        cr.set_operator(Cairo::OPERATOR_SOURCE)
        cr.paint()
      elsif ext == ".dgp"
        # Not Yet
      else
        @surface = Pix.create_surface_from_file(path, true, true)
      end
      @win.set_default_size(@surface.width, @surface.height)
      @win.show_all
      Gtk.main
    end

    def expose_cb(widget, cr)
      cr.translate(*@win.get_draw_offset)
      cr.set_source(@surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint
      @win.set_shape(cr)
    end
  end
end


$:.unshift(File.dirname(__FILE__))

NinixTest::PixTest.new(ARGV.shift)
