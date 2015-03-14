require "ninix/prefs"

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
      return []
    end
  end
end

NinixTest::PrefsTest.new
