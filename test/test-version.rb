require "ninix/version"

module NinixTest

  class VersionTest

    def initialize()
      print(Version.VERSION_INFO + "\n")
    end
  end
end

NinixTest::VersionTest.new()
