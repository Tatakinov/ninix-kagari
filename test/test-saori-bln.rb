require "ninix/dll/bln"

module NinixTest

  class BlnTest

    def initialize
      @x = [600, 220]
      @y = [600, 700]
      saori = Saori.new
      path = "./test/bln"
      saori.need_ghost_backdoor(self)
      saori.load(:dir => path)
      saori.setup
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      #print(saori.execute(["head", "test1"]), "\n")
      #print(saori.execute(["honue_x1", "test2"]), "\n")
      #Gtk.main # XXX
      saori.finalize
    end

    def attach_observer(bln)
      @bln = bln
    end

    def detach_observer(bln)
      @bln = nil # XXX
    end

    def get_surface_scale
      return 90
    end

    def surface_is_shown(side)
      return true # XXX
    end

    def balloon_is_shown(side)
      return true # XXX
    end

    def is_talking
      return false ## FIXME
    end

    def get_surface_size(side)
      return 50, 100
    end

    def get_balloon_size(side)
      return 200, 80
    end

    def get_surface_position(side)
      return @x[side], @y[side]
    end

    def get_balloon_position(side)
      return @x[side] + 10, @y[side] - 20
    end

    def notify_event(*args)
      print("NOTIFY: ", args, "\n")
    end
  end
end

NinixTest::BlnTest.new()
