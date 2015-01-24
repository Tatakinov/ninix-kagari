# -*- coding: utf-8 -*-
#
#  sstplib.rb - an SSTP library module in Ruby
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "socket"

module SSTPLib

  class SSTPServer < TCPServer

    def initialize(hostname="", port)
      super(hostname, port)
      #allow_reuse_address = True
      setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    end
  end

  class AsynchronousSSTPServer < SSTPServer

    def handle_request
      r, w, e = select.select([self.socket], [], [], 0)
      if not r
        return
      end
      SSTPServer.handle_request(self)
    end
  end

  class BaseSSTPRequestHandler

    RESPONSES = {
        200 => 'OK',
        204 => 'No Content',
        210 => 'Break',
        400 => 'Bad Request',
        408 => 'Request Timeout',
        409 => 'Conflict',
        420 => 'Refuse',
        501 => 'Not Implemented',
        503 => 'Service Unavailable',
        510 => 'Not Local IP',
        511 => 'In Black List',
        512 => 'Invisible',
        }

    def initialize(fp)
      @fp = fp
    end

    def parse_headers()
      if @fp == nil
        return
      end
      headers = []
      while true
        line = @fp.readline()
        if line.strip.empty?
          break
        end
        if line.end_with?("\r\n")
          line = line[0..-3]
        elsif line.end_with?("\n")
          line = line[0..-2]
        end       
        headers << line
      end
      message = {}
      for h in headers
        if h.include?(":")
          key, value = h.split(":", 2)
          message[key] = value.strip
        end
      end
      if message.keys.include?("Charset")
        charset = message["Charset"]
      else
        charset = "Shift_JIS"
      end
      for key in message.keys
        message[key] = message[key].force_encoding(charset).encode("UTF-8", :invalid => :replace)
      end
      return message
    end

    def parse_request(requestline)
      requestline = requestline.encode('Shift_JIS')
      if requestline.end_with?("\r\n")
        requestline = requestline[0..-3]
      elsif requestline.end_with?("\n")
        requestline = requestline[0..-2]
      end
      @requestline = requestline
      re_requestsyntax = Regexp.new('^([A-Z]+) SSTP/([0-9]\\.[0-9])$')
      match = re_requestsyntax.match(requestline)
      if not match
        @equestline = '-'
        send_error(400, 'Bad Request ' + requestline.to_s)
        return 0
      end
      @command, @version = match[1, 2]
      @headers = parse_headers()
      return 1
    end

    def handle(line)
      @error = @version = nil
      if not parse_request(line)
        return
      end
      name = "do_" + @command.to_s + "_" + @version[0] + "_" + @version[2]
      begin
        method(name).call()
      rescue
        send_error(
          501,
          'Not Implemented (' + @command + '/' + @version + ')')
        return
      end
    end

    def send_error(code, message=nil)
      @error = code
      log_error((message or RESPONSES[code]))
      send_response(code, RESPONSES[code])
    end

    def send_response(code, message=nil)
      log_request(code, message)
      @fp.write("SSTP/" + (@version or "1.0") + " " + code.to_i.to_s + " " + RESPONSES[code] + "\r\n\r\n")
    end

    def log_error(message)
#      logging.error('[{0}] {1}\n'.format(self.timestamp(), message))
    end

    def log_request(code, message=None)
      if @requestline == '-'
        request = @requestline
      else
        request = ['"', @requestline, '"'].join("")
      end
#      logging.info('{0} [{1}] {2} {3:d} {4}\n'.format(
#                    self.client_hostname(), self.timestamp(),
#                    request, code, (message or RESPONSES[code])))
    end

    def client_hostname
      begin
        host, port = self.client_address
      rescue #except:
        return 'localhost'
      end
      begin
        hostname, aliaslist, ipaddrlist = socket.gethostbyaddr(host)
      rescue #except socket.error:
        hostname = host
      end
      return hostname
    end

    def timestamp
      month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
      t = Time.now.localtime
      m = month_names[t.month - 1]
      ## FIXME ##
      return t'{0:02d}/{1}/{2:d}:{3:02d}:{4:02d}:{5:02d} {6:+05d}'.format(
               t[2], m, t[0], t[3], t[4], t[5], (-time.timezone / 36).to_i)
    end
  end


  class TEST

    def initialize(port = 9801)
      sstpd = SSTPServer.new('', port)
      print('Serving SSTP on port ' + port.to_i.to_s + ' ...' + "\n")
      opt = sstpd.getsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR)
      print('Allow reuse address: ' + opt.int.to_s + "\n")
      while true
        s = sstpd.accept
        handler = BaseSSTPRequestHandler.new(s)
        buffer = s.gets
        handler.handle(buffer)
        s.close
      end
    end
  end
end

SSTPLib::TEST.new
