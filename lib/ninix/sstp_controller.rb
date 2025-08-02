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
require_relative "ninix_server"

class BaseSSTPController < MetaMagic::Holon

  def initialize
    super("") ## FIXME
    @sstp_servers = []
    @__sstp_queue = Thread::Queue.new
    @__sstp_flag = false
    @__current_sender = nil
  end

  def enqueue_request(event, script_odict, sender, handle,
                      address, show_sstp_marker, use_translator,
                      entry_db, request_handler, from_ayu = false, push_script = nil)
    @__sstp_queue <<
      [event, script_odict, sender, handle, address, show_sstp_marker,
       use_translator, entry_db, request_handler, from_ayu, push_script]
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
    entry_db, request_handler, from_ayu, push_script= @__sstp_queue.shift
    working = (not event.nil?)
    break_flag = false
    for if_ghost in script_odict.keys()
      if not if_ghost.empty? and @parent.handle_request(:GET, :if_ghost, if_ghost, :working => working)
        @parent.handle_request(:GET, :select_current_sakura, :ifghost => if_ghost)
        default_script = script_odict[if_ghost]
        break_flag = true
        break
      end
    end
    unless break_flag
      if @parent.handle_request(:GET, :get_preference, 'allowembryo').zero?
        if event.nil?
          request_handler.send_response(420) unless request_handler.nil? # Refuse
          unless push_script.nil?
            push_script.call(nil)
          end
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
      script = handle_request(:GET, :get_event_response, event)
    else
      script = nil
    end
    if script.nil?
      script = default_script
    end
    unless push_script.nil?
      push_script.call(script)
    end
    if script.nil?
      request_handler.send_response(204) unless request_handler.nil? # No Content
      return
    end
    set_sstp_flag(sender) unless from_ayu
    @parent.handle_request(
      :GET, :enqueue_script,
      event, script, sender, handle, address,
      show_sstp_marker, use_translator, :db => entry_db,
      :request_handler => request_handler, :temp_mode => true)
  end

  def receive_sstp_request(server, socket)
    begin
      buffer = socket.gets
      handler = create(buffer, server, socket)
      handler.handle
    rescue SocketError => e
      Logging::Logging.error("socket.error: #{e.message}")
      return false
    rescue SystemCallError => e
      Logging::Logging.error("socket.error: #{e.message} (#{e.errno})")
      return false
    rescue => e # may happen when ninix is terminated
      p e.message
      p e.backtrace
      return false
    end
    return true
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
      Thread.new(server) do |soc|
        until soc.closed?
          begin
            client = soc.accept
            receive_sstp_request(soc, client)
          rescue
            # TODO error handling
          end
        end
      end
    end
  end

  def create(buffer, sstp_server, socket)
    return SSTP::RequestHandler.create_with_http_support(buffer, sstp_server, socket)
  end
end

class UnixSSTPController < BaseSSTPController
  def initialize(uuid, ayu_uuid)
    super()
    @uuid = uuid
    @ayu_uuid = ayu_uuid
    @client_threads = []
  end

  def start_servers
    server = NinixServer.new(@uuid)
    server.set_responsible(self)
    @sstp_servers << server
    Logging::Logging.info("Serving UnixSSTP on name #{@uuid}")
    Thread.new(server) do |soc|
      until soc.closed?
        begin
          threads = []
          @client_threads.keep_if do |v|
            threads << v unless v.alive?
            v.alive?
          end
          threads.each do |v|
            v.join
          end
          client = soc.accept
          @client_threads << Thread.new(soc, client) do |s, c|
            receive_sstp_request(s, c)
            c.shutdown(Socket::SHUT_WR)
          end
        rescue
          # TODO error handling
        end
      end
    end
  end

  # HACK ninix_mainのget_event_response相当のことをここでやる
  def get_event_response(event)
    return @parent.handle_request(:GET, :notify_event, *event, return_script: true)
  end

  def create(buffer, sstp_server, socket)
    return SSTP::RequestHandler.create(buffer, sstp_server, socket, @uuid, @ayu_uuid)
  end
end
