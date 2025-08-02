# -*- coding: utf-8 -*-
#
#  sstplib.rb - an SSTP library module in Ruby
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require_relative "logging"

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

    def initialize(server, fp, command, version, uuid = nil)
      @server = server
      @fp = fp
      @command = command
      @version = version
      @uuid = uuid
    end

    def parse_headers(fp)
      return if fp.nil?
      message = []
      while line = fp.gets
        break if line.strip.empty?
        line = line.chomp
        next unless line.include?(":")
        key, value = line.split(":", 2)
        message << [key, value.strip]
      end
      charset = message.reverse.assoc("Charset")&.at(1) || "UTF-8" # XXX
      message.each {|k, v| v.force_encoding(charset).encode!("UTF-8", :invalid => :replace, :undef => :replace) }
    end

    def parse_request(fp)
      @headers = parse_headers(fp)
      return true
    end

    def handle
      @error = nil
      return unless parse_request(@fp)
      name = ("do_#{@command}_#{@version[0]}_#{@version[2]}")
      begin
        send(name)
      rescue => e
        p e
        pp e.backtrace
        send_error(
          501,
          :message => "Not Implemented (#{@command}/#{@version})")
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
      @fp.write(response(code))
    end

    def response(code)
      return "SSTP/#{(@version or "1.0")} #{code} #{RESPONSES[code]}\r\n\r\n"
    end

    def log_error(message)
      Logging::Logging.error("[#{timestamp}] #{message}\n")
    end

    def log_request(code, message: nil)
      if @requestline == '-'
        request = @requestline
      else
        request = "\"#{@requestline}\""
      end
      Logging::Logging.info("#{client_hostname} [#{timestamp}] #{request} #{code} #{(message or RESPONSES[code])}\n")
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
      Time.now.localtime.strftime("%d/%b/%Y:%H:%M:%S %z")
    end

    def is_owned
      false
    end
  end
end
