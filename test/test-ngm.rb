require "ninix/ngm"

module NinixTest

  class NGMTest

    def initialize
      ngm = NGM::NGM.new()
      ngm.set_responsible(self)
      ngm.show_dialog()
      Gtk.main
    end

    def handle_request(event_type, event, *arglist, **argdict)
      return ''
    end
  end
end

NinixTest::NGMTest.new
