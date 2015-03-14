require "ninix/config"

module NinixTest

  class ConfigTest

    def initialize(path)
      conf = NConfig::create_from_file(path)
      for key in conf.keys 
        print("Key:   ", key, "\n")
        print("VALUE: ", conf[key], "\n")
      end
    end
  end
end

$:.unshift(File.dirname(__FILE__))

NinixTest::ConfigTest.new(ARGV.shift)
