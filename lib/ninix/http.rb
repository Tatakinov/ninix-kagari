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

require "net/http"
require 'thread'
require "uri"

module Http
  class Client

    def initialize
      @parent = nil
      @queue = Thread::Queue.new
    end

    def set_responsible(parent)
      @parent = parent
    end

    def enqueue(url, url_param, output_param, redirect: 5, blocking: nil)
      if redirect < 0
        @queue.push([:TYPE_ERROR, 'too many redirect', url, url_param, output_param])
        return
      end

      thread = Thread.new(url, url_param, output_param, redirect) do |url, up, op, redirect|
        begin
          uri = URI.parse(url)
        rescue
          @queue.push([:TYPE_ERROR, 'bad URL', url, up, op])
          return nil
        end
        host = uri.host
        port = uri.port
        scheme = uri.scheme
        path = uri.path
        if up[:method] == 'get' or up[:method] == 'head'
          path = path + '?' + up[:query] unless up[:query].nil?
        end
        unless scheme == 'http' or scheme == 'https'
          queue.push([:TYPE_ERROR, 'invalid scheme', op])
        end
        client = Net::HTTP.new(uri.host, uri.port)
        client.use_ssl=(true) if scheme == 'https'
        client.read_timeout=(up[:timeout])
        begin
          case up[:method]
          when 'get', 'head', 'delete'
            res = client.method(up[:method]).call(path, up[:header])
          when 'post', 'put'
            if query.nil?
              Logging::Logging.debug('no query found in post/put')
            else
              res = client.method(up[:method]).call(path, query, up[:header])
            end
          else
            # unreachable
          end
        rescue => e
          @queue.push([:TYPE_ERROR, 'timeout', url, up, op])
          next
        end
        case res.code
        when '200'
          filename = File.basename(path)
          filename = '_' if filename == '.'
          filename = '__' if filename == '..'
          filename = 'index.html' if path.end_with?('/')
          if op[:filename].nil?
            op[:filename] = filename
          end
          @queue.push([:TYPE_DATA, res.body, url, up, op])
        when '301'
          if res['location'].nil?
            @queue.push([:TYPE_ERROR, 'no location', url, up, op])
          else
            enqueue(res['location'], up, op, blocking: true, redirect: redirect - 1)
          end
        else
          @queue.push([:TYPE_ERROR, res.code, url, up, op])
        end
      end
      if blocking
        thread.join
      end
    end

    def run
      __process(*@queue.pop) unless @queue.empty?
    end

    def __process(type, data, url, up, op)
      event = {}
      if op[:event]&.start_with?('On')
        event[:complete] = op[:event]
        event[:failure] = op[:event] + 'Failure'
      else
        event[:complete] = 'OnExecuteHTTPComplete'
        event[:failure] = 'OnExecuteHTTPFailure'
      end
      case type
      when :TYPE_ERROR
        if op[:event]
          @parent.handle_request(:GET, :enqueue_event, event[:failure], op[:method], op[:event], op[:url], nil, data)
        end
      when :TYPE_DATA
        # type != ERRORなのでURI.parseは必ず成功する
        filename = op[:filename]
        if filename == false
          # FIXME UTF-8 only
          d = data.force_encoding(Encoding::UTF_8)
          d = d.gsub(/\r\n/, "\x01")
          d = d.gsub(/\r/, "\x01")
          d = d.gsub(/\n/, "\x01")
          @parent.handle_request(:GET, :enqueue_event, event[:complete], op[:method], op[:event], op[:url], d, '200')
        else
          prefix = @parent.handle_request(:GET, :get_prefix)
          dir = File.join(prefix, 'ghost/master/var')
          unless Dir.exist?(dir)
            begin
              Dir.mkdir(dir)
            rescue
              Logging::Logging.info('cannot create ' + dir)
            end
          end
          path = File.join(dir, filename)
          begin
            File.open(path, 'w') do |fh|
              fh.write(data)
            end
          rescue
            Logging::Logging.info('cannot write ' + path)
          end
          if op[:event]
            # TODO mkdir error, write error
            @parent.handle_request(:GET, :enqueue_event, event[:complete], op[:method], op[:event], op[:url], path, '200')
          end
        end
      else
        # unreachable
      end
    end

  end
end
