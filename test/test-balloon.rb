require_relative "../lib/ninix/home"
require_relative "../lib/ninix/balloon"

module NinixTest

  class BalloonTest

    def initialize
      balloons = Home.search_balloons()
      key = balloons.keys.sample
#      print(key, balloons[key], "\n")
      balloon = Balloon::Balloon.new
      balloon.set_responsible(self)
      balloon.new_(*balloons[key])
      balloon.set_balloon(0, 0)
      balloon.set_balloon(1, 0)
      balloon.set_position(0, 400, 200)
      balloon.set_position(1, 200, 100)
      balloon.show(0)
      balloon.show(1)
      balloon.show_sstp_message("TEST: SSTP", "TEST class")
      for i in 0..20
        balloon.append_text(0, "TEST: SAKURA")
      end
      balloon.append_text(1, "TEST: KERO")
      Gtk.main
    end

    def handle_request(event_type, event, *arglist, **argdict)
      if event == 'lock_repaint'
        return false
      elsif event == 'busy'
        return false
      else
        return 100 # XXX
      end
    end

  end
end

NinixTest::BalloonTest.new()
