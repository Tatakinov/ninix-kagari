require "ninix_main"

module NinixTest

  class UsageDialogTest

    def initialize
      @usage_dialog = Ninix_Main::UsageDialog.new
    end

    def update
      return true
    end

    def do_tests
      history = [
        ['a', [ 100, []]],
        ['b', [ 200, []]],
        ['x', [1000, []]],
        ['f', [1400, []]],
        ['e', [  10, []]],
      ]
      @usage_dialog.open(history)
      GLib::Timeout.add(3000) { update }
      Gtk.main    
    end
  end
end

test = NinixTest::UsageDialogTest.new
test.do_tests
