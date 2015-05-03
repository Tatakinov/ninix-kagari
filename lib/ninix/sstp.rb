# -*- coding: utf-8 -*-
#
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

require "ninix/entry_db"
require "ninix/script"
require "ninix/version"
require "ninix/sstplib"


module SSTP

  class SSTPServer < SSTPLib::AsynchronousSSTPServer

    def initialize(address)
      @parent = nil
      super(address)
      @request_handler = nil
    end

#    def shutdown_request(request)
#      if @request_handler != nil
#        # XXX: send_* methods can be called from outside of the handler
#        pass # keep alive
#      else
#        super(request) #AsynchronousSSTPServer.shutdown_request(self, request)
#      end
#    end
    
    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist, **argdict)
      if @parent != nil
        @parent.handle_request(event_type, event, *arglist, **argdict)
      end
    end
    
    def set_request_handler(handler) ## FIXME
      @request_handler = handler
    end

    def has_request_handler
      if @request_handler != nil
        return true
      else
        return false
      end
    end

    def send_response(code, data: nil)
      begin
        @request_handler.send_response(code)
        if data != nil
#          @request_handler.wfile.write(data)
          @request_handler.write(data) # FIXME
        end
#        @request_handler.force_finish()
        @request_handler.shutdown(Socket::SHUT_WR) # XXX
      rescue #except IOError:
        #pass
      end
      @request_handler = nil
    end

    def send_answer(value)
      charset = @request_handler.get_charset
      answer = [value.encode(charset, :invalid => :replace), "\r\n\r\n"].join("")
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
      socket.close()
    end
  end
  
  class SSTPRequestHandler < SSTPLib::BaseSSTPRequestHandler

    def handle(line)
      if not @server.handle_request('GET', 'get_sakura_cantalk')
        @error = @version = nil
        if not parse_request(line)
          return
        end
        send_error(512)
      else
        super(line)
      end
    end

#    def force_finish
#      BaseSSTPRequestHandler.finish(self)
#    end

#    def finish
#      if @server.request_handler == nil
#        BaseSSTPRequestHandler.finish(self)
#      end
#    end

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
      if not check_decoder()
        return
      end
      sender = get_sender()
      if sender == nil
        return
      end
      if version == 1.3
        handle = get_handle()
        if handle == nil
          return
        end
      else
        handle = nil
      end
      script_odict = get_script_odict()
      if script_odict == nil
        return
      end
      if [1.0, 1.1].include?(version)
        entry_db = nil
      elsif [1.2, 1.3, 1.4].include?(version)
        entry_db = get_entry_db()
        if entry_db == nil
          return
        end
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

    def handle_notify(version)
      if not check_decoder()
        return
      end
      sender = get_sender()
      if sender == nil
        return
      end
      event = get_event()
      if event == nil
        return
      end
      if version == 1.0
        entry_db = nil
      elsif version == 1.1
        script_odict = get_script_odict()
        if script_odict == nil
          return
        end
        entry_db = get_entry_db()
        if entry_db == nil
          return
        end
      end
      enqueue_request(sender, event, nil, script_odict, entry_db)
    end

    def enqueue_request(sender, event, handle, script_odict, entry_db)
      sock_domain, remote_port, remote_hostname, remote_ip = @fp.peeraddr
      address = remote_hostname # XXX
      if entry_db == nil or entry_db.is_empty()
        send_response(200) # OK
        show_sstp_marker, use_translator = get_options()
        @server.handle_request(
          'NOTIFY', 'enqueue_request',
          event, script_odict, sender, handle,
          address, show_sstp_marker, use_translator,
          entry_db, nil)
      elsif @server.has_request_handler
        send_response(409) # Conflict
      else
        show_sstp_marker, use_translator = get_options()
        @server.handle_request(
          'NOTIFY', 'enqueue_request',
          event, script_odict, sender, handle,
          address, show_sstp_marker, use_translator,
          entry_db, @server)
        @server.set_request_handler(self) # keep alive
      end
    end

    PROHIBITED_TAGS = ['\j', '\-', '\+', '\_+', '\!', '\8', '\_v', '\C']

    def check_script(script)
      if not local_request()
        parser = Script::Parser.new
        nodes = []
        while 1
          begin
            nodes.concat(parser.parse(script))
          rescue #except ninix.script.ParserError as e:
            done, script = e ## FIXME
            nodes.concat(done)
          else
            break
          end
        end
        for node in nodes
          if node[0] == Script::SCRIPT_TAG and \
            PROHIBITED_TAGS.include?(node[1])
            send_response(400) # Bad Request
            log_error('Script: tag ' + node[1].to_s + ' not allowed')
            return true
          end
        end
      end
      return false
    end

    def get_script_odict
      script_odict = {} #OrderedDict()
      if_ghost = nil
      for item in @headers
        name, value = item
        if name != 'Script'
          if name == ('IfGhost')
            if_ghost = value
          else
            if_ghost = nil
          end
          next
        end
        script = value.to_s
        if check_script(script)
          return
        end
        if if_ghost == nil
          script_odict[''] = script
        else
          script_odict[if_ghost] = script
        end
        if_ghost = nil
      end
      return script_odict
    end

    def get_entry_db
      entry_db = EntryDB::EntryDatabase.new
      for item in @headers
        key, value = item
        if key == "Entry"
          entry = value.split(',', 2)
          if entry.length != 2
            send_response(400) # Bad Request
            return nil
          end
          entry_db.add(entry[0].strip(), entry[1].strip())
        end
      end
      return entry_db
    end

    def get_event
      if @headers.assoc("Event") != nil
        event = @headers.reverse.assoc("Event")[1]
      else
        event = nil
      end
      if event == nil
        send_response(400) # Bad Request
        log_error('Event: header field not found')
        return nil
      end
      buf = [event]
      for i in 0..7
        key = ['Reference', i.to_s].join("")
        if @headers.assoc(key) != nil
          value = @headers.reverse.assoc(key)[1]
        else
          value = nil
        end
        buf << value
      end
      return buf
    end

    def get_sender
      if @headers.assoc('Sender') != nil
        sender = @headers.reverse.assoc('Sender')[1]
      else
        sender = nil
      end
      if sender == nil
        send_response(400) # Bad Request
        log_error('Sender: header field not found')
        return nil
      end
      return sender
    end

    def get_handle
      if @headers.assoc("HWnd") != nil
        path = @headers.assoc("HWnd")
      else
        path = nil
      end
      if path == nil
        send_response(400) # Bad Request
        log_error('HWnd: header field not found')
        return nil
      end
#      handle = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
      handle = nil # FIXME
#      begin
#        handle.connect(path)
#      rescue #except socket.error:
#        handle = nil # discard socket object
#        logging.error('cannot open Unix socket: {0}'.format(path))
#      end
#      if handle == nil
#        send_response(400) # Bad Request
#        log_error('Invalid HWnd: header field')
#        return nil
#      end
      return handle
    end

    def get_charset
      if @headers.assoc('Charset') != nil
        charset = @headers.reverse.assoc('Charset')[1] # XXX
      else
        charset = 'Shift_JIS'
      end
      return charset
    end

    def check_decoder
      if @headers.assoc('Charset') != nil
        charset = @headers.reverse.assoc('Charset')[1] # XXX
      else
        charset = 'Shift_JIS'
      end
      if not Encoding.name_list.include?(charset)
        send_response(420, :data => 'Refuse (unsupported charset)')
        log_error('Unsupported charset {0}'.format(repr(charset)))
      else
        return true
      end
      return false
    end

    def get_options
      show_sstp_marker = use_translator = true
      if @headers.assoc("Option") != nil
        options = @headers.reverse.assoc("Option")[1].split(",")
        for option in options
          option = option.strip()
          if option == 'nodescript' and local_request()
            show_sstp_marker = false
          elsif option == 'notranslate'
            use_translator = false
          end
        end
      end
      return show_sstp_marker, use_translator
    end

    def local_request
      sock_domain, remote_port, remote_hostname, remote_ip = @fp.peeraddr
      if remote_ip == "127.0.0.1"
        return true
      else
        return false
      end
    end

    # EXECUTE
    def do_EXECUTE_1_0
      handle_command()
    end

    def do_EXECUTE_1_2
      handle_command()
    end

    def do_EXECUTE_1_3
      if not local_request()
        sock_domain, remote_port, remote_hostname, remote_ip = @fp.peeraddr
        send_response(420)
        log_error(
          'Unauthorized EXECUTE/1.3 request from ' + remote_hostname)
        return
      end
      handle_command()
    end

    def shutdown(how)
      @fp.shutdown(how)
    end

    def write(data)
      @fp.write(data)
    end

    def handle_command
      if not check_decoder()
        return
      end
      sender = get_sender()
      if sender == nil
        return
      end
      command = get_command()
      if @headers.assoc('Charset') != nil
        charset = @headers.reverse.assoc('Charset')[1] # XXX
      else
        charset = 'Shift_JIS'
      end
      charset = charset.to_s
      if command == nil
        return
      elsif command == 'getname'
        send_response(200)
        name = @server.handle_request('GET', 'get_ghost_name')
        @fp.write([name.encode(charset, :invalid => :replace),
                   "\r\n"].join(""))
        @fp.write("\r\n")
      elsif command == 'getversion'
        send_response(200)
        @fp.write(['ninix-aya ',
                   Version.VERSION.encode(charset),
                   "\r\n"].join(""))
        @fp.write("\r\n")
      elsif command == 'quiet'
        send_response(200)
        @server.handle_request('NOTIFY', 'keep_silence', true)
      elsif command == 'restore'
        send_response(200)
        @server.handle_request('NOTIFY', 'keep_silence', false)
      elsif command == 'getnames'
        send_response(200)
        for name in @server.handle_request('GET', 'get_ghost_names')
          @fp.write(
            [name.encode(charset, :invalid => :replace), "\r\n"].join(""))
        end
        @fp.write("\r\n")
      elsif command == 'checkqueue'
        send_response(200)
        count, total = @server.handle_request(
                 'GET', 'check_request_queue', sender)
        @fp.write([count.to_s.encode(charset), "\r\n"].join(""))
        @fp.write([total.to_s.encode(charset), "\r\n"].join(""))
        @fp.write("\r\n")
      else
        send_response(501) # Not Implemented
        log_error('Not Implemented (' + command + ')')
      end
    end

    def get_command
      if @headers.assoc('Command')
        command = @headers.reverse.assoc('Command')[1]
      else
        command = nil
      end
      if command == nil
        send_response(400) # Bad Request
        log_error('Command: header field not found')
        return nil
      end
      return command.downcase
    end

    def do_COMMUNICATE_1_1
      if not check_decoder()
        return
      end
      sender = get_sender()
      if sender == nil
        return
      end
      sentence = get_sentence()
      if sentence == nil
        return
      end
      send_response(200) # OK
      @server.handle_request(
        'NOTIFY', 'enqueue_event', 'OnCommunicate', sender, sentence)
      return
    end

    def get_sentence
      if @headers.assoc("Sentence")
        sentence = @headers.reverse.assoc("Sentence")[1]
      else
        sentence = nil
      end
      if sentence == nil
        send_response(400) # Bad Request
        log_error('Sentence: header field not found')
        return nil
      end
      return sentence
    end
  end
end
