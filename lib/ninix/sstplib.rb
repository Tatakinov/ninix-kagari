# -*- coding: utf-8 -*-
#
#  sstplib.rb - an SSTP library module in Ruby
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "ninix/logging"

module SSTPLib

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

    def initialize(server, fp)
      @server = server
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
      message = []
      for h in headers
        if h.include?(":")
          key, value = h.split(":", 2)
          message << [key, value.strip]
        end
      end
      if message.assoc("Charset") != nil
        charset = message.reverse.assoc("Charset")[1] # XXX
      else
        charset = "Shift_JIS"
      end
      new_list = []
      for item in message
        key, value = item
        new_list << [key, value.force_encoding(charset).encode("UTF-8", :invalid => :replace)] ## FIXME
      end
      message = new_list
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
        send_error(400, :message => 'Bad Request ' + requestline.to_s)
        return false
      end
      @command, @version = match[1, 2]
      @headers = parse_headers()
      return true
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
          :message => 'Not Implemented (' + @command + '/' + @version + ')')
        return
      end
    end

    def send_error(code, message: nil)
      @error = code
      log_error((message or RESPONSES[code]))
      send_response(code, :message => RESPONSES[code])
    end

    def send_response(code, message: nil)
      log_request(code, :message => message)
      @fp.write("SSTP/" + (@version or "1.0") + " " + code.to_i.to_s + " " + RESPONSES[code] + "\r\n\r\n")
    end

    def log_error(message)
      Logging::Logging.error('[' + timestamp + '] ' + message + '\n')
    end

    def log_request(code, message: nil)
      if @requestline == '-'
        request = @requestline
      else
        request = ['"', @requestline, '"'].join("")
      end
      Logging::Logging.info(client_hostname + ' [' + timestamp + '] ' + request + ' ' + code.to_s + ' ' + (message or RESPONSES[code]) + "\n")
    end

    def client_hostname
      begin
        sock_domain, remote_port, remote_hostname, remote_ip = @fp.peeraddr
        return remote_hostname
      rescue
        return 'localhost'
      end
    end

    def timestamp
      month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
      t = Time.now.localtime
      m = month_names[t.month - 1]
      return sprintf('%02d/%s/%d:%02d:%02d:%02d %+05d',
                     t.day, m, t.year, t.hour, t.min, t.sec, t.utc_offset / 36)
    end
  end
end
