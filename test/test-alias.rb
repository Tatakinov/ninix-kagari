require_relative "../lib/ninix/alias"

module NinixTest

  class AliasTest

    def initialize(path)
      conf = Alias::create_from_file(path)
      print("ALIAS:   #{conf}\n")
    end
  end
end

$:.unshift(File.dirname(__FILE__))

NinixTest::AliasTest.new(ARGV.shift)
