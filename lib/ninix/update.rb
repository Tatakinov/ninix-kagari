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

require "net/http"
require "uri"
require "fileutils"
require "digest/md5"

require "ninix/home"

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
      return @state
    end

    def is_active
      return @state != nil
    end

    def enqueue_event(event,
                      ref0=nil, ref1=nil, ref2=nil, ref3=nil,
                      ref4=nil, ref5=nil, ref6=nil, ref7=nil)
      @event_queue << [event, ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7]
    end

    def get_event
      if @event_queue.empty?
        return nil
      else
        return @event_queue.shift
      end
    end

    def has_events
      if @event_queue.empty?
        return false
      else
        return true
      end
    end

    def start(homeurl, ghostdir, timeout: 60)
      begin
        url = URI.parse(homeurl)
      rescue
        enqueue_event('OnUpdateFailure', 'bad home URL', '', '',
                      'ghost') # XXX
        @state = nil
        return
      end
      if not url.scheme == 'http'
        enqueue_event('OnUpdateFailure', 'bad home URL', '', '',
                      'ghost') # XXX
        @state = nil
        return
      end        
      @host = url.host
      @port = url.port
      @path = url.path
      @ghostdir = ghostdir
      @timeout = timeout
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
          if File.file?(path)
            File.rename(path, path[0, path.length - BACKUPSUFFIX.length])
          end
        end
        for path in @newfiles
          if File.file?(path)
            File.delete(path)
          end
        end
        for path in @newdirs
          if File.directory?(path)
            FileUtils.remove_entry_secure(path)
          end
        end
        @backups = []
      end
      @newfiles = []
      @newdirs = []
    end

    def clean_up
      for path in @backups
        if File.file?(path)
          File.delete(path)
        end
      end
      @backups = []
    end

    def reset_timeout
      @timestamp = Time.now.to_i
    end

    def check_timeout
      return Time.now.to_i - @timestamp > @timeout
    end

    def run
      len_state = 5
      len_pre = 5
      if @state == nil or \
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
        if @schedule == nil
          return false
        end
        @final_state = @schedule.length * len_state + len_pre
      elsif @state == @final_state
        end_updates()
      elsif (@state - len_pre) % len_state == 0
        filename, checksum = @schedule[0]
#        logging.info('UPDATE: {0} {1}'.format(filename, checksum))
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
      enqueue_event(
                    'OnUpdateBegin',
                    @parent.handle_request('GET', 'get_name', ''),
                    @path, '',
                    'ghost') # XXX
      download(File.join(@path, 'updates2.dau'))
    end

    def download(locator, event: false)
      @locator = URI.escape(locator)
      @http = Net::HTTP.new(@host, @port)
      if event
        enqueue_event('OnUpdate.OnDownloadBegin',
                      File.basename(locator),
                      @file_number, @num_files,
                      'ghost') # XXX
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
        enqueue_event('OnUpdateFailure', 'timeout', '', '',
                      'ghost') # XXX
        @state = nil
        stop(:revert => true)
        return
      end
      code = @response.code.to_i
      message = @response.message
      if code == 200
        #pass
      elsif code == 302 and redirect()
        return
      elsif @state == 2 # updates2.dau
        enqueue_event(
                      'OnUpdateFailure', code.to_s, 'updates2.dau', '',
                      'ghost') # XXX
        @state = nil
        return
      else
        filename, checksum = @schedule.pop(0)
#        logging.error(
#                      'failed to download {0} ({1:d} {2})'.format(
#                                                                  filename, code, message))
        @file_number += 1
        @state += 3
        return
      end
      @buffer = []
      size = @response.content_length
      if size == nil
        @size = nil
      else
        @size = size
      end
      @state += 1
      reset_timeout()
    end

    def redirect
      location = @response.getheader('location', nil)
      if location == nil
        return false
      end
      begin
        url = URI.parse(location)
      rescue
        return false
      end
      if url.scheme != 'http'
        return false
      end
#      logging.info('redirected to {0}'.format(location))
      @http.close()
      @host = url.host
      @port = url.port
      @path = url.path.dirname
      @state -= 2
      download(url[2])
      return true
    end

    def get_content
      data = @response.read_body
      if data.empty?
        if check_timeout()
          enqueue_event('OnUpdateFailure', 'timeout', '', '',
                        'ghost') # XXX
          @state = nil
          stop(:revert => true)
          return
        elsif data == nil
          return
        end
      elsif @response.code != '200'
        enqueue_event(
                      'OnUpdateFailure', 'data retrieval failed', '', '',
                      'ghost') # XXX
        @state = nil
        stop(:revert => true)
        return
      end
      if not data.empty?
        @buffer = data
      end
      if @size == nil or data.length < @size
        enqueue_event('OnUpdateFailure', 'timeout', '', '',
                      'ghost') # XXX
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
      if schedule != nil
        @num_files = schedule.length - 1
        @file_number = 0
        list = []
        for x, y in schedule
          list << x
        end
        update_list = list.join(',')
        if @num_files >= 0
          enqueue_event(
                        'OnUpdateReady', @num_files, update_list, '',
                        'ghost') # XXX
        end
        @state += 1
      end
      return schedule
    end

    def get_schedule
      return @schedule
    end

    def parse_updates2_dau
      schedule = []
      for line in @buffer.split("\n")
        begin
          filename, checksum, newline = line.split("\001", 4)
        rescue #except ValueError:
          enqueue_event('OnUpdateFailure', 'broken updates2.dau',
                        'updates2.dau', '',
                        'ghost') # XXX
          @state = nil
          return nil
        end
        if filename == ""
          next
        end
        checksum = checksum.encode('ascii') # XXX
        path = File.join(@ghostdir, adjust_path(filename))
        begin
          f = open(path, 'rb')
          data = f.read()
          f.close()
        rescue #except IOError: # does not exist or broken
          data = nil
        end
        if data != nil
          if checksum == Digest::MD5.hexdigest(data)
            next
          end
        end
        schedule << [filename, checksum]
      end
      @updated_files = []
      return schedule
    end

    def update_file(filename, checksum)
      enqueue_event('OnUpdate.OnMD5CompareBegin',
                    filename, '', '',
                    'ghost') # XXX
      data = @buffer
      digest = Digest::MD5.hexdigest(data)
      if digest == checksum
        path = File.join(@ghostdir, adjust_path(filename))
        subdir = File.dirname(path)
        if not Dir.exists?(subdir)
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
          rescue #except OSError:
            enqueue_event(
                          'OnUpdateFailure',
                          ["can't mkdir ", subdir].join(''),
                          path, '',
                          'ghost') # XXX
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
          rescue #except IOError:
            enqueue_event(
                          'OnUpdateFailure',
                          ["can't write ", File.basename(path)].join(''),
                          path, '',
                          'ghost') # XXX
            @state = nil
            stop(:revert => true)
            return
          end
        rescue #except IOError:
          enqueue_event(
                        'OnUpdateFailure',
                        ["can't open ", File.basename(path)].join(''),
                        path, '',
                        'ghost') # XXX
          @state = nil
          stop(:revert => true)
          return
        end
        @updated_files << filename
        event = 'OnUpdate.OnMD5CompareComplete'
      else
        event = 'OnUpdate.OnMD5CompareFailure'
        enqueue_event(event, filename, checksum, digest,
                      'ghost') # XXX
        @state = nil
        stop(:revert => true)
        return
      end
      enqueue_event(event, filename, checksum, digest)
      @file_number += 1
      @state += 1
    end

    def end_updates
      filelist = parse_delete_txt()
      if not filelist.empty?
        for filename in filelist
          path = File.join(@ghostdir, filename)
          if File.exists?(path) and File.file?(path)
            begin
              File.unlink(path)
#              logging.info('deleted {0}'.format(path))
            rescue #except OSError as e:
#              logging.error(e)
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
        enqueue_event('OnUpdateComplete', 'none', '', '',
                      'ghost') # XXX
      else
        enqueue_event('OnUpdateComplete', 'changed', update_list, '',
                      'ghost') # XXX
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
          if line.empty?
            next
          end
          filename = line
          filelist << Home.get_normalized_path(filename)
        end
      rescue #except IOError:
        return nil
      end
      return filelist
    end
  end
end
