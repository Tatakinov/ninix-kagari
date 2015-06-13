require "ninix/dll/hanayu"

module NinixTest

  class HanayuTest

    def initialize
      saori = Saori.new
      path = "./test/hanayu" ## FIXME
      saori.load(:dir => path)
      saori.setup
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      print(saori.execute(["show"]), "\n")
      Gtk.main # XXX
      saori.finalize
    end
  end
end

NinixTest::HanayuTest.new()
