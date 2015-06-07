require "ninix/dll/osuwari"

module NinixTest

  class OsuwariTest

    def initialize
      saori = Saori.new
      saori.setup
      saori.need_ghost_backdoor(self)
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      print(saori.execute(
             ["START", "s1", "ACTIVE", "TL", "10", "20", "100",
              "XMOVE", "LEFT WORKAREA"]),
            "\n")
      saori.do_idle_tasks # XXX
      print(saori.execute(["STOP"]), "\n")
      saori.finalize
    end

    def identify_window(args)
      return false # XXX
    end

    def get_surface_scale
      return 90
    end

    def get_surface_size(side)
      return 50, 100
    end

    def set_surface_position(side, x, y)
      print("SIDE: ", side, "\n")
      print("POSITION: ", x, ", ", y, "\n")
    end

    def raise_surface(side)
      print("RAISE: ", side, "\n")
    end
  end
end

NinixTest::OsuwariTest.new()
