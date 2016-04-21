# coding: utf-8
require_relative "../lib/ninix/dll/httpc"

module NinixTest

  class HTTPCTest

    def initialize
      saori = Httpc::Saori.new
      saori.setup
      saori.need_ghost_backdoor(self)
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      print(saori.execute([]), "\n")
      print(saori.execute(['bg']), "\n")
      print(saori.execute(["https://osdn.jp/projects/ninix-aya/"]), "\n")
      print(saori.execute(['bg', "100", "https://osdn.jp/projects/ninix-aya/", "活動", "見る"]), "\n")
      Gtk.main # XXX
      saori.finalize
    end

    def notify_event(*args)
      print("NOTIFY: ", args, "\n")
    end
  end
end

NinixTest::HTTPCTest.new()
