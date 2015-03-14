require "ninix/update"

module NinixTest

  class UpdateTest

    def initialize
      update = Update::NetworkUpdate.new
      update.set_responsible(self)
      homeurl = "http://www.aquadrop.sakura.ne.jp/shizuku/"
      ghostdir = "/home/shy/TEST/ghost/shizuku"
      update.start(homeurl, ghostdir, timeout=60)
      while true
        state = update.state
        s = Time.now.to_i
        code = update.run()
        e = Time.now.to_i
        delta = e - s
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
        if code == 0
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

NinixTest::UpdateTest.new
