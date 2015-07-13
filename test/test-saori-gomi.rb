require "ninix/dll/gomi"

module NinixTest

  class GomiTest

    def initialize
      saori = Gomi::Saori.new
      saori.setup
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      print(saori.execute(["-v -n", 0]), "\n")
      print(saori.execute(["-v -e", 0]), "\n")
#      print(saori.execute(["-f -e", 0]), "\n")
      saori.finalize
    end
  end
end

NinixTest::GomiTest.new()
