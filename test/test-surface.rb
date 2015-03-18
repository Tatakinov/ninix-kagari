require "ninix/home"
require "ninix/surface"

module NinixTest

  class SurfaceTest

    def initialize
      ghosts = Home.search_ghosts(target=nil, check_shiori=false)
      if ghosts.empty?
        raise SystemExit('Ghosts not found.\n') ## FIXME
      end
      surface_sets = {}
      key = ghosts.keys.sample
      surface_set = ghosts[key][3]
      prefix = ghosts[key][4]
      default_sakura = "0"
      default_kero = "10"
      key = surface_set.keys.sample
      name, surface_dir, desc, alias_, surface_info, tooltips, seriko_descript = surface_set[key]
      @surface = Surface::Surface.new
      @surface.set_responsible(self)
      @surface.new_(desc, alias_, surface_info, name, prefix, tooltips, seriko_descript, default_sakura, default_kero)
      GLib::Timeout.add(3000) { update }
      Gtk.main
    end

    def update
      @surface.set_surface_default(nil)
      @surface.reset_position
      @surface.show(0)
      @surface.show(1)
      return true
    end

    def handle_request(event_type, event, *arglist, **argdict)
      if event == 'get_surface_id'
        return 0
      elsif event == 'get_selfname'
        return 'SAKURA'
      elsif event == 'get_keroname'
        return 'KERO'
      elsif event == 'lock_repaint'
        return false
      elsif event == "get_preference"
        if arglist[0] == "surface_scale"
          return 100
        elsif arglist[0] == "animation_quality"
          return 1
        end
      elsif event == "lock_repaint"
        return false
      else
        return 1 # XXX
      end
    end
  end
end

NinixTest::SurfaceTest.new
