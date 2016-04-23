require_relative "../lib/ninix_main"

module NinixTest

  class ConsoleTest

    def initialize
      @console = Ninix_Main::Console.new(self)
    end

    def update
      return true
    end

    def do_tests
      @console.open
      GLib::Timeout.add(3000) { update }
      Gtk.main    
    end

    def confirmed
      return false
    end

    def quit
      Gtk.main_quit
    end

    def search_ghosts
      return 0, 0
    end

    def do_install(filename)
      print("INSTALL: ", filename, "\n")
    end
  end
end

test = NinixTest::ConsoleTest.new
test.do_tests
