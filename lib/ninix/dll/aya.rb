# -*- coding: utf-8 -*-
#
#  aya.rb - an aya.dll compatible Shiori module for ninix
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#
#

require_relative "../lock"
require_relative "../home"
require_relative "../logging"


module Aya

  class AyaError < StandardError # XXX
    #pass
  end

  def self.encrypt_char(char)
    c = char[0].ord
    j = 0
    while j < 3
      msb = (c & 0x80)
      c <<= 1
      c &= 0xff
      unless msb.zero?
        c |= 0x01
      else
        c &= 0xfe
      end
      j += 1
    end
    c ^= 0xd2
    return c.chr
  end

  def self.decrypt_char(char)
    c = char[0].ord
    c ^= 0xd2
    j = 0
    while j < 3
      lsb = (c & 0x01)
      c >>= 1
      unless lsb.zero?
        c |= 0x80
      else
        c &= 0x7f
      end
      j += 1
    end
    return c.chr
  end

  def self.decrypt_readline(f)
    line = ''
    while true
      c = f.read(1)
      break if c == ''
      line = [line, Aya.decrypt_char(c)].join('')
      if line.end_with?(10.chr) or \
        line.end_with?(0xda.chr)
        break
      end
    end
    return line
  end

  def self.find_not_quoted(line, token)
    position = 0
    while true
      pos_new = line.index(token, position)
      if pos_new.nil?
        pos_new = -1
        break
      elsif pos_new.zero?
        break
      end
      position = line.index('"', position)
      if not position.nil? and 0 <= position and position < pos_new
        position += 1
        while position < (line.length - 1)
          if line[position] == '"'
            position += 1
            break
          else
            position += 1
            next
          end
        end
      else
        break
      end
    end
    return pos_new
  end

  def self.find_comment(line)
    if line.start_with?("//")
      return 0, line.length
    end
    start = line.length # not line.length - 1
    end_ = -1
    for token in [" //", "\t//", "　//", "/*"]
      pos_new = Aya.find_not_quoted(line, token)
      if 0 <= pos_new and pos_new < start
        start = pos_new
        if token == '/*'
          end_ = Aya.find_not_quoted(line, '*/')
          if end_ >= 0
            end_ += 2
          end
        else
          end_ = line.length
        end
      end
    end
    if start == line.length
      start = -1
    end
    return start, end_
  end

  def self.get_aya_version(filelist)
    return 0 if filelist.empty?
    dic_files = filelist
    for filename in dic_files
      if filename.downcase.end_with?('_shiori3.dic') # XXX
        open(filename, 'rb', :encoding => 'CP932') do |f|
          for line in f
            begin
              line = line.encode("UTF-8", :invalid => :replace, :undef => :replace)
              v4 = line.index('for 文 version 4')
              v5 = line.index('for AYA5')
              if not v4.nil? and v4 > 0
                return 4
              elsif not v5.nil? and v5 > 0
                return 5
              end
            rescue
              return 5
            end
          end
        end
      end
    end
    return 3
  end

  def self.find_dict(aya_dir, f)
    comment = 0
    dic_files = []
    for line in f
      line = line.encode("UTF-8", :invalid => :replace, :undef => :replace)
      unless comment.zero?
        end_ = Aya.find_not_quoted(line, '*/')
        next if end_ < 0
        line = line[end_ + 2..-1]
        comment = 0
      end
      while true
        start, end_ = Aya.find_comment(line)
        break if start < 0
        line = "" if start.zero?
        if end_ < 0
          comment = 1
          line = line[0..start-1]
          break
        end
        line = [line[0..start-1], line[end_..-1]].join('')
      end
      line = line.strip()
      next if line.empty?
      next unless line.include?(',')
      key, value = line.split(',', 2)
      key.strip!
      value.strip!
      if key == 'dic'
        filename = Home.get_normalized_path(value)
        path = File.join(aya_dir, filename)
        dic_files << path
      end
    end
    return dic_files
  end

  def self.check_version(top_dir, dll_name)
    filename = nil
    if File.file?(File.join(top_dir, 'aya.txt'))
      filename = File.join(top_dir, 'aya.txt')
    elsif File.file?(File.join(top_dir, 'yaya.txt'))
      return 6 # XXX: YAYA
    elsif not dll_name.nil? and \
         File.file?(File.join(top_dir, [dll_name[0..-4], 'txt'].join('')))
      filename = File.join(top_dir, [dll_name[0..-4], 'txt'].join(''))
    end
    version = 0
    unless filename.nil?
      open(filename, :encoding => 'CP932') do |f|
        version = Aya.get_aya_version(Aya.find_dict(top_dir, f))
        ##else
        ##  version = 0
      end
    end
    return version
  end


  class Shiori
    attr_reader :aya_dir, :dic, :req_header, :req_command, :req_key, :dbpath, :filelist, :saori_library

    def initialize(dll_name)
      @dll_name = dll_name
      unless dll_name.nil?
        @__AYA_TXT = [dll_name[0..-4], 'txt'].join('')
        @__DBNAME = [dll_name[0..-5], '_variable.cfg'].join('')
      else
        @__AYA_TXT = 'aya.txt'
        @__DBNAME = 'aya_variable.cfg'
      end
      @saori = nil
      @dic_files = []
    end

    def use_saori(saori)
      @saori = saori
    end

    def find(top_dir, dll_name)
      result = 0
      version = Aya.check_version(top_dir, dll_name)
      if [3, 4].include?(version)
        result = 300
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: AYA compatible module for ninix\n" \
        "        Copyright (C) 2002-2019 by Shyouzou Sugitani\n" \
        "        Copyright (C) 2002, 2003 by MATSUMURA Namihiko")
    end

    def reset
      @boot_time = Time.new
      @aitalk = 0
      @first_boot = 0
      @dic_files = []
      @dic = AyaDictionary.new(self)
      @global_namespace = AyaGlobalNamespace.new(self)
      @system_functions = AyaSystemFunctions.new(self)
      @logfile = nil
      @filelist = {}
      reset_request()
      @ver_3 = false # Ver.3
    end

    def reset_request
      @req_command = ''
      @req_protocol = ''
      @req_key = []
      @req_header = {}
      @global_namespace.reset_res_reference()
    end

    def load(dir: nil)
      @aya_dir = dir
      @dbpath = File.join(@aya_dir, @__DBNAME)
      @saori_library = AyaSaoriLibrary.new(@saori, @aya_dir)
      reset()
      @first_boot = @global_namespace.load_database(self)
      begin
        path = File.join(@aya_dir, @__AYA_TXT)
        open(path, :encoding => 'CP932') do |aya_txt|
          load_aya_txt(aya_txt)
        end
      rescue #except IOError:
        Logging::Logging.debug('cannot read aya.txt')
        return 0
      rescue #except AyaError as error:
        Logging::Logging.debug(error)
        return 0
      end
      # default setting
      unless @global_namespace.exists('log')
        @global_namespace.put('log', '')
      end
      unless @global_namespace.exists('logmode')
        @global_namespace.put('logmode', 'simple')
      end
      for path in @dic_files
        basename = File.basename(path, '.*')
        ext = File.extname(path)
        ext = ext.downcase
        if ext == '.ayc'
          encrypted = true
        else
          encrypted = false
        end
        begin
          open(path, 'rb') do |dicfile|
            @dic.load(dicfile, encrypted)
          end
        rescue
          Logging::Logging.debug('cannot read ' + path.to_s)
          next
        end
      end
      unless @global_namespace.exists('aitalkinterval') # Ver.3
        @global_namespace.put('aitalkinterval', 180)
      end
      unless @global_namespace.exists('securitylevel') # Ver.3
        @global_namespace.put('securitylevel', 'high')
      end
      unless @dic.get_function('OnRequest') # Ver.3
        @ver_3 = true
      end
      request("NOTIFY SHIORI/3.0\r\n" \
              "ID: OnLoad\r\n" \
              "Sender: AYA\r\n" \
              "SecurityLevel: local\r\n" \
              "Path: " + @aya_dir.gsub('/', "\\") + "\r\n\r\n".encode('CP932', :invalid => :replace, :undef => :replace))
      return 1
    end

    def load_aya_txt(f)
      comment = 0
      for line in f
        line = line.encode("UTF-8", :invalid => :replace, :undef => :replace)
        unless comment.zero?
          end_ = Aya.find_not_quoted(line, '*/')
          next if end_ < 0
          line = line[end_ + 2..-1]
          comment = 0
        end
        while true
          start, end_ = Aya.find_comment(line)
          break if start < 0
          line = "" if start.zero?
          if end_ < 0
            comment = 1
            line = line[0..start-1]
            break
          end
          line = [line[0..start-1], line[end_..-1]].join('')
        end
        line = line.strip()
        next if line.empty?
        next unless line.include?(',')
        key, value = line.split(',', 2)
        evaluate_config(key.strip, value.strip)
      end
    end

    def evaluate_config(key, value)
      if key == 'dic'
        filename = Home.get_normalized_path(value)
        path = File.join(@aya_dir, filename)
        @dic_files << path
      elsif key == 'log'
        path = File.join(@aya_dir, value.to_s)
        begin
          f = open(path, 'w')
        rescue
          Logging::Logging.debug('cannnot open ' + path)
        else
          @logfile.close() unless @logfile.nil?
          @logfile = f
          @global_namespace.put('log', value.to_s)
        end
      elsif key == 'logmode'
        #pass # FIXME
      elsif key == 'aitalkinterval' # Ver.3
        unless @global_namespace.exists('aitalkinterval')
          begin
            Integer(value)
          rescue
            Logging::Logging.debug(
              'Could not convert ' + value.to_s + ' to an integer')
          else
            @global_namespace.put('aitalkinterval', value.to_i)
          end
        end
      elsif not key.nil? and not key.empty?
        begin
          value = Integer(value)
        rescue
          value = value.to_s
        end
        @global_namespace.put(key, value)
      end
    end

    def get_dictionary
      @dic
    end

    def get_ghost_dir
      @aya_dir
    end

    def get_global_namespace
      @global_namespace
    end

    def get_system_functions
      @system_functions
    end

    def get_boot_time
      @boot_time
    end

    def unload
      request(["NOTIFY SHIORI/3.0\r\n",
               "ID: OnUnload\r\n",
               "Sender: AYA\r\n",
               "SecurityLevel: local\r\n\r\n"].join("").encode('CP932', :invalid => :replace, :undef => :replace))
      @global_namespace.save_database()
      @saori_library.unload()
      @logfile.close() unless @logfile.nil?
      for key in @filelist.keys()
        @filelist[key].close()
      end
    end

    # SHIORI API
    def request(req_string)
      header = req_string.force_encoding('CP932').split(/\r?\n/, 0)
      unless header.nil? or header.empty?
        line = header.shift
        line = line.strip()
        req_list = line.split(nil, -1)
        if req_list.length >= 2
          @req_command = req_list[0].strip()
          @req_protocol = req_list[1].strip()
        end
        for line in header
          line = line.strip()
          next if line.empty?
          line = line.encode("UTF-8", :invalid => :replace, :undef => :replace)
          next unless line.include?(':')
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          begin
            value = Integer(value)
          rescue
            value = value.to_s
          end
          @req_key << key
          @req_header[key] = value
        end
      end
      unless @first_boot.zero?
        case @req_header['ID']
        when 'OnBoot', 'OnVanished', 'OnGhostChanged'
          @first_boot = 0
          Logging::Logging.debug(
            'We lost the ' + @__DBNAME.to_s + '. Initializing....')
          request("NOTIFY SHIORI/3.0\r\n" \
                  "ID: OnFirstBoot\r\n" \
                  "Sender: ninix\r\n" \
                  "SecurityLevel: local\r\n" \
                  "Reference0: 0\r\n\r\n".encode('CP932', :invalid => :replace, :undef => :replace))
        when 'OnFirstBoot'
          @first_boot = 0
        end
      end
      result = ''
      func = @dic.get_function('OnRequest')
      if func.nil? and @req_header.include?('ID') # Ver.3
        for i in 0..8
          @global_namespace.remove(['reference', i.to_s].join(''))
        end
        for i in 0..8
          key = ['Reference', i.to_s].join('')
          if @req_header.include?(key)
            @global_namespace.put(['reference', i.to_s].join(''),
                                  @req_header[key])
          end
        end
        unless @req_header['ID'].start_with?('On')
          prefix = 'On_'
        else
          prefix = ''
        end
        func = @dic.get_function(
          [prefix, @req_header['ID']].join(''))
      end
      unless func.nil?
        result = func.call()
      end
      if @ver_3 and @req_header.include?('ID') and \
         @req_header['ID'] == 'OnSecondChange' # Ver.3
        aitalkinterval = @global_namespace.get('aitalkinterval')
        if aitalkinterval > 0
          @aitalk += 1
          if @aitalk > aitalkinterval
            @aitalk = 0
            result = request("GET SHIORI/3.0\r\n" \
                             "ID: OnAiTalk\r\n" \
                             "Sender: ninix\r\n" \
                             "SecurityLevel: local\r\n\r\n".encode('CP932', :invalid => :replace, :undef => :replace))
            reset_request()
            return result
          end
        end
      end
      reset_request()
      if @ver_3 # Ver.3
        result = ("SHIORI/3.0 200 OK\r\n" \
                  "Sender: AYA\r\n" \
                  "Value: #{result}\r\n\r\n".encode('CP932', :invalid => :replace, :undef => :replace))
        return result
      else
        return result.encode('CP932', :invalid => :replace, :undef => :replace)
      end
    end
  end


  class AyaSecurity

    DENY = 0
    ACCEPT = 1
    CONFIG = 'aya_security.cfg'

    def initialize(aya)
      @__aya = aya
      @__cfg = ''
      @__aya_dir = File.absolute_path(@__aya.aya_dir)
      @__fwrite = [[DENY, '*'], [ACCEPT, @__aya_dir]]
      @__fread = [[ACCEPT, '*']]
      @__loadlib = [[ACCEPT, '*']]
      @__logfile = nil
      load_cfg()
      @__fwrite.reverse!
      @__fread.reverse!
    end

    def load_cfg
      path = []
      head, tail = File.split(@__aya_dir)
      current = head
      while not tail.empty? and tail != "/"
        path << tail
        head, tail = File.split(current)
        current = head
      end
      path << current
      current_dir = ''
      break_flag = false
      while not path.empty?
        current_dir = File.join(current_dir, path.pop)
        if File.exist?(File.join(current_dir, CONFIG))
          @__cfg = File.join(current_dir, CONFIG)
          break_flag = true
          break
        end
      end
      unless break_flag # default setting
        Logging::Logging.warning('*WARNING : aya_security.cfg - file not found.')
        return
      end
      begin
        open(@__cfg, :encoding => 'CP932') do |f|
          name = ''
          data = {}
          @comment = 0
          line = readline(f)
          break_flag = flase
          while line
            if line.include?('[')
              unless name.empty?
                name = expand_path(name)
                if name == '*'
                  break_flag = true
                  break
                end
                if @__aya_dir.start_with?(name)
                  break_flag = true
                  break
                end
              end
              data = {}
              start = line.index('[')
              if start.nil?
                start = -1
              end
              end_ = line.index(']')
              if end_.nil?
                end_ = -1
              end
              if end_ < 0
                end_ = line.length
              end
              name = line[start + 1..end_-1]
            else
              if line.include?(',')
                key, value = line.split(',', 2)
                key.strip!
                value.strip!
                if key.start_with?('deny.')
                  key = key[5..-1]
                  list_ = data.get(key, [])
                  list_ << [DENY, value]
                  data[key] = list_
                elsif key.start_swith?('accept.')
                  key = key[7..-1]
                  list_ = data.get(key, [])
                  list_ << [ACCEPT, value]
                  data[key] = list_
                elsif key == 'log'
                  head, tail = File.split(@__cfg)
                  value = ['./', value].join('')
                  value = File.join(head, value)
                  value = File.absolute_path(value)
                  data[key] = value
                else
                  #pass # error
                end
              end
            end
            line = readline(f)
          end
          unless break_flag
            if name.empty?
              Logging::Logging.warning('*WARNING : aya_security.cfg - no entry found for ' + File.join(@__aya_dir, 'aya.dll') + '.')
              return
            end
          end
        end
      rescue #except IOError:
        Logging::Logging.debug('cannot read aya.txt')
        return
      rescue #except AyaError as error:
        Logging::Logging.debug(error)
        return
      end
      @__fwrite.concat(data.get('fwrite', []))
      for i in 0..@__fwrite.length-1
        @__fwrite[i][1] = expand_path(@__fwrite[i][1])
      end
      @__fread.concat(data.get('fread', []))
      for i in 0..@__fread.length-1
        @__fread[i][1] = expand_path(@__fread[i][1])
      end
      @__loadlib.concat(data.get('loadlib', []))
      if data.include?('log')
        @__logfile = data['log']
      end
    end

    def expand_path(path)
      head, tail = File.split(@__cfg)
      return path if path == '*'
      return head if path == ''
      meta = path.rfind('%CFGDIR')
      if meta >= 0
        path = Home.get_normalized_path(path[meta + 7..-1])
        path = ['./', path].join('')
        path = File.join(head, path)
      else
        path = Home.get_normalized_path(path)
      end
      path = File.absolute_path(path)
      return path
    end

    def readline(f)
      for line in f
        unless @comment.zero?
          end_ = Aya.find_not_quoted(line, '*/')
          next if end_ < 0
          line = line[end_ + 2..-1]
          @comment = 0
        end
        while true
          start, end_ = Aya.find_comment(line)
          break if start < 0
          line = "" if start.zero?
          if end_ < 0
            @comment = 1
            line = line[0..start-1]
            break
          end
          line = [line[0..start-1], ' ', line[end_..-1]].join('')
        end
        line = line.strip()
        next if line.empty?
        break
      end
      return line
    end

    def check_path(path, flag: 'w')
      result = 0
      abspath = File.absolute_path(path)
      head, tail = File.split(abspath)
      if tail != 'aya_security.cfg'
        if ['w', 'w+', 'r+', 'a', 'a+'].include?(flag)
          for perm, name in @__fwrite
            if name == '*' or abspath[0..name.length-1] == name
              case perm
              when ACCEPT
                result = 1
              when DENY
                result = 0
              else
                next
              end
              break
            end
          end
        elsif flag == 'r'
          result = 1 # default
          for perm, name in @__fread
            if name == '*' or abspath[0..name.length-1] == name
              case perm
              when ACCEPT
                result = 1
              when DENY
                result = 0
              else
                next
              end
              break
            end
          end
        end
      end
      if @__logfile and result.zero?
        if flag == 'r'
          logging('許可されていないファイルまたはディレクトリ階層の読み取りをブロックしました.',
                  'file', abspath)
        else
          logging('許可されていないファイルまたはディレクトリ階層への書き込みをブロックしました.',
                  'file', abspath)
        end
      end
      return result
    end

    def check_lib(dll)
      result = 1 # default
      head, tail = File.split(Home.get_normalized_path(dll))
      dll_name = tail
      for perm, name in @__loadlib
        if name == '*' or dll_name == name
          if perm == ACCEPT
          result = 1
          elsif perm == DENY
            result = 0
          end
        end
      end
      if @__logfile and result.zero?
        logging('許可されていない DLL のロードをブロックしました.',
                'dll ', dll_name)
      end
      return result
    end

    def logging(message, target_type, target) ## FIXME
      return nil if @__logfile.nil?
      begin
        open(@__logfile, 'a') do |f|
          Lock.lockfile(f)
          aya_dll = File.join(@__aya_dir, 'aya.dll')
          line = ['*WARNING : ', message.to_s, "\n"].join('')
          line = [line, 'AYA  : ', aya_dll, "\n"].join('')
          line = [line, 'date : ',
                  Time.now.strftime('%Y/%m/%d(%a) %H:%M:%S'),
                  "\n"].join('')
          line = [line, target_type.to_s,
                  ' : ', target.to_s, "\n"].join('')
          f.write(line)
          f.write("\n")
          Lock.unlockfile(f)
        end
      rescue
        Logging::Logging.debug('cannnot open ' + @__logfile.to_s)
      end
      return nil
    end
  end


  class AyaDictionary
    attr_reader :aya

    def initialize(aya)
      @aya = aya
      @functions = {}
      @global_macro = {}
    end

    def get_function(name)
      if @functions.has_key?(name)
        return @functions[name]
      else
        return nil
      end
    end

    def load(f, encrypted)
      all_lines = []
      local_macro = {}
      logical_line = ''
      comment = 0
      while true
        if encrypted
          line = Aya.decrypt_readline(f)
        else
          line = f.gets
        end
        break if line.nil? # EOF
        line = line.force_encoding('CP932').encode("UTF-8", :invalid => :replace, :undef => :replace)
        unless comment.zero?
          end_ = Aya.find_not_quoted(line, '*/')
          next if end_ < 0
          line = line[end_ + 2..-1]
          comment = 0
        end
        while true
          start, end_ = Aya.find_comment(line)
          break if start < 0
          line = "" if start.zero?
          if end_ < 0
            comment = 1
            line = line[0..start-1]
            break
          end
          line = [line[0..start-1], ' ', line[end_..-1]].join('')
        end
        line = line.gsub(/^[\s　]+|[\s　]+$/, "") # 全角空白も除去
        next if line.empty?
        if line.end_with?('/')
          logical_line = [logical_line, line[0..-2]].join('')
        else
          logical_line = [logical_line, line].join('')
          buf = line
          # preprocess
          if buf.start_with?('#')
            buf = buf[1..-1].strip()
            for (tag, target) in [['define', local_macro],
                                  ['globaldefine', @global_macro]]
              if buf.start_with?(tag)
                buf = buf[tag.length..-1].strip()
                i = 0
                while i < buf.length
                  if buf[i] == " " or buf[i] == "\t" or \
                    buf[i] == "　"
                    key = buf[0..i-1].strip()
                    target[key] = buf[i..-1].strip()
                    break
                  end
                  i += 1
                end
                break
              end
            end
            logical_line = '' # reset
            next
          end
          for macro in [local_macro, @global_macro]
            logical_line = preprocess(macro, logical_line)
          end
          # multi statement
          list_lines = split_line(logical_line.strip())
          unless list_lines.empty?
            all_lines.concat(list_lines)
          end
          logical_line = '' # reset
        end
      end
      for line in all_lines
        while true
          pos = Aya.find_not_quoted(line, '　')
          if pos.zero?
            line = line[1..-1]
          elsif pos > 0
            line = [line[0..pos-1], ' ', line[pos + 1..-1]].join('')
          else
            break
          end
        end
      end
      evaluate_lines(all_lines, File.split(f.path)[1])
    end

    def split_line(line)
      lines = []
      while true
        break if line.nil? or line.empty?
        pos = line.length # not line.length - 1
        token = ''
        for x in ['{', '}']
          pos_new = Aya.find_not_quoted(line, x)
          if 0 <= pos_new and pos_new < pos
            pos = pos_new
            token = x
          end
        end
        unless pos.zero?
          new = line[0..pos-1].strip()
        else # '{' or '}'
          new = ""
        end
        line = line[pos + token.length..-1].strip()
        unless new.empty?
          lines << new
        end
        if token != ''
          lines << token
        end
      end
      return lines
    end

    def preprocess(macro, line)
      for key in macro.keys
        value = macro[key]
        line = line.gsub(key, value)
      end
      return line
    end

    SPECIAL_CHARS = [']', '(', ')', '[', '+', '-', '*', '/', '=',
                     ':', ';', '!', '{', '}', '%', '&', '#', '"',
                     '<', '>', ',', '?']

    def evaluate_lines(lines, file_name)
      prev = nil
      name = nil
      function = []
      option = nil
      block_nest = 0
      for i in 0..lines.length-1
        line = lines[i]
        if line == '{'
          unless name.nil?
            if block_nest > 0
              function << line
            end
            block_nest += 1
          else
            if prev.nil?
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "{" at ' \
                                                      'the top of file')
            else
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "{" at ' \
                                                      'the bottom of function "' + prev.to_s + '"')
            end
          end
        elsif line == '}'
          unless name.nil?
            block_nest -= 1
            if block_nest > 0
              function << line
            elsif block_nest.zero?
              @functions[name] = AyaFunction.new(self, name,
                                                 function, option)
              # reset
              prev = name
              name = nil
              function = []
              option = nil
            end
          else
            if prev.nil?
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "}" at ' \
                                                      'the top of file')
            else
              Logging::Logging.debug(
                'syntax error in ' + file_name.to_s + ': unbalanced "}" at ' \
                                                      'the bottom of function "' + prev.to_s + '"')
            end
            block_nest = 0
          end
        elsif name.nil?
          if line.include?(':')
            name, option = line.split(':', 2)
            name.strip!
            option.strip!
          else
            name = line
          end
          for char in SPECIAL_CHARS
            if name.include?(char)
              Logging::Logging.debug(
                'illegal function name "' + name.to_s + '" in ' + file_name.to_s)
            end
          end
          function = []
        else
          if not name.nil? and block_nest > 0
            function << line
          else
            Logging::Logging.debug('syntax error in ' + file_name + ': ' + line)
          end
        end
      end
    end
  end


  class AyaFunction

    TYPE_INT = 10
    TYPE_FLOAT = 11
    TYPE_DECISION = 12
    TYPE_RETURN = 13
    TYPE_BLOCK = 14
    TYPE_SUBSTITUTION = 15
    TYPE_INC = 16
    TYPE_DEC = 17
    TYPE_IF = 18
    TYPE_WHILE = 19
    TYPE_FOR = 20
    TYPE_BREAK = 21
    TYPE_CONTINUE = 22
    TYPE_SWITCH = 23
    TYPE_CASE = 24
    TYPE_STRING_LITERAL = 25
    TYPE_STRING = 26
    TYPE_OPERATOR = 27
    TYPE_STATEMENT = 28
    TYPE_CONDITION = 29
    TYPE_SYSTEM_FUNCTION = 30
    TYPE_FUNCTION = 31
    TYPE_ARRAY_POINTER = 32
    TYPE_ARRAY = 33
    TYPE_VARIABLE_POINTER = 34
    TYPE_VARIABLE = 35
    TYPE_TOKEN = 36
    CODE_NONE = 40
    CODE_RETURN = 41
    CODE_BREAK = 42
    CODE_CONTINUE = 43
    Re_f = Regexp.new('\A[-+]?\d+(\.\d*)\z')
    Re_d = Regexp.new('\A[-+]?\d+\z')
    Re_d_ = Regexp.new('[-+]?\d+\z')
    Re_b = Regexp.new('\A[-+]?0[bB][01]+\z')
    Re_x = Regexp.new('\A[-+]?0[xX][\dA-Fa-f]+\z')
    Re_if = Regexp.new('\Aif\s')
    Re_elseif = Regexp.new('\Aelseif\s')
    Re_while = Regexp.new('\Awhile\s')
    Re_for = Regexp.new('\Afor\s')
    Re_switch = Regexp.new('\Aswitch\s')
    Re_case = Regexp.new('\Acase\s')
    Re_when = Regexp.new('\Awhen\s')
    SPECIAL_CHARS = [']', '(', ')', '[', '+', '-', '*', '/', '=',
                     ':', ';', '!', '{', '}', '%', '&', '#', '"',
                     '<', '>', ',', '?']

    def initialize(dic, name, lines, option)
      @dic = dic
      @name = name
      @status = CODE_NONE
      @lines = parse(lines)
      if option == 'nonoverlap'
        @nonoverlap = [[], [], []]
      else
        @nonoverlap = nil
      end
      if option == 'sequential'
        @sequential = [[], []]
      else
        @sequential = nil
      end
    end

    def parse(lines)
      result = []
      i = 0
      while i < lines.length
        line = lines[i]
        if line == '--'
          result << [TYPE_DECISION, []]
        elsif line == 'return'
          result << [TYPE_RETURN, []]
        elsif line == 'break'
          result << [TYPE_BREAK, []]
        elsif line == 'continue'
          result << [TYPE_CONTINUE, []]
        elsif line == '{'
          inner_func = []
          i, inner_func = get_block(lines, i)
          result << [TYPE_BLOCK, parse(inner_func)]
        elsif not Re_if.match(line).nil?
          inner_blocks = []
          while true
            current_line = lines[i]
            if not Re_if.match(current_line).nil?
              condition_tokens = AyaStatement.new(
                current_line[2..-1].strip()).tokens
              condition = parse_condition(condition_tokens)
            elsif not Re_elseif.match(current_line).nil?
              condition_tokens = AyaStatement.new(
                current_line[6..-1].strip()).tokens
              condition = parse_condition(condition_tokens)
            else
              condition = [TYPE_CONDITION, nil]
            end
            inner_block = []
            i, inner_block = get_block(lines, i + 1)
            if condition.nil?
              inner_blocks = []
              break
            end
            entry = []
            entry << condition
            entry << parse(inner_block)
            inner_blocks << entry
            if i + 1 >= lines.length
              break
            end
            next_line = lines[i + 1]
            if Re_elseif.match(next_line).nil? and \
              next_line != 'else'
              break
            end
            i = (i + 1)
          end
          unless inner_blocks.empty?
            result << [TYPE_IF, inner_blocks]
          end
        elsif not Re_while.match(line).nil?
          condition_tokens = AyaStatement.new(line[5..-1].strip()).tokens
          condition = parse_condition(condition_tokens)
          inner_block = []
          i, inner_block = get_block(lines, i + 1)
          result << [TYPE_WHILE,
                     [condition, parse(inner_block)]]
        elsif not Re_for.match(line).nil?
          inner_block = []
          i, inner_block = get_block(lines, i + 1)
          end_ = Aya.find_not_quoted(line, ';')
          if end_ < 0
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
              'illegal for statement "' + line.to_s + '"')
          else
            init = parse([line[3..end_-1].strip()])
            condition = line[end_ + 1..-1].strip()
            end_ = Aya.find_not_quoted(condition, ';')
            if end_ < 0
              Logging::Logging.debug(
                'syntax error in function "' + @name.to_s + '": ' \
                'illegal for statement "' + line.to_s + '"')
            else
              reset = parse([condition[end_ + 1..-1].strip()])
              condition_tokens = AyaStatement.new(
                condition[0..end_-1].strip()).tokens
              condition = parse_condition(condition_tokens)
              unless condition.nil?
                result << [TYPE_FOR,
                           [[init, condition, reset],
                            parse(inner_block)]]
              end
            end
          end
        elsif not Re_switch.match(line).nil?
          index = parse_token(line[6..-1].strip())
          ##fail "assert" unless [].include?(index[0]) # FIXME
          inner_block = []
          i, inner_block = get_block(lines, i + 1)
          result << [TYPE_SWITCH,
                     [index, parse(inner_block)]]
        elsif not Re_case.match(line).nil?
          left = parse_token(line[4..-1].strip())
          ##fail "assert" unless [].include?(left[0]) # FIXME
          i, block = get_block(lines, i + 1)
          inner_blocks = []
          j = 0
          while true
            current_line = block[j]
            unless Re_when.match(current_line).nil?
              right = current_line[4..-1].strip()
            else # 'others'
              right = nil
            end
            inner_block = []
            j, inner_block = get_block(block, j + 1)
            unless right.nil?
              argument = AyaArgument.new(right)
              while argument.has_more_tokens()
                entry = []
                right = argument.next_token()
                tokens = AyaStatement.new(right).tokens
                if ['-', '+'].include?(tokens[0])
                  value_min = parse_statement([tokens.shift,
                                               tokens.shift])
                else
                  value_min = parse_statement([tokens.shift])
                end
                value_max = value_min
                unless tokens.empty?
                  if tokens[0] != '-'
                    Logging::Logging.debug(
                      'syntax error in function ' \
                      '"' + @name.to_s + '": when ' + right.to_s)
                    next
                  else
                    tokens.shift
                  end
                  if tokens.length > 2 or \
                    (tokens.length == 2 and \
                     not ['-', '+'].include?(tokens[0]))
                    Logging::Logging.debug(
                      'syntax error in function ' \
                      '"' + @name + '": when ' + right.to_s)
                    next
                  else
                    value_max = parse_statement(tokens)
                  end
                end
                entry << [value_min, value_max]
                entry << parse(inner_block)
                inner_blocks << entry
              end
            else
              entry = []
              entry << right
              entry << parse(inner_block)
              inner_blocks << entry
            end
            if j + 1 == block.length
              break
            end
            next_line = block[j + 1]
            if Re_when.match(next_line).nil? and \
              next_line != 'others'
              break
            end
            j += 1
          end
          result << [TYPE_CASE, [left, inner_blocks]]
        elsif Aya.find_not_quoted(line, ';') >= 0
          end_ = Aya.find_not_quoted(line, ';')
          new_line = line[end_ + 1..-1].strip()
          line = line[0..end_-1].strip()
          if i > 0
            new_lines = lines[0..i-1]
          else
            new_lines = []
          end
          unless line.empty?
            new_lines << line
          end
          unless new_line.empty?
            new_lines << new_line
          end
          new_lines.concat(lines[i + 1..-1])
          lines = new_lines
          next
        elsif is_substitution(line)
          tokens = AyaStatement.new(line).tokens
          left = parse_token(tokens[0])
          unless [TYPE_ARRAY,
                  TYPE_VARIABLE,
                  TYPE_TOKEN].include?(left[0])
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
                                                          'illegal substitution "' + line + '"')
          else
            if left[0] == TYPE_TOKEN # this cannot be FUNCTION
              left[0] = TYPE_VARIABLE
              left[1] = [left[1], nil]
            end
            ope = [TYPE_OPERATOR, tokens[1]]
            right = parse_statement(tokens[2..-1])
            result << [TYPE_SUBSTITUTION,
                       [left, ope, right]]
          end
        elsif is_inc_or_dec(line) # ++/--
          ope = line[-2..-1]
          var = parse_token(line[0..-3])
          unless [TYPE_ARRAY,
                  TYPE_VARIABLE,
                  TYPE_TOKEN].include?(var[0])
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
                                                          'illegal increment/decrement "' + line.to_s + '"')
          else
            if var[0] == TYPE_TOKEN
              var[0] = TYPE_VARIABLE
              var[1] = [var[1], nil]
            end
            if ope == '++'
              result << [TYPE_INC, var]
            elsif ope == '--'
              result << [TYPE_DEC, var]
            else
              return nil # should not reach here
            end
          end
        else
          tokens = AyaStatement.new(line).tokens
          if tokens[-1] == '"' # This is kluge.
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
                                                          'unbalanced \'"\' or \'"\' in string ' + tokens.join(''))
            token = tokens[0..-2].join('')
            if not token.nil? and token[0] == '"'
              token = token[1..-1]
            end
            unless token.empty?
              unless token.include?('%')
                result << [TYPE_STRING_LITERAL, token]
              else
                result << [TYPE_STRING, token]
              end
            end
          elsif tokens.length == 1
            result << parse_token(tokens[0])
          else
            result << parse_statement(tokens)
          end
        end
        i += 1
      end
      result << [TYPE_DECISION, []]
      return result
    end

    def parse_statement(statement_tokens)
      n_tokens = statement_tokens.length
      statement = []
      if n_tokens == 1
        statement = [TYPE_STATEMENT,
                     parse_token(statement_tokens[0])]
      elsif ['+', '-'].include?(statement_tokens[0])
        tokens = ['0']
        tokens.concat(statement_tokens)
        statement = parse_statement(tokens)
      else
        ope_index = nil
        for ope in ['+', '-']
          if statement_tokens.include?(ope)
            new_index = statement_tokens.index(ope)
            if ope_index.nil? or new_index < ope_index
              ope_index = new_index
            end
          end
        end
        if ope_index.nil?
          statement_tokens.reverse!
          begin
            for ope in ['*', '/', '%']
              if statement_tokens.include?(ope)
                new_index = statement_tokens.index(ope)
                if ope_index.nil? or new_index < ope_index
                  ope_index = new_index
                end
              end
            end
            unless ope_index.nil?
              ope_index = (-1 - ope_index)
            end
          ensure
            statement_tokens.reverse!
          end
        end
        if [nil, -1, 0, n_tokens - 1].include?(ope_index)
          if statement_tokens[0].start_with?('"') and \
            statement_tokens[0].end_with?('"') and \
            statement_tokens[-1].start_with?('"') and \
            statement_tokens[-1].end_with?('"')
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
              '\'"\' in string ' + statement_tokens.join(' '))
            return parse_token(statement_tokens.join(' '))
          else
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
                                                          'illegal statement "' + statement_tokens.join(' ') + '"')
            return []
          end
        else
          ope = [TYPE_OPERATOR, statement_tokens[ope_index]]
          if statement_tokens[0..ope_index-1].length == 1
            if statement_tokens[0].start_with?('(')
              tokens = AyaStatement.new(statement_tokens[0][1..-2]).tokens
              left = parse_statement(tokens)
            else
              left = parse_token(
                statement_tokens[0..ope_index-1][0])
            end
          else
            left = parse_statement(statement_tokens[0..ope_index-1])
          end
          if statement_tokens[ope_index + 1..-1].length == 1
            if statement_tokens[-1].start_with?('(')
              tokens = AyaStatement.new(
                statement_tokens[ope_index + 1][1..-2]).tokens
              right = parse_statement(tokens)
            else
              right = parse_token(
                statement_tokens[ope_index + 1..-1][0])
            end
          else
            right = parse_statement(
              statement_tokens[ope_index + 1..-1])
          end
          statement = [TYPE_STATEMENT, left, ope, right]
        end
      end
      return statement
    end

    def parse_condition(condition_tokens)
      n_tokens = condition_tokens.length
      condition = nil
      ope_index = nil
      condition_tokens.reverse!
      begin
        for ope in ['&&', '||']
          if condition_tokens.include?(ope)
            new_index = condition_tokens.index(ope)
            return nil if new_index.zero? # XXX
            if ope_index.nil? or new_index < ope_index
              ope_index = new_index
            end
          end
        end
        unless ope_index.nil?
          ope_index = (-1 - ope_index)
        end
      ensure
        condition_tokens.reverse!
      end
      if ope_index.nil?
        for ope in ['==', '!=', '>', '<', '>=', '<=', '_in_', '!_in_']
          if condition_tokens.include?(ope)
            new_index = condition_tokens.index(ope)
            if ope_index.nil? or new_index < ope_index
              ope_index = new_index
            end
          end
        end
        if [nil, -1, 0, n_tokens - 1].include?(ope_index)
          Logging::Logging.debug(
            'syntax error in function "' + @name.to_s + '": ' \
                                                        'illegal condition "' + condition_tokens.join(' ') + '"')
          return nil
        end
        ope = [TYPE_OPERATOR, condition_tokens[ope_index]]
        if condition_tokens[0..ope_index-1].length == 1
          left = parse_token(condition_tokens[0..ope_index-1][0])
        else
          left = parse_statement(condition_tokens[0..ope_index-1])
        end
        if condition_tokens[ope_index + 1..-1].length == 1
          right = parse_token(condition_tokens[ope_index + 1..-1][0])
        else
          right = parse_statement(condition_tokens[ope_index + 1..-1])
        end
        condition = [TYPE_CONDITION, [left, ope, right]]
      else
        ope = [TYPE_OPERATOR, condition_tokens[ope_index]]
        left = parse_condition(condition_tokens[0..ope_index-1])
        right = parse_condition(condition_tokens[ope_index + 1..-1])
        unless left.nil? or right.nil?
          condition = [TYPE_CONDITION, [left, ope, right]]
        end
      end
      return condition
    end

    def parse_argument(args)
      argument = AyaArgument.new(args)
      arguments = []
      while argument.has_more_tokens()
        token = argument.next_token()
        if token.start_with?('&')
          result = parse_token(token[1..-1])
          case result[0]
          when TYPE_ARRAY
            arguments << [TYPE_ARRAY_POINTER, result[1]]
          when TYPE_VARIABLE
            arguments << [TYPE_VARIABLE_POINTER, result[1]]
          when TYPE_TOKEN
            arguments << [TYPE_VARIABLE_POINTER, [result[1], nil]]
          else
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
              'illegal argument "' + token.to_s + '"')
          end
        elsif token.start_with?('(')
          unless token.end_with?(')')
            Logging::Logging.debug(
              'syntax error in function "' + @name.to_s + '": ' \
              'unbalanced "(" in the string(' + token.to_s + ')')
            return nil
          else
            statement = AyaStatement.new(token[1..-2])
            arguments << parse_statement(statement.tokens)
          end
        else
          arguments << parse_statement([token])
        end
      end
      return arguments
    end

    def parse_token(token)
      result = []
      if not Re_f.match(token).nil?
        result = [TYPE_FLOAT, token]
      elsif not Re_d.match(token).nil?
        result = [TYPE_INT, token]
      elsif token.start_with?('"')
        text = token[1..-1]
        if text.end_with?('"')
          text = text[0..-2]
        end
        if text.count('"') > 0
          Logging::Logging.debug(
            'syntax error in function "' + @name.to_s + '": ' \
            '\'"\' in string "' + text.to_s + '"')
        end
        unless text.include?('%')
          result = [TYPE_STRING_LITERAL, text]
        else
          result = [TYPE_STRING, text]
        end
      else
        pos_parenthesis_open = token.index('(')
        pos_block_open = token.index('[')
        if not pos_parenthesis_open.nil? and \
          (pos_block_open.nil? or \
           pos_parenthesis_open < pos_block_open) # function
          unless token.end_with?(')')
            Logging::Logging.debug(
              'syntax error: unbalanced "(" in "' + token.to_s + '"')
          else
            func_name = token[0..pos_parenthesis_open-1]
            arguments = parse_argument(
              token[pos_parenthesis_open + 1..-2])
            break_flag = false
            for char in SPECIAL_CHARS
              if func_name.include?(char)
                Logging::Logging.debug(
                  'illegal character "' + char + '" in ' \
                                                 'the name of function "' + token.to_s + '"')
                break_flag = true
                break
              end
            end
            unless break_flag
              if @dic.aya.get_system_functions().exists(
                func_name)
                if func_name == 'LOGGING'
                  result = [TYPE_SYSTEM_FUNCTION,
                            [func_name, arguments,
                             token[pos_parenthesis_open + 1..-2]]]
                else
                  result = [TYPE_SYSTEM_FUNCTION,
                            [func_name, arguments]]
                end
              else
                result = [TYPE_FUNCTION,
                          [func_name, arguments]]
              end
            end
          end
        elsif not pos_block_open.nil? and pos_block_open != -1 # array
          unless token.end_with?(']')
            Logging::Logging.debug(
              'syntax error: unbalanced "[" in "' + token.to_s + '"')
          else
            array_name = token[0..pos_block_open-1]
            index = parse_token(token[pos_block_open + 1..-2])
            break_flag = false
            for char in SPECIAL_CHARS
              if array_name.include?(char)
                Logging::Logging.debug(
                  'illegal character "' + char.to_s + '" in ' \
                  'the name of array "' + token.to_s + '"')
                break_flag = true
                break
              end
            end
            unless break_flag
              result = [TYPE_ARRAY, [array_name, index]]
            end
          end
        else # variable or function
          break_flag = false
          for char in SPECIAL_CHARS
            if token.include?(char)
              Logging::Logging.debug(
                'syntax error in function "' + @name.to_s + '": ' \
                                                            'illegal character "' + char + '" in the name of ' \
                                                                                           'function/variable "' + token + '"')
              break_flag = true
              break
            end
          end
          unless break_flag
            result = [TYPE_TOKEN, token]
          end
        end
      end
      return result
    end

    def call(argv: nil)
      namespace = AyaNamespace.new(@dic.aya)
      _argv = []
      if argv.nil?
        namespace.put('_argc', 0)
      else
        namespace.put('_argc', argv.length)
        for i in 0..argv.length-1
          if argv[i].is_a?(Hash)
            _argv << argv[i]['value']
          else
            _argv << argv[i]
          end
        end
      end
      namespace.put('_argv', _argv)
      @status = CODE_NONE
      result = evaluate(namespace, @lines, -1, 0)
      if result.nil?
        result = ''
      end
      unless argv.nil?
        for i in 0..argv.length-1
          if argv[i].is_a?(Hash)
            value = _argv[i]
            name = argv[i]['name']
            namespace = argv[i]['namespace']
            index = argv[i]['index']
            namespace.put(name, value, :index => index)
          end
        end
      end
      return result
    end

    def evaluate(namespace, lines, index_to_return, is_inner_block)
      result = []
      alternatives = []
      for line in lines
        next if line.nil? or line.empty?
        if [TYPE_DECISION, TYPE_RETURN,
            TYPE_BREAK, TYPE_CONTINUE].include?(line[0]) or \
          [CODE_RETURN, CODE_BREAK,
           CODE_CONTINUE].include?(@status)
          unless alternatives.empty?
            unless is_inner_block.zero?
              if index_to_return < 0
                result << alternatives.sample
              elsif index_to_return <= (alternatives.length - 1)
                result << alternatives[index_to_return]
              else # out of range
                result << ''
              end
            else
              result << alternatives
            end
            alternatives = []
          end
          if line[0] == TYPE_RETURN or \
            @status == CODE_RETURN
            @status = CODE_RETURN
            break
          elsif line[0] == TYPE_BREAK or \
               @status == CODE_BREAK
            @status = CODE_BREAK
            break
          elsif line[0] == TYPE_CONTINUE or \
               @status == CODE_CONTINUE
            @status = CODE_CONTINUE
            break
          end
        elsif line[0] == TYPE_BLOCK
          inner_func = line[1]
          local_namespace = AyaNamespace.new(@dic.aya, :parent => namespace)
          result_of_inner_func = evaluate(local_namespace,
                                          inner_func, -1, 1)
          unless result_of_inner_func.nil?
            alternatives << result_of_inner_func
          end
        elsif line[0] == TYPE_SUBSTITUTION
          left, ope, right = line[1]
          ##fail "assert" unless [TYPE_ARRAY, TYPE_VARIABLE].include?(left[0])
          ##fail "assert" unless ope[0] == TYPE_OPERATOR
          ope = ope[1]
          if [':=', '+:=', '-:=', '*:=', '/:=', '%:='].include?(ope)
            type_float = 1
          else
            type_float = 0
          end
          ##fail "assert" unless right[0] == TYPE_STATEMENT
          right_result = evaluate_statement(namespace, right,
                                            type_float)
          unless ['=', ':='].include?(ope)
            left_result = evaluate_token(namespace, left) 
            right_result = operation(left_result, ope[0],
                                     right_result, type_float)
            ope = ope[1..-1]
          end
          substitute(namespace, left, ope, right_result)
        elsif line[0] == TYPE_INC or \
             line[0] == TYPE_DEC # ++/--
          if line[0] == TYPE_INC
            ope = '++'
          elsif line[0] == TYPE_DEC
            ope = '--'
          else
            return nil # should not reach here
          end
          var = line[1]
          ##fail "assert" unless [TYPE_ARRAY, TYPE_VARIABLE].include?(var[0])
          var_name = var[1][0]
          if var_name.start_with?('_')
            target_namespace = namespace
          else
            target_namespace = @dic.aya.get_global_namespace()
          end
          value = evaluate_token(namespace, var)
          if var[0] == TYPE_ARRAY # _argv[n] only
            index = evaluate_token(namespace, var[1][1])
            begin
              index = Integer(index)
            rescue
              Logging::Logging.debug(
                'index of array has to be integer: ' \
                '' + var_name.to_s + '[' + var[1][1][0].to_s + ']')
              return nil
            end
          end
          if value.is_a?(Integer) or value.is_a?(Float)
            if ope == '++'
              target_namespace.put(var_name, value.to_i + 1, :index => index)
            elsif ope == '--'
              target_namespace.put(var_name, value.to_i - 1, :index => index)
            else
              return nil # should not reach here
            end
          else
            Logging::Logging.debug(
              'illegal increment/decrement:' \
              'type of variable ' + var_name.to_s + ' is not number')
          end
        elsif line[0] == TYPE_IF
          inner_blocks = line[1]
          n_blocks = inner_blocks.length
          for j in 0..n_blocks-1
            entry = inner_blocks[j]
            condition = entry[0]
            inner_block = entry[1]
            fail "assert" unless condition[0] == TYPE_CONDITION
            if condition.nil? or \
              evaluate_condition(namespace, condition)
              local_namespace = AyaNamespace.new(@dic.aya, :parent => namespace)
              result_of_inner_block = evaluate(local_namespace,
                                               inner_block,
                                               -1, 1)
              unless result_of_inner_block.nil? or
                    [0, false].include?(result_of_inner_block) or
                    result_of_inner_block.empty?
                alternatives << result_of_inner_block
              end
              break
            end
          end
        elsif line[0] == TYPE_WHILE
          condition = line[1][0]
          inner_block = line[1][1]
          fail "assert" unless condition[0] == TYPE_CONDITION
          while evaluate_condition(namespace, condition)
            local_namespace = AyaNamespace.new(@dic.aya, :parent => namespace)
            result_of_inner_block = evaluate(local_namespace,
                                             inner_block, -1, 1)
            unless result_of_inner_block.nil?
              alternatives << result_of_inner_block
            end
            if @status == CODE_RETURN
              break
            end
            if @status == CODE_BREAK
              @status = CODE_NONE
              break
            end
            if @status == CODE_CONTINUE
              @status = CODE_NONE
            end
          end
        elsif line[0] == TYPE_FOR
          init = line[1][0][0]
          condition = line[1][0][1]
          reset = line[1][0][2]
          inner_block = line[1][1]
          evaluate(namespace, init, -1, 1)
          fail "assert" unless condition[0] == TYPE_CONDITION
          while evaluate_condition(namespace, condition)
            local_namespace = AyaNamespace.new(@dic.aya, :parent => namespace)
            result_of_inner_block = evaluate(local_namespace,
                                             inner_block, -1, 1)
            unless result_of_inner_block.nil?
              alternatives << result_of_inner_block
            end
            break if @status == CODE_RETURN
            if @status == CODE_BREAK
              @status = CODE_NONE
              break
            end
            if @status == CODE_CONTINUE
              @status = CODE_NONE
            end
            evaluate(namespace, reset, -1, 1)
          end
        elsif line[0] == TYPE_SWITCH
          index = evaluate_token(namespace, line[1][0])
          inner_block = line[1][1]
          begin
            index = Integer(index)
          rescue
            index = 0
          end
          local_namespace = AyaNamespace.new(@dic.aya, :parent => namespace)
          result_of_inner_block = evaluate(local_namespace,
                                           inner_block, index, 1)
          unless result_of_inner_block.nil? or
                [0, false].include?(result_of_inner_block) or
                result_of_inner_block.empty?
            alternatives << result_of_inner_block
          end
        elsif line[0] == TYPE_CASE
          left = evaluate_token(namespace, line[1][0])
          inner_blocks = line[1][1]
          n_blocks = inner_blocks.length
          default_result = nil
          break_flag = false
          for j in 0..n_blocks-1
            entry = inner_blocks[j]
            inner_block = entry[1]
            local_namespace = AyaNamespace.new(@dic.aya, :parent => namespace)
            unless entry[0].nil?
              value_min, value_max = entry[0]
              value_min = evaluate_statement(namespace, value_min, 1)
              value_max = evaluate_statement(namespace, value_max, 1)
              if value_min <= left and left <= value_max
                result_of_inner_block = evaluate(
                  local_namespace, inner_block, -1, 1)
                unless result_of_inner_block.nil? or
                      [0, false].include?(result_of_inner_block) or
                      result_of_inner_block.empty?
                  alternatives << result_of_inner_block
                  break_flag = true
                  break
                end
              end
            else
              default_result = evaluate(local_namespace,
                                        inner_block, -1, 1)
            end
          end
          unless break_flag
            unless default_result.nil? or default_result.empty?
              alternatives << default_result
            end
          end
        elsif line[0] == TYPE_STATEMENT
          result_of_func = evaluate_statement(namespace, line, 0)
          unless result_of_func.nil? or
                [0, false].include?(result_of_func) or
                result_of_func.empty?
            alternatives << result_of_func
          end
        else
          result_of_eval = evaluate_token(namespace, line)
          unless result_of_eval.nil? or
                [0, false].include?(result_of_eval) or
                result_of_eval.empty?
            alternatives << result_of_eval
          end
        end
      end
      if is_inner_block.zero?
        unless @sequential.nil?
          list_ = []
          for alt in result
            list_ << alt.length
          end
          if @sequential[0] != list_
            @sequential[0] = list_
            @sequential[1] = ([0] * result.length)
          else
            for index in 0..result.length-1
              current = @sequential[1][index]
              if current < result[index].length - 1
                @sequential[1][index] = (current + 1)
                break
              else
                @sequential[1][index] = 0
              end
            end
          end
        end
        unless @nonoverlap.nil?
          list_ = []
          for alt in result
            list_ << alt.length
          end
          if @nonoverlap[0] != list_
            @nonoverlap[0] = list_
            @nonoverlap[2] = []
          end
          if @nonoverlap[2].empty?
            @nonoverlap[2] << ([0] * result.length)
            while true
              new = []
              new.concat(@nonoverlap[2][-1])
              break_flag = false
              for index in 0..result.length-1
                if new[index] < result[index].length - 1
                  new[index] += 1
                  @nonoverlap[2] << new
                  break_flag = true
                  break
                else
                  new[index] = 0
                end
              end
              break unless break_flag
            end
          end
          next_ = Random.rand(0..@nonoverlap[2].length-1)
          @nonoverlap[1] = @nonoverlap[2][next_]
          @nonoverlap[2].delete(next_)
        end
        for index in 0..result.length-1
          if not @sequential.nil?
            result[index] = result[index][@sequential[1][index]]
          elsif not @nonoverlap.nil?
            result[index] = result[index][@nonoverlap[1][index]]
          else
            result[index] = result[index].sample
          end
        end
      end
      return nil if result.nil? or result.empty?
      return result[0] if result.length == 1
      return result.map {|s| s.to_s}.join('')
    end

    def substitute(namespace, left, ope, right)
      var_name = left[1][0]
      if var_name.start_with?('_')
        target_namespace = namespace
      else
        target_namespace = @dic.aya.get_global_namespace()
      end
      if left[0] != TYPE_ARRAY
        target_namespace.put(var_name, right)
      else
        index = evaluate_token(namespace, left[1][1])
        begin
          index = Integer(index)
        rescue
          Logging::Logging.debug('Could not convert ' + index.to_s + ' to an integer')
        else
          case ope
          when '='
            elem = right
          when ':='
            if right.is_a?(Integer)
              elem = right.to_f
            else
              elem = right
            end
          else
            return nil # should not reach here
          end
          target_namespace.put(var_name, elem, :index => index)
        end
      end
    end

    def evaluate_token(namespace, token)
      result = '' # default
      case token[0]
      when TYPE_TOKEN
        if not Re_b.match(token[1]).nil?
          pos = Re_d_.match(token[1]).start(0)
          result = token[1][pos..-1].to_i(2)
        elsif not Re_x.match(token[1]).nil?
          result = token[1].to_i(16)
        else
          func = @dic.get_function(token[1])
          system_functions = @dic.aya.get_system_functions()
          if not func.nil?
            result = func.call()
          elsif system_functions.exists(token[1])
            result = system_functions.call(namespace, token[1], [])
          elsif token[1].start_with?('random') # ver.3
            result = Random.rand(0..99)
          else
            if token[1].start_with?('_')
              target_namespace = namespace
            else
              target_namespace = @dic.aya.get_global_namespace()
            end
            if target_namespace.exists(token[1])
              result = target_namespace.get(token[1])
            end
          end
        end
      when TYPE_STRING_LITERAL
        result = token[1]
      when TYPE_STRING
        result = evaluate_string(namespace, token[1])
      when TYPE_INT
        result = token[1].to_i
      when TYPE_FLOAT
        result = token[1].to_f
      when TYPE_SYSTEM_FUNCTION
        system_functions = @dic.aya.get_system_functions()
        func_name = token[1][0]
        ##fail ["assert: ", 'function ', func_name, ' not found.'].join('') unless system_functions.exists(func_name)
        arguments = evaluate_argument(namespace, func_name,
                                      token[1][1], true)
        if func_name == 'CALLBYNAME'
          func = @dic.get_function(arguments[0])
          system_functions = @dic.aya.get_system_functions()
          if not func.nil?
            result = func.call()
          elsif system_functions.exists(arguments[0])
            result = system_functions.call(namespace, arguments[0], [])
          end
        elsif func_name == 'LOGGING'
          arguments.insert(0, token[1][2])
          arguments.insert(0, @name)
          arguments.insert(0, @dic.aya.logfile)
          result = system_functions.call(namespace, func_name, arguments)
        else
          result = system_functions.call(namespace, func_name, arguments)
        end
      when TYPE_FUNCTION
        func_name = token[1][0]
        func = @dic.get_function(func_name)
        ##fail ["assert: ", 'function ', func_name, ' not found.'].join('') unless func != nil
        arguments = evaluate_argument(namespace, func_name,
                                      token[1][1], false)
        result = func.call(:argv => arguments)
      when TYPE_ARRAY
        var_name = token[1][0]
        if var_name.start_with?('_')
          target_namespace = namespace
        else
          target_namespace = @dic.aya.get_global_namespace()
        end
        index = evaluate_token(namespace, token[1][1])
        begin
          index = Integer(index)
        rescue
          Logging::Logging.debug(
            'index of array has to be integer: ' + var_name.to_s + '[' + token[1][1].to_s + ']')
        else
          if var_name == 'random' # Ver.3
            result = Random.rand(0..index-1)
          elsif var_name == 'ascii' # Ver.3
            if 0 <= index and index < 0x80 ## FIXME
              result = index.chr
            else
              result = ' '
            end
          elsif target_namespace.exists(var_name)
            result = target_namespace.get(var_name, :index => index)
          end
        end
      when TYPE_VARIABLE
        var_name = token[1][0]
        if var_name.start_with?('_')
          target_namespace = namespace
        else
          target_namespace = @dic.aya.get_global_namespace()
        end
        if target_namespace.exists(var_name)
          result = target_namespace.get(var_name)
        end
      when TYPE_ARRAY_POINTER
        var_name = token[1][0]
        if var_name.start_with?('_')
          target_namespace = namespace
        else
          target_namespace = @dic.aya.get_global_namespace()
        end
        index = evaluate_token(namespace, token[1][1])
        begin
          index = Integer(index)
        rescue
          Logging::Logging.debug(
            'index of array has to be integer: ' + var_name.to_s + '[' + token[1][1].to_s + ']')
        else
          if var_name == 'random' # Ver.3
            result = Random.rand(0..index-1)
          elsif var_name == 'ascii' # Ver.3
            if 0 <= index and index < 0x80 ## FIXME
              result = index.chr
            else
              result = ' '
            end
          else
            value = target_namespace.get(var_name, :index => index)
            result = {'name' => var_name,
                      'index' => index,
                      'namespace' => target_namespace,
                      'value' => value}
          end
        end
      when TYPE_VARIABLE_POINTER
        var_name = token[1][0]
        if var_name.start_with?('_')
          target_namespace = namespace
        else
          target_namespace = @dic.aya.get_global_namespace()
        end
        value = target_namespace.get(var_name)
        result = {'name' => var_name,
                  'index' => nil,
                  'namespace' => target_namespace,
                  'value' => value}
      else
        Logging::Logging.debug('error in evaluate_token: ' + token.to_s)
      end
      return result
    end

    def evaluate_condition(namespace, condition)
      result = false
      return true if condition[1].nil?
      left = condition[1][0]
      ope = condition[1][1]
      right = condition[1][2]
      fail "assert" unless ope[0] == TYPE_OPERATOR
      case left[0]
      when TYPE_CONDITION
        left_result = evaluate_condition(namespace, left)
      when TYPE_STATEMENT
        left_result = evaluate_statement(namespace, left, 1)
      else
        left_result = evaluate_token(namespace, left)
      end
      case right[0]
      when TYPE_CONDITION
        right_result = evaluate_condition(namespace, right)
      when TYPE_STATEMENT
        right_result = evaluate_statement(namespace, right, 1)
      else
        right_result = evaluate_token(namespace, right)
      end
      case ope[1]
      when '=='
        result = (left_result == right_result)
      when '!='
        result = (left_result != right_result)
      when '_in_'
        if right_result.is_a?(String) and left_result.is_a?(String)
          if right_result.include?(left_result)
            result = true
          else
            result = false
          end
        else
          result = false
        end
      when '!_in_'
        if right_result.is_a?(String) and left_result.is_a?(String)
          unless right_result.include?(left_result)
            result = true
          else
            result = false
          end
        else
          result = false
        end
      when '<'
        if right_result.is_a?(String) != left_result.is_a?(String)
          left_result = left_result.to_f
          right_result = right_result.to_f
        end
        result = (left_result < right_result)
      when '>'
        if right_result.is_a?(String) != left_result.is_a?(String)
          left_result = left_result.to_f
          right_result = right_result.to_f
        end
        result = (left_result > right_result)
      when '<='
        if right_result.is_a?(String) != left_result.is_a?(String)
          left_result = left_result.to_f
          right_result = right_result.to_f
        end
        result = (left_result <= right_result)
      when '>='
        if right_result.is_a?(String) != left_result.is_a?(String)
          left_result = left_result.to_f
          right_result = right_result.to_f
        end
        result = (left_result >= right_result)
      when '||'
        result = (left_result or right_result)
      when '&&'
        result = (left_result and right_result)
      else
        #pass
      end
      return result
    end

    def evaluate_statement(namespace, statement, type_float)
      num = statement[1..-1].length
      return '' if num.zero?
      type_ = statement[0]
      token = statement[1]
      if type_ == TYPE_STATEMENT
        left = evaluate_statement(namespace, token, type_float)
      else
        left = evaluate_token(namespace, statement)
      end
      ##else
      ##  Logging::Logging.debug('illegal statement: ' + statement[1].join(' '))
      ##  return ''
      ##end
      if num == 3
        ##fail "assert" unless statement[2][0] == TYPE_OPERATOR
        ope = statement[2][1]
        type_ = statement[3][0]
        case type_
        when TYPE_INT
          token = statement[3][1]
          unless type_float.zero?
            right = token.to_f
          else
            right = token.to_i
          end
        when TYPE_FLOAT
          token = statement[3][1]
          unless type_float.zero?
            right = token.to_f
          else
            right = token.to_f.to_i
          end
        when TYPE_STATEMENT
          right = evaluate_statement(namespace, statement[3],
                                     type_float)
        else
          right = evaluate_token(namespace, statement[3])
        end
        result = operation(left, ope, right, type_float)
      else
        result = left
      end
      return result
    end

    def operation(left, ope, right, type_float)
      begin
        if not type_float.zero?
          left = Float(left)
          right = Float(right)
        elsif ope != '+' or \
             (not left.is_a?(String) and not right.is_a?(String))
          left = Integer(left)
          right = Integer(right)
        else
          left = left.to_s
          right = right.to_s
        end
      rescue
        left = left.to_s
        right = right.to_s
      end
      begin
        case ope
        when '+'
          return left + right
        when '-'
          return left - right
        when '*'
          return left * right
        when '/'
          if right.zero?
            return 0
          else
            if left.is_a?(Integer) and right.is_a?(Integer)
              return (left / right).to_i
            else
              return left / right
            end
          end
        when '%'
          return left % right
        end
      rescue
        Logging::Logging.debug(
          'illegal operation: ' + [left.to_s, ope.to_s, right.to_s].join(' '))
        return ''
      end
    end

    def get_block(parent, startpoint)
      result = []
      n_lines = parent.length
      inner_nest_level = 0
      for i in startpoint..n_lines-1
        inner_content = parent[i]
        if inner_content == '{'
          if inner_nest_level > 0
            result << inner_content
          end
          inner_nest_level += 1
        elsif inner_content == '}'
          inner_nest_level -= 1
          if inner_nest_level > 0
            result << inner_content
          end
        else
        result << inner_content
        end
        if inner_nest_level.zero?
          return i, result
        end
      end
      return startpoint, result
    end

    def evaluate_string(namespace, line)
      history = [] # %[n]
      buf = ''
      startpoint = 0
      system_functions = @dic.aya.get_system_functions()
      while startpoint < line.length
        pos = line.index('%', startpoint)
        if pos.nil? or pos < 0
          buf = [buf, line[startpoint..-1]].join('')
          startpoint = line.length
          next
        else
          unless pos.zero?
            buf = [buf, line[startpoint..pos-1]].join('')
          end
          startpoint = pos
        end
        endpoint = line.length
        for char in SPECIAL_CHARS
          pos = line[0..endpoint-1].index(char, startpoint + 2)
          if not pos.nil? and 0 < pos and pos < endpoint
            endpoint = pos
          end
        end
        if  line[startpoint + 1] == '[' # history
          if line[endpoint] != ']'
            Logging::Logging.debug(
              'unbalanced "%[" or illegal index in ' \
              'the string(' + line + ')')
            buf = ''
            break
          end
          index_token = parse_token(line[startpoint + 2..endpoint-1])
          index = evaluate_token(namespace, index_token)
          begin
            index = Integer(index)
          rescue
            Logging::Logging.debug(
              'illegal history index in the string(' + line + ')')
          else
            if 0 <= index and index < history.length
              buf = [buf, format(history[index])].join('')
            end
          end
          startpoint = (endpoint + 1)
          next
        end
        replaced = false
        while endpoint > (startpoint + 1)
          token = line[startpoint + 1..endpoint-1]
          if token == 'random' or token == 'ascii' # Ver.3
            if endpoint < line.length and \
              line[endpoint] == '['
              end_of_block = line.index(']', endpoint + 1)
              if end_of_block.nil? or end_of_block < 0
                Logging::Logging.debug(
                  'unbalanced "[" or illegal index in ' \
                  'the string(' + line + ')')
                startpoint = line.length
                buf = ''
                break
              end
              index = parse_token(line[endpoint + 1..end_of_block-1])
              content_of_var = evaluate_token(
                namespace, [TYPE_ARRAY, [token, index]])
              if content_of_var.nil?
                content_of_var = ''
              end
              history << content_of_var
              buf = [buf, format(content_of_var)].join('')
              startpoint = (end_of_block + 1)
              replaced = true
              break
            end
          end
          func = @dic.get_function(token)
          is_system_func = system_functions.exists(token)
          if not func.nil? or is_system_func
            if endpoint < line.length and \
              line[endpoint] == '('
              end_of_parenthesis = line.index(')', endpoint + 1)
              if end_of_parenthesis.nil? or end_of_parenthesis < 0
                Logging::Logging.debug(
                  'unbalanced "(" in the string(' + line + ')')
                startpoint = line.length
                buf = ''
                break
              end
              func_name = token
              arguments = parse_argument(
                line[endpoint + 1..end_of_parenthesis-1])
              arguments = evaluate_argument(
                namespace, func_name, arguments, is_system_func)
              if is_system_func
                if func_name == 'CALLBYNAME'
                  func = @dic.get_function(arguments[0])
                  if not func.nil?
                    result_of_func = func.call()
                  elsif system_functions.exists(arguments[0])
                    result_of_func = system_functions.call(
                      namespace, arguments[0], [])
                  end
                elsif func_name == 'LOGGING'
                  arguments.insert(
                    0, line[endpoint + 1..end_of_parenthesis-1])
                  arguments.insert(0, @name)
                  arguments.insert(0, @dic.aya.logfile)
                  result_of_func = system_functions.call(
                    namespace, func_name, arguments)
                else
                  result_of_func = system_functions.call(
                    namespace, func_name, arguments)
                end
              else
                result_of_func = func.call(:argv => arguments)
              end
              if result_of_func.nil?
                result_of_func = ''
              end
              history << result_of_func
              buf = [buf, format(result_of_func)].join('')
              startpoint = (end_of_parenthesis + 1)
              replaced = true
              break
            elsif not func.nil?
              result_of_func = func.call()
              history << result_of_func
              buf = [buf, format(result_of_func)].join('')
              startpoint = endpoint
              replaced = true
              break
            else
              result_of_func = system_functions.call(
                namespace, token, [])
              if result_of_func.nil?
                result_of_func = ''
              end
              history << result_of_func
              buf = [buf, format(result_of_func)].join('')
              startpoint = endpoint
              replaced = true
              break
            end
          else
            if token.start_with?('_')
              target_namespace = namespace
            else
              target_namespace = @dic.aya.get_global_namespace()
            end
            if target_namespace.exists(token)
              have_index = false
              index = nil
              if endpoint < line.length and line[endpoint] == '['
                end_of_block = line.index(']', endpoint + 1)
                if end_of_block.nil? or end_of_block < 0
                  Logging::Logging.debug(
                    'unbalanced "[" or ' \
                    'illegal index in the string(' + line + ')')
                  startpoint = line.length
                  buf = ''
                  break
                end
                have_index = true
                index_token = parse_token(
                  line[endpoint + 1..end_of_block-1])
                index = evaluate_token(namespace, index_token)
                begin
                  index = Integer(index)
                rescue
                  have_index = false
                  index = nil
                end
              end
              value = target_namespace.get(token, :index => index)
              unless value.nil?
                content_of_var = value
                history << content_of_var
                buf = [buf,
                       format(content_of_var)].join('')
                if have_index
                  startpoint = (end_of_block + 1)
                else
                  startpoint = endpoint
                end
                replaced = true
                break
              end
            end
          end
          endpoint -= 1
        end
        unless replaced
          buf = [buf, line[startpoint]].join('')
          startpoint += 1
        end
      end
      return buf
    end

    def format(input_num)
      if input_num.is_a?(Float)
        result = input_num.round(6).to_s
      else
        result = input_num.to_s
      end
      return result
    end

    def evaluate_argument(namespace, name, argument, is_system_func)
      arguments = []
      for i in 0..argument.length-1
        if is_system_func and \
          @dic.aya.get_system_functions().not_to_evaluate(name, i)
          ##fail "assert" unless [].include?(argument[i]) ## FIXME
          arguments << argument[i][1][1]
        else
          arguments << evaluate_statement(namespace,
                                          argument[i], 1)
        end
      end
      if is_system_func
        if name == 'NAMETOVALUE' and \
          arguments.length == 1 # this is kluge
          arguments[0] = evaluate_statement(namespace,
                                            argument[0], 1)
        end
      end
      return arguments
    end

    def is_substitution(line)
      statement = AyaStatement.new(line)
      if statement.countTokens() >= 3
        statement.next_token() # left
        ope = statement.next_token()
        ope_list = ['=', ':=',
                    '+=', '-=', '*=', '/=', '%=',
                    '+:=', '-:=', '*:=', '/:=', '%:=']
        if ope_list.include?(ope)
          return true
        end
      end
      return false
    end

    def is_inc_or_dec(line)
      if line.length <= 2
        return false
      end
      if line.end_with?('++') or line.end_with?('--')
        return true
      else
        return false
      end
    end
  end


  class AyaSystemFunctions

    def initialize(aya)
      @aya = aya
      @saori_statuscode = ''
      @saori_header = []
      @saori_value = {}
      @saori_protocol = ''
      @errno = 0
      @security = AyaSecurity.new(@aya)
      @functions = {
        'ARRAYSIZE' => ['ARRAYSIZE', [0, 1], [1, 2], nil],
        'ASC' => ['ASC', [nil], [1], nil],
        'BINSTRTONUM' => ['BINSTRTONUM', [nil], [1], nil],
        'CALLBYNAME' => ['CALLBYNAME', [nil], [1], nil],
        'CEIL' => ['CEIL', [nil], [1], nil],
        'COS' => ['COS', [nil], [1], nil],
        'CUTSPACE' => ['CUTSPACE', [nil], [1], nil],
        'ERASE' => ['ERASE', [nil], [3], nil],
        'ERASEVARIABLE' => ['ERASEVARIABLE', [nil], [1], nil],
        'FCLOSE' => ['FCLOSE', [nil], [1], nil],
        'FCOPY' => ['FCOPY', [nil], [2], 259],
        'FDELETE' => ['FDELETE', [nil], [1], 269],
        'FENUM' => ['FENUM', [nil], [1, 2], 290],
        'FLOOR' => ['FLOOR', [nil], [1], nil],
        'FMOVE' => ['FMOVE', [nil], [2], 264],
        'FOPEN' => ['FOPEN', [nil], [2], 256],
        'FREAD' => ['FREAD', [nil], [1], nil],
        'FRENAME' => ['FRENAME', [nil], [2], 273],
        'FSIZE' => ['FSIZE', [nil], [1], 278],
        ##'FUNCTIONEX' => ['FUNCTIONEX', [nil], [nil], nil], # FIXME # Ver.3
        'FWRITE' => ['FWRITE', [nil], [2], nil],
        'FWRITE2' => ['FWRITE2', [nil], [2], nil],
        'GETLASTERROR' => ['GETLASTERROR', [nil], [nil], nil],
        'HEXSTRTONUM' => ['HEXSTRTONUM', [nil], [1], nil],
        'IASC' => ['IASC', [nil], [1], nil],
        'INSERT' => ['INSERT', [nil], [3], nil],
        'ISFUNCTION' => ['ISFUNCTION', [nil], [1], nil],
        'ISINSIDE' => ['ISINSIDE', [nil], [3], nil],
        'ISINTEGER' => ['ISINTEGER', [nil], [1], nil],
        'ISREAL' => ['ISREAL', [nil], [1], nil],
        'LETTONAME' => ['LETTONAME', [nil], [2], nil],
        'LIB.HEADER' => ['LIB_HEADER', [nil], [1], nil],
        'LIB.KEY' => ['LIB_HEADER', [nil], [1], nil], # alias
        'LIB.PROTOCOL' => ['LIB_PROTOCOL', [nil], [0], nil],
        'LIB.STATUSCODE' => ['LIB_STATUSCODE', [nil], [0], nil],
        'LIB.VALUE' => ['LIB_VALUE', [nil], [1], nil],
        'LOADLIB' => ['LOADLIB', [nil], [1], 16],
        'LOG' => ['LOG', [nil], [1], nil],
        'LOG10' => ['LOG10', [nil], [1], nil],
        'LOGGING' => ['LOGGING', [nil], [4], nil],
        'MERASE' => ['MERASE', [nil], [3], nil],
        'MINSERT' => ['MINSERT', [nil], [3], nil],
        'MKDIR' => ['MKDIR', [nil], [1], 282],
        'MSTRLEN' => ['MSTRLEN', [nil], [1], nil],
        'MSTRSTR' => ['MSTRSTR', [nil], [3], nil],
        'MSUBSTR' => ['MSUBSTR', [nil], [3], nil],
        'NAMETOVALUE' => ['NAMETOVALUE', [0], [1, 2], nil],
        'POW' => ['POW', [nil], [2], nil],
        'RAND' => ['RAND', [nil], [0, 1], nil],
        'REPLACE' => ['REPLACE', [nil], [3], nil],
        'REQ.COMMAND' => ['REQ_COMMAND', [nil], [0], nil],
        'REQ.HEADER' => ['REQ_HEADER', [nil], [1], nil],
        'REQ.KEY' => ['REQ_HEADER', [nil], [1], nil], # alias
        'REQ.PROTOCOL' => ['REQ_PROTOCOL', [nil], [0], nil],
        'REQ.VALUE' => ['REQ_VALUE', [nil], [1], nil],
        'REQUESTLIB' => ['REQUESTLIB', [nil], [2], nil],
        'RMDIR' => ['RMDIR', [nil], [1], 286],
        'ROUND' => ['ROUND', [nil], [1], nil],
        ##'SAORI' => ['SAORI', [nil], [nil], nil], # FIXME # Ver.3
        'SETSEPARATOR' => ['SETSEPARATOR', [0], [2], nil],
        'SIN' => ['SIN', [nil], [1], nil],
        'SQRT' => ['SQRT', [nil], [1], nil],
        'STRLEN' => ['STRLEN', [1], [1, 2], nil],
        'STRSTR' => ['STRSTR', [3], [3, 4], nil],
        'SUBSTR' => ['SUBSTR', [nil], [3], nil],
        'TAN' => ['TAN', [nil], [1], nil],
        'TOBINSTR' => ['TOBINSTR', [nil], [1], nil],
        'TOHEXSTR' => ['TOHEXSTR', [nil], [1], nil],
        'TOLOWER' => ['TOLOWER', [nil], [1], nil],
        'TONUMBER' => ['TONUMBER', [0], [1], nil],
        'TONUMBER2' => ['TONUMBER2', [nil], [1], nil],
        'TOSTRING' => ['TOSTRING', [0], [1], nil],
        'TOSTRING2' => ['TOSTRING2', [nil], [1], nil],
        'TOUPPER' => ['TOUPPER', [nil], [1], nil],
        'UNLOADLIB' => ['UNLOADLIB', [nil], [1], nil]
      }
    end

    def exists(name)
      @functions.include?(name)
    end

    def call(namespace, name, argv)
      @errno = 0
      if @functions.include?(name) and \
         check_num_args(name, argv)
        return method(@functions[name][0]).call(namespace, argv)
      else
        return ''
      end
    end

    def not_to_evaluate(name, index)
      if @functions[name][1].include?(index)
        return true
      else
        return false
      end
    end

    def check_num_args(name, argv)
      list_num = @functions[name][2]
      return true if list_num == [nil]
      return true if list_num.include?(argv.length)
      list_num.sort!
      if argv.length < list_num[0]
        errno = @functions[name][3]
        @errno = errno unless errno.nil?
        Logging::Logging.debug(
          [name.to_s, ': called with too few argument(s)'].join(''))
        return false
      end
      return true
    end

    def ARRAYSIZE(namespace, argv)
      if argv[0].is_a?(String)
        line = argv[0]
        if line.nil? or line == ''
          value = 0
        elsif line.start_with?('"') and line.end_with?('"')
          value = (line.count(',') + 1)
        else
          target_namespace = select_namespace(namespace, line)
          value = target_namespace.get_size(line)
        end
      else
        value = 0
      end
      if argv.length == 2
        var = argv[1].to_s
        target_namespace = select_namespace(namespace, var)
        target_namespace.put(var, value)
        return nil
      else
        return value
      end
    end

    def ASC(namespace, argv)
      begin
        Integer(argv[0])
      rescue
        return ''
      end
      index = argv[0].to_i
      if 0 <= index and index < 0x80
        return index.chr
      else
        return ' '
      end
    end

    def BINSTRTONUM(namespace, argv)
      begin
        return Integer(argv[0].to_s, 2)
      rescue
        return -1
      end
    end

    def CALLBYNAME(namespace, argv) # dummy
      nil
    end

    def CEIL(namespace, argv)
      begin
        return math.ceil(Float(argv[0])).to_i
      rescue
        return -1
      end
    end

    def COS(namespace, argv)
      begin
        result = math.cos(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def CUTSPACE(namespace, argv)
      return argv[0].to_s.strip()
    end

    def ERASE(namespace, argv)
      line = argv[0].to_s.encode('CP932', :invalid => :replace, :undef => :replace) # XXX
      begin
        start = Integer(argv[1])
        bytes = Integer(argv[2])
      rescue
        return ''
      end
      return [line[0..start-1], line[start + bytes..-1]].join('').encode("UTF-8", :invalid => :replace, :undef => :replace) # XXX
    end

    def ERASEVARIABLE(namespace, argv)
      var = argv[0].to_s
      target_namespace = select_namespace(namespace, var)
      target_namespace.remove(var)
    end

    def FCLOSE(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      if @aya.filelist.include?(norm_path)
        @aya.filelist[norm_path].close()
        @aya.filelist.delete(norm_path)
      end
      return nil
    end

    def FCOPY(namespace, argv)
      src = Home.get_normalized_path(argv[0].to_s)
      head, tail = File.split(src)
      dst = [Home.get_normalized_path(argv[1].to_s), '/', tail].join('')
      src_path = File.join(@aya.aya_dir, src)
      dst_path = File.join(@aya.aya_dir, dst)
      result = 0
      if not File.file?(src_path)
        @errno = 260
      elsif not File.directory?(dst_path)
        @errno = 261
      elsif @security.check_path(src_path, :flag => 'r') == 1 and \
            @security.check_path(dst_path) == 1
        begin
          shutil.copyfile(src_path, dst_path)
        rescue
          @errno = 262
        else
          result = 1
        end
      else
        @errno = 263
      end
      return result
    end

    def FDELETE(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      result = 0
      if not File.file?(path)
        @errno = 270
      elsif @security.check_path(path) == 1
        begin
          File.delete(path)
        rescue
          @errno = 271
        else
          result = 1
        end
      else
        @errno = 272
      end
      return result
    end

    def FENUM(namespace, argv)
      if argv.length >= 2
        separator = argv[1].to_s
      else
        separator = ','
      end
      dirname = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, dirname)
      filelist = []
      if @security.check_path(path, :flag => 'r') == 1
        begin
          filelist = Dir.entries(path).reject{|entry| entry =~ /^\.{1,2}$/}
        rescue
          @errno = 291
        end
      else
        @errno = 292
      end
      result = ''
      for index in 0..filelist.length-1
        path = File.join(@aya.aya_dir, dirname, filelist[index])
        if File.directory?(path)
          result = [result, "\\"].join('')
        end
        result = [result, filelist[index]].join('')
        if index != (filelist.length - 1)
          result = [result, separator].join('')
        end
      end
      return result
    end

    def FLOOR(namespace, argv)
      begin
        return math.floor(Float(argv[0])).to_i
      rescue
        return -1
      end
    end

    def FMOVE(namespace, argv)
      src = Home.get_normalized_path(argv[0].to_s)
      head, tail = File.split(src)
      dst = [Home.get_normalized_path(argv[1].to_s), '/', tail].join('')
      src_path = File.join(@aya.aya_dir, src)
      dst_path = File.join(@aya.aya_dir, dst)
      result = 0
      head, tail = File.split(dst_path)
      if not File.file?(src_path)
        @errno = 265
      elsif not File.directory?(head)
        @errno = 266
      elsif @security.check_path(src_path) == 1 and \
            @security.check_path(dst_path) == 1
        begin
          File.rename(src_path, dst_path)
        rescue
          @errno = 267
        else
          result = 1
        end
      else
        @errno = 268
      end
      return result
    end

    def FOPEN(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      accessmode = argv[1].to_s
      result = 0
      path = File.join(@aya.aya_dir, filename)
      if @security.check_path(path, :flag => accessmode[0]) == 1
        norm_path = File.expand_path(path)
        if @aya.filelist.include?(norm_path)
          result = 2
        else
          begin
            @aya.filelist[norm_path] = open(path, accessmode[0], encoding='Shift_JIS')
          rescue
            @errno = 257
          else
            result = 1
          end
        end
      else
        @errno = 258
      end
      return result
    end

    def FREAD(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      result = -1
      if @aya.filelist.include?(norm_path)
        f = @aya.filelist[norm_path]
        result = f.readline()
        if result.nil?
          result = -1
        elsif result.end_with?("\r\n")
          result = result[0..-3]
        elsif result.end_with?("\n")
          result = result[0..-2]
        end
      end
      return result
    end

    def FRENAME(namespace, argv)
      src = Home.get_normalized_path(argv[0].to_s)
      dst = Home.get_normalized_path(argv[1].to_s)
      src_path = File.join(@aya.aya_dir, src)
      dst_path = File.join(@aya.aya_dir, dst)
      result = 0
      head, tail = File.split(dst_path)
      if not File.exist?(src_path)
        @errno = 274
      elsif not File.directory?(head)
        @errno = 275
      elsif @security.check_path(dst_path) == 1
        begin
          File.rename(src_path, dst_path)
        rescue
          @errno = 276
        else
          result = 1
        end
      else
        @errno = 277
      end
      return result
    end

    def FSIZE(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      size = -1
      if not File.exist?(path)
        @errno = 279
      elsif @security.check_path(path, :flag => 'r') == 1
        begin
          size = File.size(path)
        rescue
          @errno = 280
        end
      else
        @errno = 281
      end
      return size
    end

    def FUNCTIONEX(namespace, argv) # FIXME # Ver.3
      return nil
    end

    def FWRITE(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      data = [argv[1].to_s, "\n"].join('')
      if @aya.filelist.include?(norm_path)
        f = @aya.filelist[norm_path]
        f.write(data)
      end
      return nil
    end

    def FWRITE2(namespace, argv)
      filename = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, filename)
      norm_path = File.expand_path(path)
      data = argv[1].to_s
      if @aya.filelist.include?(norm_path)
        f = @aya.filelist[norm_path]
        f.write(data)
      end
      return nil
    end

    def GETLASTERROR(namespace, argv)
      @errno
    end

    def HEXSTRTONUM(namespace, argv)
      begin
        return Integer(argv[0].to_s, 16)
      rescue
        return -1
      end
    end

    def IASC(namespace, argv)
      return -1 unless argv[0].is_a?(String)
      begin
        code = argv[0][0].ord
      rescue
        return -1
      end
      return code
    end

    def INSERT(namespace, argv)
      line = argv[0].to_s.encode('CP932', :invalid => :replace, :undef => :replace) # XXX
      begin
        start = Integer(argv[1])
      rescue
        return ''
      end
      to_insert = argv[2].to_s.encode('CP932', :invalid => :replace, :undef => :replace) # XXX
      if start < 0
        start = 0
      end
      return [line[0..start-1], to_insert, line[start..-1]].join('').encode("UTF-8", :invalid => :replace, :undef => :replace) # XXX
    end

    def ISFUNCTION(namespace, argv)
      if not argv[0].is_a?(String)
        return 0
      elsif not @aya.dic.get_function(argv[0]).nil?
        return 1
      elsif @aya.get_system_functions().exists(argv[0])
        return 2
      else
        return 0
      end
    end

    def ISINSIDE(namespace, argv)
      if argv[1] <= argv[0] and argv[0] <= argv[2]
        return 1
      else
        return 0
      end
    end

    def ISINTEGER(namespace, argv)
      if argv[0].is_a?(Integer)
        return 1
      else
        return 0
      end
    end

    def ISREAL(namespace, argv)
      if argv[0].is_a?(Integer) or argv[0].is_a?(Float)
        return 1
      else
        return 0
      end
    end

    def LETTONAME(namespace, argv)
      var = argv[0].to_s
      value = argv[1]
      if var.nil? or var.empty?
        return nil
      end
      target_namespace = select_namespace(namespace, var)
      target_namespace.put(var, value)
      return nil
    end

    def LIB_HEADER(namespace, argv)
      begin
        Integer(argv[0])
      rescue
        return ''
      end
      result = ''
      header_list = @saori_header
      if not header_list.nil? and argv[0].to_i < header_list.length
        result = header_list[argv[0].to_i]
      end
      return result
    end

    def LIB_PROTOCOL(namespace, argv)
      @aya.saori_protocol
    end

    def LIB_STATUSCODE(namespace, argv)
      @saori_statuscode
    end

    def LIB_VALUE(namespace, argv)
      result = ''
      if argv[0].is_a?(Integer)
        header_list = @saori_header
        if not header_list.nil? and argv[0].to_i < header_list.length
          key = header_list[argv[0].to_i]
        end
      else
        key = argv[0].to_s
      end
      if @saori_value.include?(key)
        result = @saori_value[key]
      end
      return result
    end

    def LOADLIB(namespace, argv)
      dll = argv[0].to_s
      result = 0
      unless dll.empty?
        if @security.check_lib(dll) == 1
          result = @aya.saori_library.load(dll, @aya.aya_dir)
          if result.zero?
            @errno = 17
          end
        else
          @errno = 18
        end
      end
      return result
    end

    def LOG(namespace, argv)
      begin
        Float(argv[0])
      rescue
        return -1
      end
      if argv[0].to_f.zero?
        return 0
      end
      result = math.log(argv[0].to_f)
      return select_math_type(result)
    end

    def LOG10(namespace, argv)
      begin
        Float(argv[0])
      rescue
        return -1
      end
      if argv[0].to_f.zero?
        return 0
      end
      result = math.log10(argv[0].to_f)
      return select_math_type(result)
    end

    def LOGGING(namespace, argv)
      return nil if argv[0].nil?
      logfile = argv[0]
      line = ['> function ', argv[1].to_s, ' ： ', argv[2].to_s].join('')
      unless argv[3].nil?
        line = [line, ' = '].join('')
        if argv[3].is_a?(Integer) or argv[3].is_a?(Float)
          line = [line, argv[3].to_s].join('')
        else
          line = [line, '"', argv[3].to_s, '"'].join('')
        end
      end
      line = [line, "\n"].join('')
      logfile.write(line)
      logfile.write("\n")
      return nil
    end

    def MERASE(namespace, argv)
      line = argv[0].to_s
      begin
        start = Integer(argv[1])
        end_ = Integer(argv[2])
      rescue
        return ''
      end
      return [line[0..start-1], line[end_..-1]].join('')
    end

    def MINSERT(namespace, argv)
      line = argv[0].to_s
      begin
        start = Integer(argv[1])
      rescue
        return ''
      end
      to_insert = argv[2].to_s
      return [line[0..start-1], to_insert, line[start..-1]].join('')
    end

    def MKDIR(namespace, argv)
      dirname = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, dirname)
      result = 0
      head, tail = File.split(path)
      if not File.directory?(head)
        @errno = 283
      elsif @security.check_path(path) == 1
        begin
          Dir.mkdir(path, 0o755)
        rescue
          @errno = 284
        else
          result = 1
        end
      else
      @errno = 285
      end
      return result
    end

    def MSTRLEN(namespace, argv)
      argv[0].to_s.length
    end

    def MSTRSTR(namespace, argv)
      line = argv[0].to_s
      to_find = argv[1].to_s
      begin
        start = Integer(argv[2])
      rescue
        return -1
      end
      return line.rfind(to_find, start)
    end

    def MSUBSTR(namespace, argv)
      line = argv[0].to_s
      begin
        start = Integer(argv[1])
        end_ = Integer(argv[2])
      rescue
        return ''
      end
      return line[start..end_-1]
    end

    def NAMETOVALUE(namespace, argv)
      if argv.length == 2
        var = argv[0].to_s
        name = argv[1].to_s
      else
        name = argv[0].to_s
      end
      target_namespace = select_namespace(namespace, name)
      value = target_namespace.get(name)
      if argv.length == 2
        target_namespace = select_namespace(namespace, var)
        target_namespace.put(var, value)
        return nil
      else
        return value
      end
    end

    def POW(namespace, argv)
      begin
        result = math.pow(Float(argv[0]), Float(argv[1]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def RAND(namespace, argv)
      unless argv
        return Random.rand(0..99)
      else
        begin
          Integer(argv[0])
        rescue
          return -1
        end
        return Random.rand(0..argv[0].to_i-1)
      end
    end

    def REPLACE(namespace, argv)
      line = argv[0].to_s
      old = argv[1].to_s
      new = argv[2].to_s
      return line.gsub(old, new)
    end

    def REQ_COMMAND(namespace, argv)
      return @aya.req_command
    end

    def REQ_HEADER(namespace, argv)
      begin
        Integer(argv[0])
      rescue
        return ''
      end
      if @aya.req_key.length > argv[0].to_i
        return @aya.req_key[argv[0].to_i]
      else
        return ''
      end
    end

    def REQ_PROTOCOL(namespace, argv)
      @aya.req_protocol
    end

    def REQ_VALUE(namespace, argv)
      if argv[0].is_a?(Integer)
        name = REQ_HEADER(namespace, [argv[0]])
      else
        name = argv[0].to_s
      end
      if @aya.req_header.include?(name)
        return @aya.req_header[name]
      else
        return ''
      end
    end

    def REQUESTLIB(namespace, argv)
      response = @aya.saori_library.request(
        argv[0].to_s,
        argv[1].to_s.encode('Shift_JIS', :invalid => :replace, :undef => :replace)) ## FIXME
      header = response.encode("UTF-8", :invalid => :replace, :undef => :replace).split(/\r?\n/, 0)
      @saori_statuscode = ''
      @saori_header = []
      @saori_value = {}
      @saori_protocol = ''
      unless header.nil? or header.empty?
        line = header.shift
        line = line.strip()
        if line.include?(' ')
          @saori_protocol, @saori_statuscode = line.split(' ', 2)
          @saori_protocol.strip!
          @saori_statuscode.strip!
        end
        for line in header
          next unless line.include?(':')
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          unless key.empty?
            @saori_header << key
            @saori_value[key] = value
          end
        end
      end
      return nil
    end

    def RMDIR(namespace, argv)
      dirname = Home.get_normalized_path(argv[0].to_s)
      path = File.join(@aya.aya_dir, dirname)
      result = 0
      if not File.directory?(path)
        @errno = 287
      elsif @security.check_path(path) == 1
        begin
          Dir.rmdir(path)
        rescue
          @errno = 288
        else
          result = 1
        end
      else
        @errno = 289
      end
      return result
    end

    def ROUND(namespace, argv)
      begin
        value = math.floor(Float(argv[0]) + 0.5)
      rescue
        return -1
      end
      return value.to_i
    end

    def SAORI(namespace, argv) # FIXME # Ver.3
      return nil
    end

    def SETSEPARATOR(namespace, argv)
      name = argv[0].to_s
      separator = argv[1].to_s
      target_namespace = select_namespace(namespace, name)
      target_namespace.set_separator(name, separator)
      return nil
    end

    def SIN(namespace, argv)
      begin
        result = math.sin(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end
 
    def SQRT(namespace, argv)
      begin
        arg = Float(argv[0])
      rescue
        return -1
      end
      if arg < 0.0
        return -1
      else
        result = math.sqrt(arg)
        return select_math_type(result)
      end
    end

    def STRLEN(namespace, argv)
      line = argv[0].to_s.encode('CP932', :invalid => :replace, :undef => :replace) # XXX
      if argv.length == 2
        var = argv[1].to_s
        target_namespace = select_namespace(namespace, var)
        target_namespace.put(var, line.length)
        return nil
      else
        return line.length
      end
    end

    def STRSTR(namespace, argv)
      line = argv[0].to_s.encode('CP932', :invalid => :replace, :undef => :replace) # XXX
      to_find = argv[1].to_s.encode('CP932', :invalid => :replace, :undef => :replace) # XXX
      begin
        start = Integer(argv[2])
      rescue
        return -1
      end
      result = line.index(to_find, start)
      if argv.length == 4
        var = argv[3].to_s
        target_namespace = select_namespace(namespace, var)
        target_namespace.put(var, result)
        return nil
      else
        return result
      end
    end

    def SUBSTR(namespace, argv)
      line = argv[0].to_s.encode('CP932', :invalid => :replace, :undef => :replace) # XXX
      begin
        start = Integer(argv[1])
        num = Integer(argv[2])
      rescue
        return ''
      end
      return line[start..start + num-1].encode("UTF-8", :invalid => :replace, :undef => :replace) # XXX
    end

    def TAN(namespace, argv)
      begin
        result = math.tan(Float(argv[0]))
      rescue
        return -1
      end
      return select_math_type(result)
    end

    def TOBINSTR(namespace, argv)
      begin
        i = Integer(argv[0])
      rescue
        return ''
      end
      if i < 0
        i = abs(i)
        numsin = '-'
      else
        numsin = ''
      end
      line = ''
      while not i.zero?
        mod = (i % 2)
        i = (i / 2).to_i
        line = [mod.to_s, line].join('')
      end
      line = [numsin, line].join('')
      return line
    end

    def TOHEXSTR(namespace, argv)
      begin
        return Integer(argv[0]).to_s(16)
      rescue
        return ''
      end
    end

    def TOLOWER(namespace, argv)
      argv[0].to_s.downcase
    end

    def TONUMBER(namespace, argv)
      var = argv[0].to_s
      target_namespace = select_namespace(namespace, var)
      token = target_namespace.get(var)
      begin
        if token.include?('.')
          result = Float(token)
        else
          result = Integer(token)
        end
      rescue
        result = 0
      end
      target_namespace.put(var, result)
      return nil
    end

    def TONUMBER2(namespace, argv)
      token = argv[0].to_s
      begin
        if token.include?('.')
          value = Float(token)
        else
          value = Integer(token)
        end
      rescue
        return 0
      else
        return value
      end
    end

    def TOSTRING(namespace, argv)
      name = argv[0].to_s
      target_namespace = select_namespace(namespace, name)
      value = target_namespace.get(name).to_s
      target_namespace.put(name, value)
    end

    def TOSTRING2(namespace, argv)
      argv[0].to_s
    end

    def TOUPPER(namespace, argv)
      argv[0].to_s.upcase
    end

    def UNLOADLIB(namespace, argv)
      unless argv[0].to_s.empty?
        @aya.saori_library.unload(:name => argv[0].to_s)
      end
      return nil
    end

    def select_math_type(value)
      if math.floor(value) == value
        return value.to_i
      else
        return value
      end
    end

    def select_namespace(namespace, name)
      if name.start_with?('_')
        return namespace
      else
        return @aya.get_global_namespace()
      end
    end
  end


  class AyaNamespace

    def initialize(aya, parent: nil)
      @aya = aya
      @parent = parent
      @table = {}
    end

    def put(name, content, index: nil)
      if not @parent.nil? and @parent.exists(name)
        @parent.put(name, content, :index => index)
      elsif index.nil?
        unless exists(name)
          @table[name] = AyaVariable.new(name)
        end
        @table[name].put(content)
      elsif exists(name) and index >=0
        @table[name].put(content, :index => index)
      else
        #pass # ERROR
      end
    end

    def get(name, index: nil)
      if @table.include?(name)
        return @table[name].get(:index => index)
      elsif not @parent.nil? and @parent.exists(name)
        return @parent.get(name, :index => index)
      else
        return nil
      end
    end

    def set_separator(name, separator)
      if not @parent.nil? and @parent.exists(name)
        @parent.set_separator(name, separator)
      elsif @table.include?(name)
        @table[name].set_separator(separator)
      else
        #pass # ERROR
      end
    end

    def get_size(name)
      if @table.include?(name)
        return @table[name].get_size()
      elsif not @parent.nil? and @parent.exists(name)
        return @parent.get_size(name)
      else
        return 0
      end
    end

    def remove(name) # only works with local table
      if @table.include?(name)
        @table.delete(name)
      end
    end

    def exists(name)
      result = (@table.include?(name) or \
                (not @parent.nil? and @parent.exists(name)))
      return result
    end
  end


  class AyaGlobalNamespace < AyaNamespace

    SYS_VARIABLES = ['year', 'month', 'day', 'weekday',
                     'hour', '12hour', 'ampm', 'minute', 'second',
                     'systemuptickcount', 'systemuptime',
                     'systemuphour', 'systemupminute', 'systemupsecond',
                     'memoryload',
                     'memorytotalphys', 'memoryavailphys',
                     'memorytotalvirtual', 'memoryavailvirtual',
                     'random', 'ascii' # Ver.3
                    ] # except for 'aitalkinterval', etc.
    Re_res = Regexp.new('\Ares_reference\d+z')

    def reset_res_reference
      for key in @table.keys
        @table.delete(key) unless Re_res.match(key).nil?
      end
    end

    def get(name, index: nil)
      t = Time.now
      past = t - @aya.get_boot_time()
      result =
        case name
        when 'year'
          t.year
        when 'month'
          t.month
        when 'day'
          t.day
        when 'weekday'
          t.wday
        when 'hour'
          t.hour
        when '12hour'
          t.hour % 12
        when 'ampm'
          if t.hour >= 12
            1 # pm
          else
            0 # am
          end
        when 'minute'
          t.min
        when 'second'
          t.sec
        when 'systemuptickcount'
          (past * 1000.0).to_i
        when 'systemuptime'
          past.to_i
        when 'systemuphour'
          (past / 60.0 / 60.0).to_i
        when 'systemupminute'
          ((past / 60.0).to_i % 60)
        when 'systemupsecond'
          (past.to_i % 60)
        when 'memoryload', 'memorytotalphys', 'memoryavailphys',
             'memorytotalvirtual', 'memoryavailvirtual'
          0 # FIXME
        else
          super(name, :index => index)
        end
      return result
    end

    def exists(name)
      return true if SYS_VARIABLES.include?(name)
      return super(name)
    end

    def load_database(aya)
      begin
        open(aya.dbpath, 'rb') do |f|
          line = f.readline()
          unless line.start_with?('# Format: v1.0') or \
                line.start_with?('# Format: v1.1') or \
                line.start_with?('# Format: v2.1')
            return 1
          end
          if line.start_with?('# Format: v1.0') or \
            line.start_with?('# Format: v1.1')
            charset = 'EUC-JP' # XXX
          else
            charset = 'utf-8'
        end
          for line in f
            line = line.force_encoding(charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
            comma = line.index(',')
            if not comma.nil? and comma >= 0
              key = line[0..comma-1]
            else
              next
            end
            value = line[comma + 1..-1].strip()
            comma = Aya.find_not_quoted(value, ',')
            if not comma.nil? and comma >= 0
              separator = value[comma + 1..-1].strip()
              separator = separator[1..-2]
              value = value[0..comma-1].strip()
              value = value[1..-2]
              put(key, value.to_s)
              @table[key].set_separator(separator.to_s)
            elsif value.start_with?('"') # Format: v1.0
              value = value[1..-2]
              put(key, value.to_s)
            elsif value != 'None'
              if value.include?('.')
                put(key, value.to_f)
              else
                put(key, value.to_i)
              end
            else
              #pass
            end
          end
        end
      rescue
        return 1
      end
      return 0
    end

    def save_database
      begin
        open(@aya.dbpath, 'w') do |f|
          f.write("# Format: v2.1\n")
          for key in @table.keys()
            line = @table[key].dump()
            f.write([line, "\n"].join('')) unless line.nil?
          end
        end
      rescue #except IOError:
        Logging::Logging.debug('aya.py: cannot write database (ignored)')
        return
      end
    end
  end


  class AyaStatement
    attr_reader :tokens

    SPECIAL_CHARS = '=+-*/<>|&!:'

    def initialize(line)
      @n_tokens = 0
      @tokens = []
      @position_of_next_token = 0
      tokenize(line)
    end

    def tokenize(line)
      token_startpoint = 0
      block_nest_level = 0
      length = line.length
      i = 0
      while i < length
        c = line[i]
        if c == '('
          block_nest_level += 1
          i += 1
        elsif c == ')'
          block_nest_level -= 1
          i += 1
        elsif c == '"'
          if block_nest_level.zero?
            unless i.zero?
              append_unless_empty(line[token_startpoint..i-1].strip())
              token_startpoint = i
            end
          end
          position = i
          while position < (length - 1)
            position += 1
            if line[position] == '"'
              break
            end
          end
          i = position
          if block_nest_level.zero?
            @tokens << line[token_startpoint..position]
            token_startpoint = (position + 1)
          end
          i += 1
        elsif block_nest_level.zero? and (c == ' ' or c == "\t")
          append_unless_empty(line[token_startpoint..i-1].strip())
          i += 1
          token_startpoint = i
        elsif block_nest_level.zero? and line[i] == '　'
          append_unless_empty(line[token_startpoint..i-1].strip())
          i += 1
          token_startpoint = i
        elsif block_nest_level.zero? and \
             line[i..-1].strip()[0..3] == '_in_'
          append_unless_empty(line[token_startpoint..i-1].strip())
          @tokens << '_in_'
          i += 4
          token_startpoint = i
        elsif block_nest_level.zero? and \
             line[i..-1].strip()[0..4] == '!_in_'
          append_unless_empty(line[token_startpoint..i-1].strip())
          @tokens << '!_in_'
          i += 5
          token_startpoint = i
        elsif block_nest_level.zero? and SPECIAL_CHARS.include?(c)
          append_unless_empty(line[token_startpoint..i-1].strip())
          ope_list = [':=', '+=', '-=', '*=', '/=', '%=',
                      '<=', '>=', '==', '!=', '&&', '||',
                      '+:=', '-:=', '*:=', '/:=', '%:=']
          if ope_list.include?(line[i..i + 1])
            @tokens << line[i..i + 1]
            i += 2
            token_startpoint = i
          elsif ope_list.include?(line[i..i + 2])
            @tokens << line[i..i + 2]
            i += 3
            token_startpoint = i
          else
            @tokens << line[i..i]
            i += 1
            token_startpoint = i
          end
        else
          i += 1
        end
      end
      append_unless_empty(line[token_startpoint..-1].strip())
      @n_tokens = @tokens.length
    end

    def append_unless_empty(token)
      @tokens << token unless token.nil? or token.empty?
    end

    def has_more_tokens
      (@position_of_next_token < @n_tokens)
    end

    def countTokens
      @n_tokens
    end

    def next_token
      return nil unless has_more_tokens()
      result = @tokens[@position_of_next_token]
      @position_of_next_token += 1
      return result
    end
  end


  class AyaVariable

    TYPE_STRING = 0
    TYPE_INT = 1
    TYPE_REAL = 2
    TYPE_ARRAY = 3

    def initialize(name)
      @name = name
      @line = ''
      @separator = ','
      @type = nil
      @array = []
    end

    def set_separator(separator)
      return if @type != TYPE_STRING
      @separator = separator
      reset()
    end

    def reset
      return if @type != TYPE_STRING
      @position = 0
      @is_empty = false
      @array = []
      while not @is_empty
        separator_position = @line.index(@separator, @position)
        if separator_position.nil?
          token = @line[@position..-1]
          @is_empty = true
        else
          token = @line[@position..separator_position-1]
          @position = separator_position + @separator.length
        end
        @array << token
      end
    end

    def get_size
      @array.length
    end

    def get(index: nil)
      if index.nil?
        case @type
        when TYPE_STRING
          return @line.to_s
        when TYPE_INT
          return @line.to_i
        when TYPE_REAL
          return @line.to_f
        else
          return ''
        end
      elsif 0 <= index and index < @array.length
        value = @array[index]
        case @type
        when TYPE_STRING
          return value.to_s
        when TYPE_INT
          return value.to_i
        when TYPE_REAL
          return value.to_f
        when TYPE_ARRAY
          return value
        else
          return nil # should not reach here
        end
      else
        return ''
      end
    end

    def put(value, index: nil)
      if index.nil?
        @line = value.to_s
        if value.is_a?(String)
          @type = TYPE_STRING
        elsif value.is_a?(Integer)
          @type = TYPE_INT
        elsif value.is_a?(Float)
          @type = TYPE_REAL
        elsif value.is_a?(Array)
          @type = TYPE_ARRAY
          @array = value
        end
        reset()
      elsif index < 0
        #pass
      else
        if @type == TYPE_STRING
          @line = ''
          for i in 0..@array.length-1
            if i == index
              @line = [@line, value.to_s].join('')
            else
              @line = [@line, @array[i]].join('')
            end
            if i != (@array.length - 1)
              @line = [@line, @separator].join('')
            end
          end
          if index >= @array.length
            for i in @array.length..index
              if i == index
                @line = [@line, @separator,
                         value.to_s].join('')
              else
                @line = [@line, @separator,
                         ''].join('')
              end
            end
          end
          reset()
        elsif @type == TYPE_ARRAY
          if 0 <= index and index < @array.length
            @array[index] = value
          end
        else
          #pass # ERROR
        end
      end
    end

    def dump
      line = nil
      if @type == TYPE_STRING
        line = (@name.to_s + ', "' + @line.to_s + '", "' + @separator.to_s + '"')
      elsif @type != TYPE_ARRAY
        line = (@name.to_s + ', ' + @line.to_s)
      else
        #pass
      end
      return line
    end
  end


  class AyaArgument

    def initialize(line)
      @line = line.strip()
      @length = @line.length
      @current_position = 0
    end

    def has_more_tokens
      return (@current_position != -1 and \
              @current_position < @length)
    end

    def next_token
      return nil unless has_more_tokens()
      startpoint = @current_position
      @current_position = position_of_next_token()
      if @current_position == -1
        token = @line[startpoint..-1]
      else
        token = @line[startpoint..@current_position-2]
      end
      return token.strip()
    end

    def position_of_next_token
      locked = true
      position = @current_position
      parenthesis_nest_level = 0
      while position < @length
        c = @line[position]
        case c
        when '"'
          return position unless locked
          while position < (@length - 1)
            position += 1
            if @line[position] == '"'
              break
            end
          end
        when '('
          parenthesis_nest_level += 1
        when ')'
          parenthesis_nest_level -= 1
        when ','
          if parenthesis_nest_level.zero?
            locked = false
          end
        else
          return position unless locked
        end
        position += 1
      end
      return -1
    end
  end


  class AyaSaoriLibrary

    def initialize(saori, top_dir)
      @saori_list = {}
      @saori = saori
    end

    def load(name, top_dir)
      result = 0
      head, name = File.split(name.gsub("\\", '/')) # XXX: don't encode here
      top_dir = File.join(top_dir, head)
      unless @saori.nil? or @saori_list.include?(name)
        module_ = @saori.request(name)
        @saori_list[name] = module_ unless module_.nil?
      end
      if @saori_list.include?(name)
        result = @saori_list[name].load(:dir => top_dir)
      end
      return result
    end

    def unload(name: nil)
      unless name.nil?
        name = File.split(name.gsub("\\", '/'))[-1] # XXX: don't encode here
        if @saori_list.include?(name)
          @saori_list[name].unload()
          @saori_list.delete(name)
        end
      else
        for key in @saori_list.keys()
          @saori_list[key].unload()
        end
      end
      return nil
    end

    def request(name, req)
      result = '' # FIXME
      name = File.split(name.gsub("\\", '/'))[-1] # XXX: don't encode here
      if not name.nil? and @saori_list.include?(name)
        result = @saori_list[name].request(req)
      end
      return result
    end
  end
end
