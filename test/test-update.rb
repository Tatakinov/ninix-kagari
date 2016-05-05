require_relative "../lib/ninix/update"

module NinixTest

  class UpdateTest

    def initialize(ghostdir, homeurl)
      update = Update::NetworkUpdate.new
      update.set_responsible(self)
      update.start(homeurl, ghostdir, :timeout => 60)
      while true
        state = update.state
        s = Time.now.to_i
        code = update.run()
        e = Time.now.to_i
        delta = (e - s)
        if delta > 0.1
          print('Warning: state = ', state.to_i, ' (', delta.to_f, ' sec)', "\n")
        end
        while true
          event = update.get_event()
          if event == nil
            break
          end
          print(event, "\n")
        end
        if not code
          break
        end
        if update.state == 5 and not update.get_schedule.empty?
          print('File(s) to be update:', "\n")
          for filename, checksum in update.get_schedule
            print('   ', filename, "\n")
          end
        end
      end
      update.stop()
      update.clean_up()
    end

    def handle_request(*a)
      return nil
    end
  end
end

#homeurl = "http://aquadrop.sakura.ne.jp/ghost/shizuku/"
#ghostdir = "/home/shy/TEST/ghost/shizuku"
homeurl = "http://unvollendet.hp.infoseek.co.jp/ukagaka/kousin2/"
ghostdir = "home/shy/TEST/ghost/Taromati"
#homeurl = "http://rking.x0.com/ukagaka_up/bth5/"
#ghostdir = "home/shy/TEST/ghost/BTHver.5"
NinixTest::UpdateTest.new(ghostdir, homeurl)
