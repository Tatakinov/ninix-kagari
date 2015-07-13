require "ninix/dll/wmove"

module NinixTest

  class WmoveTest

    def initialize
      @x = [100, 320]
      @y = [200, 400]
      saori = WMove::Saori.new
      saori.setup
      saori.need_ghost_backdoor(self)
      saori.load
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      print(saori.execute(['GET_DESKTOP_SIZE']), "\n")
      print(saori.execute(['GET_POSITION', ""]), "\n")
      print(saori.execute(['GET_POSITION', get_selfname]), "\n")
      print(saori.execute(['GET_POSITION', get_keroname]), "\n")
      print(saori.execute(['CLEAR']), "\n")
      print(saori.execute(['CLEAR', get_selfname]), "\n")
      print(saori.execute(['CLEAR', get_keroname]), "\n")
      print(saori.execute(
             ['STANDBY', get_selfname, get_keroname,
              "-10", "1", "5"]),
            "\n")
      print(saori.execute(
             ['STANDBY_INSIDE', get_keroname, get_selfname,
              "20", "3", "12"]),
            "\n")
      print(saori.execute(['MOVE', get_selfname, "100", "50"]), "\n")
      print(saori.execute(['MOVE_INSIDE', get_keroname, "-100", "50"]), "\n")
      saori.do_idle_tasks # move
      saori.do_idle_tasks # move
      saori.do_idle_tasks # move
      print(saori.execute(['MOVETO', get_keroname, "640", "50"]), "\n")
      print(saori.execute(['MOVETO_INSIDE', get_selfname, "320", "10"]), "\n")
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      saori.do_idle_tasks # moveto
      print(saori.execute(['ZMOVE', get_selfname, '1']), "\n")
      print(saori.execute(['ZMOVE', get_selfname, '2']), "\n")
      print(saori.execute(['ZMOVE', get_keroname, '1']), "\n")
      print(saori.execute(['ZMOVE', get_keroname, '2']), "\n")
      saori.do_idle_tasks # raise
      saori.do_idle_tasks # lower
      print(saori.execute(['WAIT', get_selfname, "26"]), "\n") # > 25[ms]
      print(saori.execute(['WAIT', get_keroname, "0"]), "\n")
      saori.do_idle_tasks # wait
      saori.do_idle_tasks # wait(only sakura side)
      print(saori.execute(
             ['NOTIFY', get_selfname, "TEST EVENT(S)", "REF0"]),
            "\n")
      print(saori.execute(
             ['NOTIFY', get_keroname, "TEST EVENT(K)", "REF0", "REF1"]),
            "\n")
      saori.do_idle_tasks # notify
      saori.finalize
    end

    def get_selfname
      return "Sakura"
    end

    def get_keroname
      return "Kero"
    end

    def get_surface_size(side)
      return 50, 100
    end

    def get_surface_position(side)
      return @x[side], @y[side]
    end

    def set_surface_position(side, x, y)
      print("SIDE: ", side, "\n")
      print("POSITION: ", x, ", ", y, "\n")
      @x[side] = x
      @y[side] = y
    end

    def raise_surface(side)
      print("RAISE: ", side, "\n")
    end

    def lower_surface(side)
      print("LOWER: ", side, "\n")
    end

    def notify_event(*args)
      print("NOTIFY: ", args, "\n")
    end
  end
end

NinixTest::WmoveTest.new()
