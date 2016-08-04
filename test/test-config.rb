require_relative "../lib/ninix/config"

module NinixTest

  class ConfigTest

    def initialize(path)
      conf = NConfig::create_from_file(path)
      conf.each {|key, value|
        print("Key:   #{key}\n")
        print("Value: #{value}\n")
      }
    end
  end
end

$:.unshift(File.dirname(__FILE__))

NinixTest::ConfigTest.new(ARGV.shift)
