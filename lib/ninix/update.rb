# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2017 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "net/http"
require "uri"
require "fileutils"
require "digest/md5"

require_relative "home"
require_relative "logging"

module Update

  class NetworkUpdate

    BACKUPSUFFIX = '.BACKUP'

    def initialize
      @parent = nil
      @event_queue = []
      @state = nil
      @backups = []
      @newfiles = []
      @newdirs = []
    end

    def set_responsible(parent)
      @parent = parent
    end

    def state
      @state
    end

    def is_active
      return (not @state.nil?)
    end

    def enqueue_event(event,
                      ref0: nil, ref1: nil, ref2: nil, ref3: nil,
                      ref4: nil, ref5: nil, ref6: nil, ref7: nil)
      @event_queue << [event, ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7]
    end

    def get_event
      return nil if @event_queue.empty?
      return @event_queue.shift
    end

    def has_events
      return (not @event_queue.empty?)
    end

    def start(homeurl, ghostdir, timeout: 60)
      begin
        url = URI.parse(homeurl)
      rescue
        enqueue_event('OnUpdateFailure',
                      :ref0 => 'bad home URL',
                      :ref1 => '',
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
        @state = nil
        return
      end
      unless url.scheme == 'http'
        enqueue_event('OnUpdateFailure',
                      :ref0 => 'bad home URL',
                      :ref1 => '',
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
        @state = nil
        return
      end        
      @host = url.host
      @port = url.port
      @path = url.path
      @ghostdir = ghostdir
      @timeout = timeout
      @redirect_limit = 5
      @state = 0
    end

    def interrupt
      @event_queue = []
      @parent.handel_request(
                             'NOTIFY', 'enqueue_event',
                             'OnUpdateFailure', 'artificial', '', '',
                             'ghost') # XXX
      @state = nil
      stop(:revert => true)
    end

    def stop(revert: false)
      @buffer = []
      if revert
        for path in @backups
          File.rename(path, path[0, path.length - BACKUPSUFFIX.length]) if File.file?(path)
        end
        for path in @newfiles
          File.delete(path) if File.file?(path)
        end
        for path in @newdirs
          FileUtils.remove_entry_secure(path) if File.directory?(path)
        end
        @backups = []
      end
      @newfiles = []
      @newdirs = []
    end

    def clean_up
      for path in @backups
        File.delete(path) if File.file?(path)
      end
      @backups = []
    end

    def reset_timeout
      @timestamp = Time.now.to_i
    end

    def check_timeout
      return (Time.now.to_i - @timestamp) > @timeout
    end

    def run
      len_state = 5
      len_pre = 5
      if @state.nil? or \
        @parent.handle_request('GET', 'check_event_queue')
        return false
      elsif @state == 0
        start_updates()
      elsif @state == 1
        connect()
      elsif @state == 2
        wait_response()
      elsif @state == 3
        get_content()
      elsif @state == 4
        @schedule = make_schedule()
        if @schedule.nil?
          return false
        end
        @final_state = (@schedule.length * len_state + len_pre)
      elsif @state == @final_state
        end_updates()
      elsif (@state - len_pre) % len_state == 0
        filename, checksum = @schedule[0]
        Logging::Logging.info('UPDATE: ' + filename + ' ' + checksum)
        download(File.join(@path, URI.escape(filename)),
                 :event => true)
      elsif (@state - len_pre) % len_state == 1
        connect()
      elsif (@state - len_pre) % len_state == 2
        wait_response()
      elsif (@state - len_pre) % len_state == 3
        get_content()
      elsif (@state - len_pre) % len_state == 4
        filename, checksum = @schedule.shift
        update_file(filename, checksum)
      end
      return true
    end

    def start_updates
      enqueue_event('OnUpdateBegin',
                    :ref0 => @parent.handle_request('GET', 'get_name', :default => ''),
                    :ref1 => @path,
                    :ref2 => '',
                    :ref3 => 'ghost') # XXX
      download(File.join(@path, 'updates2.dau'))
    end

    def download(locator, event: false)
      @locator = locator # don't use URI.escape here
      @http = Net::HTTP.new(@host, @port)
      if event
        enqueue_event('OnUpdate.OnDownloadBegin',
                      :ref0 => File.basename(locator),
                      :ref1 => @file_number,
                      :ref2 => @num_files,
                      :ref3 => 'ghost') # XXX
      end
      @state += 1
      reset_timeout()
    end

    def connect
      @response = @http.get(@locator)
      @state += 1
      reset_timeout()
    end

    def wait_response
      if check_timeout()
        enqueue_event('OnUpdateFailure',
                      :ref0 => 'timeout',
                      :ref1 => '',
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
        @state = nil
        stop(:revert => true)
        return
      end
      code = @response.code.to_i
      message = @response.message
      if code == 200
        #pass
      elsif code == 302
        if redirect()
          return
        else
          enqueue_event('OnUpdateFailure',
                        :ref0 => 'http redirect error',
                        :ref1 => '',
                        :ref2 => '',
                        :ref3 => 'ghost') # XXX
          @state = nil
          return
        end
      elsif @state == 2 # updates2.dau
        enqueue_event('OnUpdateFailure',
                      :ref0 => code.to_s,
                      :ref1 => 'updates2.dau',
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
        @state = nil
        return
      else
        filename, checksum = @schedule.shift
        Logging::Logging.error(
          "failed to download #{filename} (#{code} #{message})")
        @file_number += 1
        @state += 3
        return
      end
      @buffer = []
      @size = @response.content_length
      @state += 1
      reset_timeout()
      @redirect_limit = 5 # reset
    end

    def redirect
      @redirect_limit -= 1
      return false if @redirect_limit < 0
      location = @response['location']
      return false if location.nil?
      begin
        url = URI.parse(location)
      rescue
        return false
      end
      return false if url.scheme != 'http'
      return false if url.path.empty?
      Logging::Logging.info("redirected to #{location}")
      @http.finish if @http.started?
      @host = url.host
      @port = url.port
      @path = url.path
      @state -= 2
      download(@path)
      return true
    end

    def get_content
      data = @response.read_body
      if data.empty?
        if check_timeout()
          enqueue_event('OnUpdateFailure',
                        :ref0 => 'timeout',
                        :ref1 => '',
                        :ref2 => '',
                        :ref3 => 'ghost') # XXX
          @state = nil
          stop(:revert => true)
          return
        elsif data.nil?
          return
        end
      elsif @response.code != '200'
        enqueue_event('OnUpdateFailure',
                      :ref0 => 'data retrieval failed',
                      :ref1 => '',
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
        @state = nil
        stop(:revert => true)
        return
      end
      @buffer = data unless data.empty?
      if @size.nil? or data.length < @size
        enqueue_event('OnUpdateFailure',
                      :ref0 => 'timeout',
                      :ref1 => '',
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
        @state = nil
        stop(:revert => true)
        return
      end
      @state += 1
    end

    def adjust_path(filename)
      filename = Home.get_normalized_path(filename)
      if ['install.txt',
          'delete.txt',
          'readme.txt',
          'thumbnail.png'].include?(filename) or File.dirname(filename) != "."
        return filename
      end
      return File.join('ghost', 'master', filename)
    end

    def make_schedule
      schedule = parse_updates2_dau()
      unless schedule.nil?
        @num_files = (schedule.length - 1)
        @file_number = 0
        list = []
        for x, y in schedule
          list << x
        end
        update_list = list.join(',')
        if @num_files >= 0
          enqueue_event('OnUpdateReady',
                        :ref0 => @num_files,
                        :ref1 => update_list,
                        :ref2 => '',
                        :ref3 => 'ghost') # XXX
        end
        @state += 1
      end
      return schedule
    end

    def get_schedule
      @schedule
    end

    def parse_updates2_dau
      schedule = []
      for line in @buffer.split("\n", 0)
        begin
          filename, checksum, newline = line.split("\001", 4)
        rescue
          enqueue_event('OnUpdateFailure',
                        :ref0 => 'broken updates2.dau',
                        :ref1 => 'updates2.dau',
                        :ref2 => '',
                        :ref3 => 'ghost') # XXX
          @state = nil
          return nil
        end
        next if filename == ""
        unless checksum.nil?
          checksum = checksum.encode('ascii', :invalid => :replace, :undef => :replace) # XXX
        end
        path = File.join(@ghostdir, adjust_path(filename))
        begin
          f = open(path, 'rb')
          data = f.read()
          f.close()
        rescue # IOError # does not exist or broken
          data = nil
        end
        unless data.nil?
          next if checksum == Digest::MD5.hexdigest(data)
        end
        schedule << [filename, checksum]
      end
      @updated_files = []
      return schedule
    end

    def update_file(filename, checksum)
      enqueue_event('OnUpdate.OnMD5CompareBegin',
                    :ref0 => filename,
                    :ref1 => '',
                    :ref2 => '',
                    :ref3 => 'ghost') # XXX
      data = @buffer
      digest = Digest::MD5.hexdigest(data)
      if digest == checksum
        path = File.join(@ghostdir, adjust_path(filename))
        subdir = File.dirname(path)
        unless Dir.exists?(subdir)
          subroot = subdir
          while true
            head, tail = File.split(subroot)
            if Dir.exists?(head)
              break
            else
              subroot = head
            end
          end
          @newdirs << subroot
          begin
            FileUtils.mkdir_p(subdir)
          rescue SystemCallError
            enqueue_event('OnUpdateFailure',
                          :ref0 => ["can't mkdir ", subdir].join(''),
                          :ref1 => path,
                          :ref2 => '',
                          :ref3 => 'ghost') # XXX
            @state = nil
            stop(:revert => true)
            return
          end
        end
        if File.exists?(path)
          if File.file?(path)
            backup = [path, BACKUPSUFFIX].join('')
            File.rename(path, backup)
            @backups << backup
          end
        else
          @newfiles << path
        end
        begin
          f = open(path, 'wb')
          begin
            f.write(data)
          rescue # IOError, SystemCallError
            enqueue_event('OnUpdateFailure',
                          :ref0 => ["can't write ", File.basename(path)].join(''),
                          :ref1 => path,
                          :ref2 => '',
                          :ref3 => 'ghost') # XXX
            @state = nil
            stop(:revert => true)
            return
          end
        rescue # IOError
          enqueue_event('OnUpdateFailure',
                        :ref0 => ["can't open ", File.basename(path)].join(''),
                        :ref1 => path,
                        :ref2 => '',
                        :ref3 => 'ghost') # XXX
          @state = nil
          stop(:revert => true)
          return
        end
        @updated_files << filename
        event = 'OnUpdate.OnMD5CompareComplete'
      else
        event = 'OnUpdate.OnMD5CompareFailure'
        enqueue_event(event,
                      :ref0 => filename,
                      :ref1 => checksum,
                      :ref2 => digest,
                      :ref3 => 'ghost') # XXX
        @state = nil
        stop(:revert => true)
        return
      end
      enqueue_event(event,
                    :ref0 => filename,
                    :ref1 => checksum,
                    :ref2 => digest)
      @file_number += 1
      @state += 1
    end

    def end_updates
      filelist = parse_delete_txt()
      unless filelist.empty?
        for filename in filelist
          path = File.join(@ghostdir, filename)
          if File.exists?(path) and File.file?(path)
            begin
              File.unlink(path)
              Logging::Logging.info('deleted ' + path)
            rescue SystemCallError => e
              Logging::Logging.error(e.message)
            end
          end
        end
      end
      list = []
      for x in @updated_files
        list << x
      end
      update_list = list.join(',')
      if update_list.empty?
        enqueue_event('OnUpdateComplete',
                      :ref0 => 'none',
                      :ref1 => '',
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
      else
        enqueue_event('OnUpdateComplete',
                      :ref0 => 'changed',
                      :ref1 => update_list,
                      :ref2 => '',
                      :ref3 => 'ghost') # XXX
      end
      @state = nil
      stop()
    end

    def parse_delete_txt
      filelist = []
      begin
        f = open(File.join(@ghostdir, 'delete.txt'), 'rb')
        for line in f
          line = line.strip()
          next if line.empty?
          filename = line
          filelist << Home.get_normalized_path(filename)
        end
      rescue # IOError
        return nil
      end
      return filelist
    end
  end
end
