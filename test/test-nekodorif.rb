require "ninix/home"
require "ninix/nekodorif"

module NinixTest

  class NekodorifTest

    def initialize
      nekoninni = Home.search_nekoninni()
      katochan = Home.search_katochan()
      neko = Nekodorif::Nekoninni.new
      ninni = nekoninni.sample
      neko.load(ninni[1], katochan, self)
      Gtk.main
    end

    def attach_observer(nekoninni) # dummy
    end

    def detach_observer(nekoninni) # dummy
    end

    def get_surface_scale
      return 100
    end

    def get_selfname
      return "Sakura"
    end

    def get_keroname
      return "Kero"
    end

    def notify_event(*a)
    end

    def get_surface_position(side)
      return 0, 0
    end

    def get_surface_size(side)
      return 100, 100
    end

    def handle_request(type, event, *a) # dummy
    end
  end
end

NinixTest::NekodorifTest.new
