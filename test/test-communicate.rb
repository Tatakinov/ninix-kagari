require "ninix/communicate"

module NinixTest

  class DUMMY_SAKURA

    def initialize(name)
      @name = name
    end

    def is_listening(event)
      return true
    end

    def enqueue_event(event, *references)
      print("NAME: ", @name, "\n")
      print("EVENT: ", event, "\n")
      print("REF: ", references, "\n")
    end

    def key
      return @name
    end
  end

  class CommunicateTest

    TEST_DATA = [['Sakura', 0, 10], 
                 ['Naru', 8, 11],
                 ['Busuko', 6666, 1212]]
    def initialize
      ghosts = []
      communicate = Communicate::Communicate.new
      for ghost in TEST_DATA
        sakura = DUMMY_SAKURA.new(ghost[0])
        ghosts << [sakura, ghost]
        communicate.rebuild_ghostdb(sakura, *ghost)
      end
      print("COMMUNICATE:",
            communicate.get_otherghostname(ghosts.sample[1][0]), "\n")
      communicate.notify_all('TEST', [1, 'a', {22 => 'test'}])
      from = ghosts.sample
      to = ghosts.sample ## FIXME
      communicate.notify_other(from[1][0],
                               'OnOtherTest', to[1][0], from[1][0], '',
                               false, nil,
                               nil, false, '\h\s[10]test\e', [1, 2, 3, 'a'])
      communicate.notify_other(from[1][0],
                               'OnOtherTest', to[1][0], from[1][0], '',
                               false, '__SYSTEM_ALL_GHOST__',
                               nil, false, '\h\s[10]test\e', [1, 2, 3, 'a'])
    end
  end
end

NinixTest::CommunicateTest.new
