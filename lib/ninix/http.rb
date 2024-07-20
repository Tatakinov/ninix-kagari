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
      @timeout = 60
      @threads = []
    end

    def timeout=(timeout)
      if timeout > 0 and timeout <= 300
        @timeout = timeout
      end
    end

    def enqueue(url, query: nil, method: 'get', blocking: nil, redirect: 5)
      return [:TYPE_ERROR, 'too many redirect'] if redirect < 0
      queue = Thread::Queue.new
      thread = Thread.new(@timeout) do |timeout|
        begin
          uri = URI.parse(url)
        rescue
          return [:TYPE_ERROR, 'bad URL']
        end
        host = uri.host
        port = uri.port
        scheme = uri.scheme
        path = uri.path
        if method == 'get' or method == 'head'
          path = path + '?' + query unless query.nil?
        end
        unless scheme == 'http' or scheme == 'https'
          queue.push([:TYPE_ERROR, 'invalid scheme'])
        end
        client = Net::HTTP.new(uri.host, uri.port)
        client.use_ssl=(true) if scheme == 'https'
        client.read_timeout=(@timeout)
        begin
          case method
          when 'get', 'head', 'delete'
            res = client.method(method).call(path)
          when 'post', 'put'
            if query.nil?
              Logging::Logging.debug('no query found in post/put')
            else
              res = client.method(method).call(path, query)
            end
          else
            # unreachable
          end
        rescue
          queue.push([:TYPE_ERROR, 'timeout'])
        end
        case res.code
        when '200'
          queue.push([:TYPE_DATA, res.body])
        when '301'
          if res['location'].nil?
            queue.push([:TYPE_ERROR, 'no location'])
          else
            queue.push(enqueue(res['location'], blocking: true, redirect: redirect - 1))
          end
        else
          queue.push([:TYPE_ERROR, res.code])
        end
      end
      if blocking
        thread.join
        return queue.pop
      else
        @threads << [thread, queue]
        return nil
      end
    end

    def run
      @threads.size.times do |i|
        thread, queue = @threads[i]
        unless thread.alive?
          @threads.delete_at(i)
          thread.join
          return queue.pop
        end
      end
      return nil
    end

  end
end
