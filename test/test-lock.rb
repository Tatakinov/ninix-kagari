require_relative "../lib/ninix/lock"

module NinixTest

  class LockTest

    def initialize(path)
      open(path, "w") {|f|
        if Lock.lockfile(f)
          print("LOCK\n")
          sleep(5)
          Lock.unlockfile(f)
          print("UNLOCK\n")
        else
          print("LOCK: failed.\n")
        end
      }
    end
  end
end

$:.unshift(File.dirname(__FILE__))

NinixTest::LockTest.new(ARGV.shift)
