require_relative "../lib/ninix/prefs"

module NinixTest

  class PrefsTest

    def initialize
      @dialog = Prefs::PreferenceDialog.new()
      @dialog.set_responsible(self)
      @dialog.load()
      @dialog.show()
#      @dialog.save()
      Gtk.main
    end

    def handle_request(type, event, *a) # dummy
      if event == 'get_balloon_list'
        return [["test name", "test dir"]]
      end
      return []
    end
  end
end

NinixTest::PrefsTest.new
