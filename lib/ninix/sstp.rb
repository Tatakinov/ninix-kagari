# -*- coding: utf-8 -*-
#
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

require "socket"
require "stringio"

require_relative "entry_db"
require_relative "script"
require_relative "version"
require_relative "sstplib"
require_relative "logging"


module SSTP

  class SSTPServer < TCPServer
    attr_reader :socket

    def initialize(address)
      @parent = nil
      super(address)
      setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
      @request_handler = nil
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      @parent&.handle_request(event_type, event, *arglist)
    end

    def set_request_handler(handler) ## FIXME
      @request_handler = handler
    end

    def has_request_handler
      not @request_handler.nil?
    end

    def send_response(code, data: nil)
      begin
        @request_handler.send_response(code)
        @request_handler.write(data) unless data.nil? # FIXME
        @request_handler.shutdown(Socket::SHUT_WR) # XXX
      rescue
        #pass
      end
      @request_handler = nil
    end

    def send_answer(value)
      charset = @request_handler.get_charset
      answer = "#{value.encode(charset, :invalid => :replace, :undef => :replace)}\r\n\r\n"
      send_response(200, :data => answer) # OK
    end

    def send_no_content
      send_response(204) # No Content
    end

    def send_sstp_break
      send_response(210) # Break
    end

    def send_timeout
      send_response(408) # Request Timeout
    end

    def close
      # NOP
    end
  end


  class SSTPRequestHandler < SSTPLib::BaseSSTPRequestHandler

    def initialize(...)
      super
      @response_queue = Thread::Queue.new
    end

    def handle
      unless @server.handle_request(:GET, :get_sakura_cantalk)
        @error = nil
        return unless parse_request(@fp)
        send_error(512)
      else
        super
      end
    end

    # SEND
    def do_SEND_1_0
      handle_send(1.0)
    end

    def do_SEND_1_1
      handle_send(1.1)
    end

    def do_SEND_1_2
      handle_send(1.2)
    end

    def do_SEND_1_3
      handle_send(1.3)
    end

    def do_SEND_1_4
      handle_send(1.4)
    end

    def handle_send(version)
      return unless check_decoder()
      sender = get_sender()
      return if sender.nil?
      case version
      when 1.3
        handle = get_handle()
        return if handle.nil?
      else
        handle = nil
      end
      script_odict = get_script_odict()
      return if script_odict.nil?
      case version
      when 1.0, 1.1
        entry_db = nil
      when 1.2, 1.3, 1.4
        entry_db = get_entry_db()
        return if entry_db.nil?
      end
      enqueue_request(sender, nil, handle, script_odict, entry_db)
    end

    # NOTIFY
    def do_NOTIFY_1_0
      handle_notify(1.0)
    end

    def do_NOTIFY_1_1
      handle_notify(1.1)
    end

    def do_NOTIFY_1_2
      handle_notify(1.2)
    end

    def do_NOTIFY_1_3
      handle_notify(1.3)
    end

    def do_NOTIFY_1_4
      handle_notify(1.4)
    end

    def handle_notify(version)
      script_odict = {}
      return unless check_decoder()
      sender = get_sender()
      return if sender.nil?
      event = get_event()
      return if event.nil?
      case version
      when 1.0
        entry_db = nil
      when 1.1
        script_odict = get_script_odict()
        return if script_odict.nil?
        entry_db = get_entry_db()
        return if entry_db.nil?
      end
      enqueue_request(sender, event, nil, script_odict, entry_db)
    end

    def enqueue_request(sender, event, handle, script_odict, entry_db)
      sock_domain, remote_port, remote_hostname, remote_ip = @fp.peeraddr
      address = remote_hostname # XXX
      if entry_db.nil? or entry_db.is_empty()
        show_sstp_marker, use_translator = get_options()
        @server.handle_request(
          :GET, :enqueue_request,
          event, script_odict, sender, handle,
          address, show_sstp_marker, use_translator,
          entry_db, nil, from_ayu, proc do |script|
            @response_queue.push(script)
          end)
        script = @response_queue.pop
        if script.nil? or script.empty?
          send_response(204, ['Charset: UTF-8']) # No Content
        else
          send_response(200, ['Charset: UTF-8', "Script: #{script}"]) # OK
        end
      elsif @server.has_request_handler
        send_response(409) # Conflict
      else
        show_sstp_marker, use_translator = get_options()
        @server.handle_request(
          :GET, :enqueue_request,
          event, script_odict, sender, handle,
          address, show_sstp_marker, use_translator,
          entry_db, @server)
        @server.set_request_handler(self) # keep alive
      end
    end

    PROHIBITED_TAGS = ['\j', '\-', '\+', '\_+', '\!', '\8', '\_v', '\C']

    def check_script(script)
      unless local_request()
        parser = Script::Parser.new
        nodes = []
        while true
          begin
            nodes.concat(parser.parse(script))
          rescue Script::ParserError => e
            done, script = e.get_item
            nodes.concat(done)
          else
            break
          end
        end
        nodes.each do |node|
          next unless node[0] == Script::SCRIPT_TAG
          if PROHIBITED_TAGS.include?(node[1]) and not is_owned
            send_response(400) # Bad Request
            log_error("Script: tag #{node[1]} not allowed")
            return true
          end
        end
      end
      return false
    end

    def is_owned
      return false if @uuid.nil? or @uuid.empty?
      @headers.lazy.filter_map do |k, v|
        v if k == 'ID'
      end.first == @uuid
    end

    def from_ayu
      return false if @ayu_uuid.nil? or @ayu_uuid.empty?
      @headers.lazy.filter_map do |k, v|
        v if k == 'Ayu'
      end.first == @ayu_uuid
    end

    def get_script_odict
      script_odict = {} # Ordered Hash
      if_ghost = nil
      @headers.each do |name, value|
        case name
        when 'IfGhost'
          if_ghost = value
        when 'Script'
          # nop
        else
          if_ghost = nil
          next
        end
        script = value.to_s
        return if check_script(script)
        script_odict[if_ghost || ''] = script
        if_ghost = nil
      end
      return script_odict
    end

    def get_entry_db
      entry_db = EntryDB::EntryDatabase.new
      @headers.each do |key, value|
        next unless key == "Entry"
        entry = value.split(',', 2)
        if entry.length != 2
          send_response(400) # Bad Request
          return nil
        end
        entry_db.add(entry[0].strip(), entry[1].strip())
      end
      return entry_db
    end

    def get_event(key = "Event")
      event = @headers.reverse.assoc(key)&.at(1)
      if event.nil?
        send_response(400) # Bad Request
        log_error('Event: header field not found')
        return nil
      end
      buf = [event]
      (0..7).each do |i|
        key = "Reference#{i}"
        value = @headers.reverse.assoc(key)&.at(1)
        buf << value
      end
      return buf
    end

    def get_sender
      sender = @headers.reverse.assoc('Sender')&.at(1)
      if sender.nil?
        send_response(400) # Bad Request
        log_error('Sender: header field not found')
        return nil
      end
      return sender
    end

    def get_handle
      path = @headers.assoc("HWnd")&.at(1)
      if path.nil?
        send_response(400) # Bad Request
        log_error('HWnd: header field not found')
        return nil
      end
      handle = Socket.new(Socket::AF_UNIX, Socket::SOCK_STREAM)
      begin
        handle.connect(path)
      rescue SystemCallError
        handle = nil # discard socket object
        Logging::Logging.error('cannot open Unix socket: ' + path)
      end
      if handle.nil?
        send_response(400) # Bad Request
        log_error('Invalid HWnd: header field')
        return nil
      end
      return handle
    end

    def get_charset
      @headers.reverse.assoc('Charset')&.at(1) || 'UTF-8' # XXX
    end

    def check_decoder
      charset = get_charset
      return true if Encoding.name_list.include?(charset)
      send_response(420, :data => 'Refuse (unsupported charset)')
      log_error("Unsupported charset #{charset}")
      return false
    end

    def get_options
      show_sstp_marker = use_translator = true
      options = (@headers.reverse.assoc("Option")&.at(1) || "").split(",", 0)
      options.each do |option|
        option = option.strip()
        case option
        when 'nodescript'
          show_sstp_marker = false if local_request()
        when 'notranslate'
          use_translator = false
        end
      end
      return show_sstp_marker, use_translator
    end

    def local_request
      return true if @fp.is_a?(UNIXSocket)
      sock_domain, remote_port, remote_hostname, remote_ip = @fp.peeraddr
      remote_ip == "127.0.0.1"
    end

    # EXECUTE
    def do_EXECUTE_1_0
      handle_command()
    end

    def do_EXECUTE_1_2
      handle_command()
    end

    def do_EXECUTE_1_3
      unless local_request()
        sock_domain, remote_port, remote_hostname, remote_ip = @fp.peeraddr
        send_response(420)
        log_error("Unauthorized EXECUTE/1.3 request from #{remote_hostname}")
        return
      end
      handle_command()
    end

    def do_EXECUTE_1_4
      handle_command()
    end

    def shutdown(how)
      @fp.shutdown(how)
    end

    def write(data)
      @fp.write(data)
    end

    def handle_command
      return unless check_decoder()
      sender = get_sender()
      return if sender.nil?
      command, *args = get_event("Command")
      charset = get_charset
      charset = charset.to_s
      case command
      when nil
        return
      when 'getname'
        send_response(200)
        name = @server.handle_request(:GET, :get_ghost_name)
        @fp.write(name.encode(
                    charset, :invalid => :replace, :undef => :replace))
        @fp.write("\r\n")
        @fp.write("\r\n")
      when 'getversion'
        send_response(200)
        @fp.write("ninix-kagari ")
        @fp.write(Version.VERSION.encode(
                    charset, :invalid => :replace, :undef => :replace))
        @fp.write("\r\n")
        @fp.write("\r\n")
      when 'quiet'
        send_response(200)
        @server.handle_request(:GET, :keep_silence, true)
      when 'restore'
        send_response(200)
        @server.handle_request(:GET, :keep_silence, false)
      when 'getnames'
        send_response(200)
        for name in @server.handle_request(:GET, :get_ghost_names)
          @fp.write(name.encode(
                      charset, :invalid => :replace, :undef => :replace))
          @fp.write("\r\n")
        end
        @fp.write("\r\n")
      when 'checkqueue'
        send_response(200)
        count, total = @server.handle_request(
                 :GET, :check_request_queue, sender)
        @fp.write(count.to_s.encode(
                    charset, :invalid => :replace, :undef => :replace))
        @fp.write("\r\n")
        @fp.write(total.to_s.encode(
                    charset, :invalid => :replace, :undef => :replace))
        @fp.write("\r\n")
        @fp.write("\r\n")
      when 'GetBalloonSize'
        x, y = @server.handle_request(:GET, :get_balloon_size, args[0].to_i)
        send_response(200)
        @fp.write("#{x},#{y}")
        @fp.write("\r\n")
        @fp.write("\r\n")
      when 'SetBalloonPosition'
        @server.handle_request(:GET, :set_balloon_position, *args.map do |v|
          v.to_i
        end.take(3))
        send_response(204)
      else
        send_response(501) # Not Implemented
        log_error("Not Implemented (#{command})")
      end
    end

    def do_COMMUNICATE_1_1
      return unless check_decoder()
      sender = get_sender()
      return if sender.nil?
      sentence = get_sentence()
      return if sentence.nil?
      send_response(200) # OK
      @server.handle_request(
        :GET, :enqueue_event, 'OnCommunicate', sender, sentence)
      return
    end

    def get_sentence
      sentence = @headers.reverse.assoc("Sentence")&.at(1)
      if sentence.nil?
        send_response(400) # Bad Request
        log_error('Sentence: header field not found')
        return nil
      end
      return sentence
    end
  end

  class NilRequestHandler < SSTPRequestHandler
    def initialize(server, fp)
      super(server, fp, 'unused', '1.0')
    end

    def parse_request(fp)
      send_error(400, :message => "Bad Request")
      return false
    end
  end

  class HTTPRequestHandler < SSTPRequestHandler
    def initialize(server, fp, method, path, version)
      @server = server
      @fp = fp
      @method = method
      @path = path
      @http_version = version
    end

    def parse_request(fp)
      return if fp.nil?
      header = {}
      loop do
        line = fp.gets
        break if line.strip.empty?
        line = line.chomp
        next unless line.include?(':')
        k, v = line.split(':', 2)
        header[k.strip] = v.strip
      end
      if header.include?('Content-Length') and header['Content-Length'].to_i > 0
        length = header['Content-Length'].to_i
        content = fp.read(length)
      end
      unless @path == '/api/sstp/v1'
        send_response(0, message: "", http_code: 404, http_message: 'Not Found')
        return false
      end
      if @method == 'GET'
        endpoint
        return false
      end
      unless @method == 'POST'
        send_response(0, message: "", http_code: 400, http_message: 'Bad Request')
        return false
      end
      sio = StringIO.new(content, 'r')
      line = sio.gets
      line = line.chomp
      re_req_sstp_syntax = Regexp.new('\A([A-Z]+) SSTP/([0-9]\\.[0-9])\z')
      match = re_req_sstp_syntax.match(line)
      if match.nil?
        send_response(400, message: "Bad Request")
        return false
      end
      @command, @version = match[1, 2]
      super(sio)
    end

    def send_response(code, message: nil, http_code: 200, http_message: 'OK')
      unless http_code == 200
        @fp.write("HTTP/#{@http_version} #{http_code} #{http_message}\r\n\r\n")
      end
      content = response(code)
      @fp.write("HTTP/#{@http_version} #{http_code} #{http_message}\r\n")
      @fp.write("Content-Length: #{content.bytesize}\r\n")
      @fp.write("\r\n")
      return super(code, message: message)
    end

    def endpoint
      html = '<html><body><form method="post" action="/api/sstp/v1" enctype="text/plain"><input type="hidden" name="__dummy__sstp__form__flag__" value="1"><textarea name="sstp" rows="15" cols="60"></textarea><br><input type="submit"></form></body></html>'
      @fp.write("200 OK HTTP/1.1\r\nContent-Length: #{html.bytesize}\r\n\r\n")
      @fp.write(html)
    end
  end

  class RequestHandler
    def self.create_with_http_support(line, server, fp)
      return NilRequestHandler.new(server, fp) if line.nil?
      line = line.encode('UTF-8', :invalid => :replace, :undef => :replace).chomp
      re_req_http_syntax = Regexp.new('\A([A-Z]+) ([^ ]+) HTTP/([0-9]\\.[0-9])\z')
      match = re_req_http_syntax.match(line)
      unless match.nil?
        method, path, version = match[1, 3]
        return HTTPRequestHandler.new(server, fp, method, path, version)
      end
      return create(line, server, fp)
    end

    def self.create(line, server, fp, uuid, ayu_uuid)
      return NilRequestHandler.new(server, fp) if line.nil?
      line = line.encode('UTF-8', :invalid => :replace, :undef => :replace).chomp
      re_req_sstp_syntax = Regexp.new('\A([A-Z]+) SSTP/([0-9]\\.[0-9])\z')
      match = re_req_sstp_syntax.match(line)
      unless match.nil?
        command, version = match[1, 2]
        return SSTPRequestHandler.new(server, fp, command, version, uuid, ayu_uuid)
      end
      return NilRequestHandler.new(server, fp)
    end
  end
end
