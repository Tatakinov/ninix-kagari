require "ninix/home"
require "ninix/sakura"

module NinixTest

  class ReadmeTest

    def initialize
      ghosts = Home.search_ghosts(target=nil, check_shiori=false)
      key = ghosts.keys.sample
      prefix = ghosts[key][4]
      dialog = Sakura::ReadmeDialog.new
      dialog.set_responsible(self)
      dialog.show("test", prefix)
      Gtk.main
    end

    def handle_request(event_type, event, *arglist, **argdict)
    end
  end
end

test = NinixTest::ReadmeTest.new
test.do_tests
