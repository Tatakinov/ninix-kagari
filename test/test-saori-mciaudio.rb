require "ninix/dll/mciaudio"

module NinixTest

  class MciaudioTest

    def initialize
      saori = MCIAudio::Saori.new
      saori.load(:dir => "") # XXX
      saori.setup
      saori.need_ghost_backdoor(self)
      saori.request("") # XXX
      filename = "test.mp3"
      abs_path = File.absolute_path(filename)
      print(saori.execute(nil), "\n")                # Bad Request
      print(saori.execute(["stop"]), "\n")           # No Content
      print(saori.execute(["load", abs_path]), "\n") # Bad Request
      print(saori.execute(["load", filename]), "\n") # No Content
      print(saori.execute(["play"]), "\n")           # No Content
      print("PLAYING...\n")
      sleep(2)
      print(saori.execute(["play"]), "\n")           # No Content
      print("PAUSE...\n")
      sleep(3)
      print(saori.execute(["play"]), "\n")           # No Content
      print("PLAYING...\n")
      GLib::MainLoop.new(nil, false).run # XXX
      saori.finalize
    end

    def get_prefix
      return File.absolute_path("./test") # XXX
    end
  end
end

NinixTest::MciaudioTest.new()
