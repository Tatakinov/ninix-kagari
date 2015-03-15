require "ninix/sstplib"

module NinixTest

  class SSTPLibTest

    def initialize(port = 9801)
      sstpd = SSTPLib::SSTPServer.new('', port)
      print('Serving SSTP on port ' + port.to_i.to_s + ' ...' + "\n")
      opt = sstpd.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR)
      print('Allow reuse address: ' + opt.int.to_s + "\n")
      while true
        s = sstpd.accept
        handler = SSTPLib::BaseSSTPRequestHandler.new(self, s)
        buffer = s.gets
        handler.handle(buffer)
        s.close
      end
    end

    def request_parent(args)
      print("ARGS: ", args, "\n")
      return 1
    end
  end
end

NinixTest::SSTPLibTest.new
