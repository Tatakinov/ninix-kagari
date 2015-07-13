require "ninix/dll/textcopy"

module NinixTest

  class TextcopyTest

    def initialize
      saori = TextCopy::Saori.new
      saori.setup
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      print(saori.execute(["ninix test", 0]), "\n")
      print(saori.execute(["ninix test", 1]), "\n")
      saori.finalize
    end
  end
end

NinixTest::TextcopyTest.new()
