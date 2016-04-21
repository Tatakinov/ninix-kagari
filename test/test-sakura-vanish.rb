require_relative "../lib/ninix/sakura"

module NinixTest

  class VanishTest

    def initialize
      dialog = Sakura::VanishDialog.new
      dialog.set_responsible(self)
      dialog.set_message("test")
      dialog.show()
      Gtk.main
    end

    def handle_request(event_type, event, *arglist, **argdict)
      if event_type == "NOTIFY"
        print("NOTIFY: ", event, "\n")
      end
    end
  end
end

test = NinixTest::VanishTest.new
