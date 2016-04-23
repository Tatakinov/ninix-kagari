# coding: utf-8
require_relative "../lib/ninix/sstp"

module NinixTest

  class SSTPTest

    def initialize
      port = 9801
      sstpd = SSTP::SSTPServer.new(port)
      sstpd.set_responsible(self)
#      @request_handler = nil
      print('Serving SSTP on port ' + port.to_i.to_s + ' ...' + "\n")
      opt = sstpd.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR)
      print('Allow reuse address: ' + opt.int.to_s + "\n")
      @cantalk = 0
      while true
        s = sstpd.accept
        handler = SSTP::SSTPRequestHandler.new(sstpd, s)
        buffer = s.gets
        handler.handle(buffer)
        if sstpd.has_request_handler
          #sstpd.send_answer("TEST")
          #sstpd.send_no_content
          #sstpd.send_sstp_break
          #sstpd.send_response(511)
          sstpd.send_timeout
        end
        s.close
      end
      #serv.shutdown_request("TEST")
    end

#    def has_request_handler
#      if @request_handler != nil
#        return true
#      else
#        return false
#      end
#    end
#
#    def set_request_handler(handler) ## FIXME
#      @request_handler = handler
#    end

    def handle_request(event, *args)
      if event == "GET"
        print("ARGS: ", args, "\n")
        if args[0] == "get_sakura_cantalk"
#          print("CANTALK :", @cantalk, "\n")
          if @cantalk == 1
            @cantalk = 0
            return true
          else
            @cantalk = 1
            return false
          end
        elsif args[0] == "get_ghost_names"
          return ["A", "B", "C"]
        elsif args[0] == "check_request_queue"
          return [100, 200]
        else
          return "日本語テスト"
        end
      elsif event == "NOTIFY"
        print("NOTIFY: ", args, "\n")
        return 1
      end
    end
  end
end

NinixTest::SSTPTest.new
