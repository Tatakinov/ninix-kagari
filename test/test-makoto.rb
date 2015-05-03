require "ninix/makoto"

module NinixTest

  class MakotoTest

    def initialize
      print("testing...\n")
      for i in 0...1000
        Makoto.test()
      end
      Makoto.test(:verbose => 1)
    end
  end
end

NinixTest::MakotoTest.new
