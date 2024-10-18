# -*- coding: utf-8 -*-
#
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require_relative "metamagic"

class BaseSSTPController < MetaMagic::Holon

  def initialize
    super("") ## FIXME
    @sstp_servers = []
    @__sstp_queue = []
    @__sstp_flag = false
    @__current_sender = nil
  end

  def enqueue_request(event, script_odict, sender, handle,
                      address, show_sstp_marker, use_translator,
                      entry_db, request_handler)
    @__sstp_queue <<
      [event, script_odict, sender, handle, address, show_sstp_marker,
       use_translator, entry_db, request_handler]
  end

  def check_request_queue(sender)
    count = 0
    for request in @__sstp_queue
      if request[2].split(' / ', 2)[0] == sender.split(' / ', 2)[0]
        count += 1
      end
    end
    if @__sstp_flag and \
      @__current_sender.split(' / ', 2)[0] == sender.split(' / ', 2)[0]
      count += 1
    end
    return count.to_s, @__sstp_queue.length.to_s
  end

  def set_sstp_flag(sender)
    @__sstp_flag = true
    @__current_sender = sender
  end

  def reset_sstp_flag
    @__sstp_flag = false
    @__current_sender = nil
  end

  def handle_sstp_queue
    return if @__sstp_flag or @__sstp_queue.empty?
    event, script_odict, sender, handle, address, \
    show_sstp_marker, use_translator, \
    entry_db, request_handler = @__sstp_queue.shift
    working = (not event.nil?)
    break_flag = false
    for if_ghost in script_odict.keys()
      if not if_ghost.empty? and @parent.handle_request('GET', 'if_ghost', if_ghost, :working => working)
        @parent.handle_request('NOTIFY', 'select_current_sakura', :ifghost => if_ghost)
        default_script = script_odict[if_ghost]
        break_flag = true
        break
      end
    end
    unless break_flag
      if @parent.handle_request('GET', 'get_preference', 'allowembryo').zero?
        if event.nil?
          request_handler.send_response(420) unless request_handler.nil? # Refuse
          return
        else
          default_script = nil
        end
      else
        if script_odict.include?('') # XXX
          default_script = script_odict['']
        else
          default_script = script_odict.values[0]
        end
      end
    end
    unless event.nil?
      script = handle_request('GET', 'get_event_response', event)
    else
      script = nil
    end
    if script.nil?
      script = default_script
    end
    if script.nil?
      request_handler.send_response(204) unless request_handler.nil? # No Content
      return
    end
    set_sstp_flag(sender)
    @parent.handle_request(
      'NOTIFY', 'enqueue_script',
      event, script, sender, handle, address,
      show_sstp_marker, use_translator, :db => entry_db,
      :request_handler => request_handler, :temp_mode => true)
  end

  def receive_sstp_request
    for sstp_server in @sstp_servers
      begin
        socket = sstp_server.accept_nonblock
      rescue
        next
      end
      begin
        buffer = socket.gets
        handler = create(buffer, sstp_server, socket)
        handler.handle
      rescue SocketError => e
        Logging::Logging.error("socket.error: #{e.message}")
      rescue SystemCallError => e
        Logging::Logging.error("socket.error: #{e.message} (#{e.errno})")
      rescue => e # may happen when ninix is terminated
        p e.message
        p e.backtrace
        return
      end
    end
  end

  def get_sstp_port
    return nil if @sstp_servers.empty?
    return @sstp_servers[0].server_address[1]
  end

  def quit
    for server in @sstp_servers
      server.close()
    end
  end

  def start_servers
  end
end

class TCPSSTPController < BaseSSTPController
  def initialize(port)
    super()
    @sstp_port = port
  end

  def start_servers
    for port in @sstp_port
      begin
        server = SSTP::SSTPServer.new(port)
      rescue SystemCallError => e
        Logging::Logging.warning("Port #{port}: #{e.message} (ignored)")
        next
      end
      server.set_responsible(self)
      @sstp_servers << server
      Logging::Logging.info("Serving SSTP on port #{port}")
    end
  end

  def create(buffer, sstp_server, socket)
    return SSTP::RequestHandler.create_with_http_support(buffer, sstp_server, socket)
  end
end

class UnixSSTPController < BaseSSTPController
  def initialize(uuid)
    super()
    @uuid = uuid
  end

  def start_servers
    server = NinixServer.new(@uuid)
    server.set_responsible(self)
    @sstp_servers << server
    Logging::Logging.info("Serving UnixSSTP on name #{@uuid}")
  end

  # HACK ninix_mainのget_event_response相当のことをここでやる
  def get_event_response(event, *args)
    return @parent.handle_request('GET', 'get_event_response', *event)
  end

  def create(buffer, sstp_server, socket)
    return SSTP::RequestHandler.create(buffer, sstp_server, socket)
  end
end
