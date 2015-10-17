# -*- coding: utf-8 -*-
#
#  kawari.rb - a "華和梨" compatible Shiori module for ninix
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#


require 'base64'

require_relative "../home"
require_relative "../logging"


module Kawari

  ###   READER   ###
  $charset = 'CP932' # default

  def self.read_dict(path)
    open(path, 'rb') do |f|
      lineno = 0
      buf = []
      for line in f
        lineno = lineno + 1
        position = [lineno, path]
        if line.start_with?('!KAWA0000')
          line = Kawari.decrypt(line[9..-1]).force_encoding($charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
        else
          line = line.force_encoding($charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
        end
        if line.strip.empty? or \
          line.start_with?('#') or \
          line.start_with?(':crypt') or \
          line.start_with?(':endcrypt')
          next
        end
        if not line.include?(':')
          Logging::Logging.debug('kawari.rb: syntax error at line ' + position[0].to_s + ' in ' + position[1].to_s)
          Logging::Logging.debug(line.strip())
          next
        end
        entries, phrases = line.split(':', 2)
        entries.strip!
        phrases.strip!
        if entries.empty?
          Logging::Logging.debug('kawari.rb: syntax error at line ' + position[0].to_s + ' in ' + position[1].to_s)
          Logging::Logging.debug(line.strip())
          next
        end
        if phrases.empty?
          next
        end
        if entries == 'locale'
          if not Encoding.name_list.include?(phrases)
            Logging::Logging.error('kawari.rb: unsupported charset ' + phrases.to_s)
          else
            $charset = phrases
          end
        end
        buf << [entries, phrases, position]
      end
      return buf
    end
  end

  def self.decrypt(data)
    buf = []
    for c in Base64.decode64(data).each_char
      buf << (c.ord ^ 0xcc).chr
    end
    return buf.join('')
  end

  def self.encrypt(data)
    buf = []
    for c in data
      buf << (c.ord ^ 0xcc).chr
    end
    line = ['!KAWA0000', Base64.encode64(buf.join(''))].join('')
    return line.gsub("\n", '')
  end

  def self.create_dict(buf)
    rdict = {} # rules
    kdict = {} # keywords
    for entries, phrases, position in buf
      parsed_entries = Kawari.parse_entries(entries)
      parsed_phrases = Kawari.parse_phrases(phrases)
      if parsed_phrases == nil
        Logging::Logging.debug('kawari.rb: syntax error at line ' + position[0].to_s + ' in ' + position[1].to_s + ':')
        Logging::Logging.debug(phrases.strip())
        next
      end
      if entries.start_with?('[')
        Kawari.add_phrases(kdict, parsed_entries, parsed_phrases)
        next
      end
      for entry in parsed_entries
        Kawari.add_phrases(rdict, entry, parsed_phrases)
      end
    end
    return rdict, kdict
  end

  def self.add_phrases(dic, entry, phrases)
    if not dic.include?(entry)
      dic[entry] = []
    end
    for phrase in phrases
      if phrase
        phrase[0]  = phrase[0].lstrip()
        phrase[-1] = phrase[-1].rstrip()
      end
      dic[entry] << phrase
    end
  end

  def self.parse_entries(data)
    if data.start_with?('[') and data.end_with?(']')
      entries = []
      i = 0
      j = data.length
      while i < j
        if data[i] == '"'
          i, text = Kawari.parse_quotes(data, i)
          entries << text
        else
          i += 1
        end
      end
    else
      entries = data.split(',', 0).map {|s| s.strip }
    end
    return entries
  end

  Re_comma = Regexp.new('^,')

  def self.parse_phrases(data)
    buf = []
    i = 0
    j = data.length
    while i < j
      if data[i] == ','
        i += 1
      end
      i, phrase = Kawari.parse(data, i, Re_comma)
      if not phrase.empty?
        buf << phrase
      end
    end
    return buf
  end

  def self.parse(data, start, stop_pattern=nil)
    buf = []
    i = start
    j = data.length
    while i < j
      if stop_pattern and stop_pattern.match(data[i..-1])
        break
      elsif data[i] == '"'
        i, text = Kawari.parse_quotes(data, i)
        buf << '"' + text + '"'
      elsif data[i..i + 1] == '${'
        i, text = Kawari.parse_reference(data, i)
        buf << text
      elsif data[i..i + 1] == '$('
        i, text = Kawari.parse_inline_script(data, i)
        buf << text
      elsif data[i] == '$'
        buf << data[i]
        i += 1
      elsif data[i] == ';'
        buf << data[i]
        i += 1
      else
        i, text = Kawari.parse_text(data, i, stop_pattern)
        buf << text
      end
    end
    if not buf.empty?
      if Kawari.is_space(buf[0])
        buf.delete_at(0)
      else
        buf[0] = buf[0].lstrip()
      end
    end
    if not buf.empty?
      if Kawari.is_space(buf[-1])
        buf.delete_at(-1)
      else
        buf[-1] = buf[-1].rstrip()
      end
    end
    return i, buf
  end

  def self.parse_quotes(data, start)
    buf = []
    i = start + 1
    j = data.length
    while i < j
      if data[i] == '"'
        i += 1
        break
      elsif data[i] == '\\'
        i += 1
        if i < j and data[i] == '"'
          buf << ['\\', data[i]].join('')
          i += 1
        else
          buf << '\\'
        end
      else
        buf << data[i]
        i += 1
      end
    end
    return i, buf.join('')
  end

  def self.parse_reference(data, start)
    i = start
    j = data.length
    while i < j
      if data[i] == '}'
        i += 1
        break
      else
        i += 1
      end
    end
    return i, data[start..i-1]
  end

  def self.parse_inline_script(data, start)
    buf = ['$']
    i = start + 1
    j = data.length
    npar = 0
    while i < j
      #begin specification bug work-around (1/3)
      if data[i] == ')'
        buf << data[i]
        i += 1
        break
      end
      #end
      if data[i] == '"'
        i, text = Kawari.parse_quotes(data, i)
        buf << '"' + text.to_s + '"'
      elsif data[i..i + 1] == '${'
        i, text = Kawari.parse_reference(data, i)
        buf << text
      elsif data[i..i + 1] == '$('
        i, text = Kawari.parse_inline_script(data, i)
        buf << text
      else
        if data[i] == '('
          npar = npar + 1
        elsif data[i] == ')'
          npar = npar - 1
        end
        buf << data[i]
        i += 1
      end
      if npar == 0
        break
      end
    end
    return i, buf.join('')
  end

  def self.is_space(s)
    return s.strip.empty?
  end

  def self.parse_text(data, start, stop_pattern=nil)
    condition = Kawari.is_space(data[start])
    i = start
    j = data.length
    while i < j
      if stop_pattern and stop_pattern.match(data[i..-1])
        break
      elsif ['$', '"'].include?(data[i])
        break
      elsif Kawari.is_space(data[i]) != condition
        break
      elsif data[i] == ';'
        if i == start
          i += 1
        end
        break
      else
        i += 1
      end
    end
    return i, data[start..i-1]
  end

  def self.read_local_script(path)
    rdict = {}
    kdict = {}
    open(path, :encoding => $charset) do |f|
      while line = f.gets
        if line.start_with?('#')
          rdict[line.strip()] = [f.readline().strip()]
        end
      end
    end
    return rdict, kdict
  end

  ###   KAWARI   ###

  class Kawari7

    MAXDEPTH = 30

    def initialize(prefix, pathlist, rdictlist, kdictlist)
      kawari_init(prefix, pathlist, rdictlist, kdictlist)
    end

    def kawari_init(prefix, pathlist, rdictlist, kdictlist)
      @prefix = prefix
      @pathlist = pathlist
      @rdictlist = rdictlist
      @kdictlist = kdictlist
      @system_entries = {}
      @expr_parser = ExprParser.new()
      #begin specification bug work-around (2/3)
      @expr_parser.kawari = self
      #end
      @otherghost = {}
      get_system_entry('OnLoad')
    end

    def finalize
      get_system_entry('OnUnload')
    end

    # SHIORI/1.0 API
    def getaistringrandom
      return get('sentence')
    end

    def getaistringfromtargetword(word)
      return get('sentence') # XXX
    end

    def getdms
      return getword('dms')
    end

    def getword(word_type)
      for delimiter in ['.', '-']
        name = ['compatible', delimiter, word_type].join('')
        script = get(name, default=nil)
        if script != nil
          return script.strip()
        end
      end
      return ''
    end

    def getstring(name)
      return get('resource.' + name.to_s)
    end

    # SHIORI/2.2 API
    def get_event_response(event,
                           ref0=nil, ref1=nil, ref2=nil, ref3=nil,
                           ref4=nil, ref5=nil, ref6=nil, ref7=nil) ## FIXME
      ref = [ref0, ref1, ref2,ref3, ref4, ref5, ref6, ref7].map {|r| r.to_s if r != nil }
      for i in 0..7
        if ref[i] != nil
          value = ref[i]
          @system_entries['system.Reference' + i.to_s] = value
          @system_entries['system-Reference' + i.to_s] = value
        end
      end
      script = nil
      if event == 'OnCommunicate'
        @system_entries['system.Sender'] = ref[0]
        @system_entries['system-Sender'] = ref[0]
        @system_entries['system.Sender.Path'] = 'local' # (local/unknown/external)
        @system_entries['system-Sender.Path'] = 'local' # (local/unknown/external)
        if not @system_entries.include?('system.Age')
          @system_entries['system.Age'] = '0'
          @system_entries['system-Age'] = '0'
        end
        @system_entries['system.Sentence'] = ref[1]
        @system_entries['system-Sentence'] = ref[1]
        if @otherghost.include?(ref[0])
          s0, s1 = @otherghost[ref[0]]
          @system_entries['system.Surface'] = [s0.to_s,
                                               s1.to_s].join(',')
          @system_entries['system-Surface'] = [s0.to_s,
                                               s1.to_s].join(',')
        end
        script = get_system_entry('OnResponse')
        if not script
          for dic in @kdictlist
            for entry in dic
              break_flag = false
              for word in entry
                if not ref[1].include?(word)
                  break_flag = true
                  break
                end
              end
              if not break_flag
                script = expand(dic[entry].sample)
                break
              end
            end
          end
        end
        if not script
          script = get_system_entry('OnResponseUnknown')
        end
        if script != nil
          script = script.strip()
        end
      else
        for delimiter in ['.', '-']
          name = ['event', delimiter, event].join('')
          script = get(name, default=nil)
          if script != nil
            script = script.strip()
            break
          end
        end
      end
      if script != nil
        script = script
      end
      return script
    end

    # SHIORI/2.4 API
    def teach(word)
      @system_entries['system.Sentence'] = word
      @system_entries['system-Sentence'] = word
      return get_system_entry('OnTeach')
    end

    def get_system_entry(entry)
      for delimiter in ['.', '-']
        name = ['system', delimiter, entry].join('')
        script = get(name, default=nil)
        if script != nil
          return script.strip()
        end
      end
      return nil
    end

    def otherghostname(ghost_list)
      ghosts = []
      for ghost in ghost_list
        name, s0, s1 = ghost.split(1.chr, 3)
        ghosts << [name, s0, s1]
        @otherghost[name] = [s0, s1]
      end
      otherghost_name = []
      for ghost in ghosts
        otherghost_name << ghost[0]
      end
      @system_entries['system.OtherGhost'] = otherghost_name
      @system_entries['system-OtherGhost'] = otherghost_name
      otherghost_ex = []
      for ghost in ghosts
        otherghost_ex << ghost.join(1.chr)
      end
      @system_entries['system.OtherGhostEx'] = otherghost_ex
      @system_entries['system-OtherGhostEx'] = otherghost_ex
      if not ghosts.empty?
        get_system_entry('OnNotifyOther')
      end
      return ''
    end

    def communicate_to
      communicate = get_system_entry('communicate')
      if communicate
        if communicate == 'stop'
          @system_entries['system.Age'] = '0'
          @system_entries['system-Age'] = '0'
          communicate = nil
        else
          if @system_entries.include?('system.Age')
            age = @system_entries['system.Age'].to_i + 1
            @system_entries['system.Age'] = age.to_s
            @system_entries['system-Age'] = age.to_s
          else
            @system_entries['system.Age'] = '0'
            @system_entries['system-Age'] = '0'
          end
        end
      end
      clear('system.communicate')
      if communicate != nil
        communicate = communicate
      end
      return communicate
    end

    # internal
    def clear(name)
      Logging::Logging.debug('*** clear("' + name.to_s + '")')
      for dic in @rdictlist
        if dic.include?(name)
          dic.delete(name)
        end
      end
    end

    def get_internal_dict(name)
      break_flag = false
      for dic in @rdictlist
        if dic.include?(name)
          break_flag = true
          break
        end
      end
      if not break_flag
        dic = @rdictlist[0]
        dic[name] = []
      end
      return dic
    end

    def unshift(name, value)
      Logging::Logging.debug('*** unshift("' + name.to_s + '", "' + value.to_s + '")')
      dic = get_internal_dict(name)
      i, segments = Kawari.parse(value, 0)
      dic[name].insert(0, segments)
    end

    def shift(name)
      dic = get_internal_dict(name)
      value = expand(dic[name].shift)
      Logging::Logging.debug('*** shift("' + name.to_s + '") => "' + value.to_s + '"')
      return value
    end

    def push(name, value)
      Logging::Logging.debug('*** push("' + name.to_s + '", "' + value.to_s + '")')
      dic = get_internal_dict(name)
      i, segments = Kawari.parse(value, 0)
      dic[name] << segments
    end

    def pop(name)
      dic = get_internal_dict(name)
      value = expand(dic[name].pop())
      Logging::Logging.debug('*** pop("' + name.to_s + '") => "' + value.to_s + '"')
      return value
    end

    def set(name, value)
      clear(name)
      push(name, value)
    end

    def get(name, context=nil, depth=0, default='')
      if depth == MAXDEPTH
        return ''
      end
      if name and name.start_with?('@')
        segments = context[name].sample
      else
        if not name.include?('&')
          selection = select_simple_phrase(name)
        else
          selection = select_compound_phrase(name)
        end
        if selection == nil
          Logging::Logging.debug('${{' + name.to_s + '}} not found')
          return default
        end
        segments, context = selection
      end
      Logging::Logging.debug([name, '=>', segments].join(''))
      return expand(segments, context, depth)
    end

    def parse_all(data, start=0)
      i, segments = Kawari.parse(data, start)
      return expand(segments)
    end

    def parse_sub(data, start=0, stop_pattern=nil)
      i, segments = Kawari.parse(data, start, stop_pattern)
      return i, expand(segments)
    end

    def expand(segments, context=nil, depth=0)
      buf = []
      references = []
      i = 0
      j = segments.length
      while i < j
        segment = segments[i]
        if not segment
          #pass
        elsif segment.start_with?('${') and segment.end_with?('}')
          newname = segment[2..-2]
          if is_number(newname)
            begin
              segment = references[Integer(newname)]
            rescue #except IndexError:
              #pass
            end
          elsif is_system_entry(newname)
            if ['system.OtherGhost', 'system-OtherGhost',
                'system.OtherGhostEx',
                'system-OtherGhostEx'].include?(newname)
              segment_list = @system_entries[newname]
              if segment_list
                segment = segment_list.sample
              else
                segment = ''
              end
            elsif newname == 'system.communicate'
              segment = get_system_entry('communicate')
            else
              segment = @system_entries.include?(newname) ? @system_entries[newname] : segment
            end
          else
            segment = get(newname, context, depth + 1)
          end
          references << segment
        elsif segment.start_with?('$(') and segment.end_with?(')')
          i, segment = eval_inline_script(segments, i)
        elsif segment.start_with?('"') and segment.end_with?('"')
          segment = segment[1..-2].gsub('\\"', '"')
        end
        buf << segment
        i += 1
      end
      return buf.join('')
    end

    def atoi(s)
      begin
        return Integer(s)
      rescue #except ValueError:
        return 0
      end
    end

    def is_number(s)
      begin
        Integer(s)
      rescue #except ValueError:
        return false
      end
      return true
    end

    def is_system_entry(s)
      return (s.start_with?('system-') or s.start_with?('system.'))
    end

    def select_simple_phrase(name)
      n = 0
      buf = []
      for d in @rdictlist
        if d.include?(name)
          c = d[name]
        else
          c = []
        end
        n += c.length
        buf << [c, d]
      end
      if n == 0
        return nil
      end
      n = rand(0..n-1)
      for c, d in buf
        m = c.length
        if n < m
          break
        end
        n -= m
      end
      return c[n], d        
    end

    def select_compound_phrase(name)
      buf = []
      for name in name.split('&', 0).map {|s| s.strip }
        cp_list = []
        for d in @rdictlist
          cp_list.concat(d.include?(name) ? d[name] : [])
        end
        buf << cp_list
      end
      buf = buf.map {|x| [x.length, x] }
      buf.sort()
      buf = buf.map {|x| x[1] }
      candidates = []
      for item in buf.shift
        break_flag = false
        for cp_list in buf
          if not cp_list.include?(item)
            break_flag = true
            break
          end
        end
        if not break_flag
          candidates << item
        end
      end
      if candidates.empty?
        return nil
      end
      return candidates.sample, nil
    end

    def eval_inline_script(segments, i)
      # check old 'if' syntax
      if segments[i].start_with?('$(if ') and i + 1 < segments.length and \
        segments[i + 1].start_with?('$(then ')
        if_block = segments[i][5..-2].strip()
        i += 1
        then_block = segments[i][7..-2].strip()
        if i + 1 < segments.length and segments[i + 1].start_with?('$(else ')
          i += 1
          else_block = segments[i][7..-2].strip()
        else
          else_block = ''
        end
        if i + 1 < segments.length and segments[i + 1] == '$(endif)'
          i += 1
        else
          Logging::Logging.debug('kawari.rb: syntax error: $(endif) expected')
          return i, '' # syntax error
        end
        return i, exec_old_if(if_block, then_block, else_block)
      end
      # execute command(s)
      values = []
      for command in split_commands(segments[i][2..-2])
        argv = parse_argument(command)
        argv[0] = expand(argv[0])
        if argv[0] == 'silent'
          if argv.length == 1
            values = []
          else
            Logging::Logging.debug(
              ['kawari.rb: syntax error:', segments[i]].join(''))
          end
          next
        end
        handler = @kis_commands[argv[0]]
        begin
          if handler == nil
            raise RuntimeError.new('invalid command')
          end
          values << method(handler).call(argv)
        rescue => message #except RuntimeError as message:
          Logging::Logging.debug(
            'kawari.rb: ' + message.to_s + ': ' + segments[i].to_s)
        end
      end
      result = values.join('')
      Logging::Logging.debug(['>>>', segments[i]].join(''))
      Logging::Logging.debug(['"', result, '"'].join(''))
      return i, result
    end

    def split_commands(data)
      i, segments = Kawari.parse(data, 0)
      # find multiple commands separated by semicolons
      buf = []
      command = []
      for segment in segments
        if segment == ';'
          if not command.empty?
            buf << command
            command = []
          end
        else
          command << segment
        end
      end
      if not command.empty?
        buf << command
      end
      # strip white space before and after each command
      for command in buf
        if Kawari.is_space(command[0])
          command.delete_at(0)
        end
        if Kawari.is_space(command[-1])
          command.delete_at(-1)
        end
      end
      return buf
    end

    def parse_argument(segments)
      buf = [[]]
      for segment in segments
        if Kawari.is_space(segment)
          buf << []
        else
          buf[-1] << segment
        end
      end
      return buf
    end

    def exec_new_if(argv)
      if argv.length == 3
        return exec_if(argv[1], argv[2], nil)
      elsif argv.length == 4
        return exec_if(argv[1], argv[2], argv[3])
      else
        raise RuntimeError.new('syntax error')
      end
    end

    def exec_old_if(if_block, then_block, else_block)
      # convert [...] into $([...])
      if if_block and if_block.start_with?('[') and if_block.end_with?(']')
        if_block = ['$(', if_block, ')'].join('')
      end
      # parse arguments
      i, if_block = Kawari.parse(if_block, 0)
      i, then_block = Kawari.parse(then_block, 0)
      if else_block
        i, else_block = Kawari.parse(else_block, 0)
      end
      result = exec_if(if_block, then_block, else_block)
      if else_block
        Logging::Logging.debug(
          '>>> $(if ' + if_block.join('') + ')$(then ' + then_block.join('') + ')$(else ' + else_block.join('') + ')$(endif)')
      else
        Logging::Logging.debug(
          '>>> $(if ' + if_block.join('') + ')$(then ' + then_block.join('') + ')$(endif)')
      end
      Logging::Logging.debug(['"', result, '"'].join(''))
      return result
    end

    def exec_if(if_block, then_block, else_block)
      if not ['', '0', 'false', 'False'].include?(expand(if_block))
        return expand(then_block)
      elsif else_block
        return expand(else_block)
      end
      return ''
    end

    def exec_foreach(argv)
      if argv.length != 4
        raise RuntimeError.new('syntax error')
      end
      temp = expand(argv[1])
      name = expand(argv[2])
      buf = []
      for dic in @rdictlist
        if dic.include?(name)
          for segments in dic[name]
            set(temp, expand(segments))
            buf << expand(argv[3])
          end
        end
      end
      clear(temp)
      return buf.join('')
    end

    def exec_loop(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      begin
        n = Integer(expand(argv[1]))
      rescue # except ValueError:
        raise RuntimeError.new('invalid argument')
      end
      buf = []
      for _ in 0..n-1
        buf << expand(argv[2])
      end
      return buf.join('')
    end

    def exec_while(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      buf = []
      while not ['', '0', 'false', 'False'].include?(expand(argv[1]))
        buf << expand(argv[2])
      end
      return buf.join('')
    end

    def exec_until(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      buf = []
      while ['', '0', 'false', 'False'].include?(expand(argv[1]))
        buf << expand(argv[2])
      end
      return buf.join('')
    end

    def exec_set(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      set(expand(argv[1]), expand(argv[2]))
      return ''
    end

    def exec_adddict(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      push(expand(argv[1]), expand(argv[2]))
      return ''
    end

    def exec_array(argv) # XXX experimental
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      name = expand(argv[1])
      n = atoi(expand(argv[2]))
      for d in @rdictlist
        c = d.include?(name) ? d[name] : []
        if n < c.length
          return c[n].map {|s| expand(s) }.join('')
        end
        n -= c.length
      end
      raise RuntimeError.new('invalid argument')
    end

    def exec_clear(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      clear(expand(argv[1]))
      return ''
    end

    def exec_enumerate(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      name = expand(argv[1])
      return enumerate(name).map {|s| expand(s) }.join(' ')
    end

    def enumerate(name)
      buf = []
      for dic in @rdictlist
        if dic.include?(name)
          for segments in dic[name]
            buf << segments
          end
        end
      end
      return buf
    end

    def exec_size(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      name = expand(argv[1])
      n = 0
      for d in @rdictlist
        c = d.include?(name) ? d[name] : []
        n += c.length
      end
      return n.to_s
    end

    def exec_get(argv) # XXX experimental
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      name = expand(argv[1])
      n = atoi(expand(argv[2]))
      for d in @rdictlist
        c = d.include?(name) ? d[name] : []
        if n < c.length
          return c[n].join('')
        end
        n -= c.length
      end
      raise RuntimeError.new('invalid argument')
    end

    def exec_unshift(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      unshift(expand(argv[1]), expand(argv[2]))
      return ''
    end

    def exec_shift(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      return shift(expand(argv[1]))
    end

    def exec_push(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      push(expand(argv[1]), expand(argv[2]))
      return ''
    end

    def exec_pop(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      return pop(expand(argv[1]))
    end

    def exec_pirocall(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      selection = select_simple_phrase(expand(argv[1]))
      if selection == nil
        return ''
      end
      return selection[0]
    end

    def exec_split(argv)
      if argv.length != 4
        raise RuntimeError.new('syntax error')
      end
      name = expand(argv[1])
      word_list = expand(argv[2]).split(expand(argv[3]), 0)
      n = 0
      for word in word_list
        n += 1
        entry = name.to_s + '.' + n.to_s
        set(entry, word)
      end
      set([name, '.size'].join(''), n.to_s)
      return ''
    end

    def get_dict_path(path)
      path = Home.get_normalized_path(path)
      if not path
        raise RuntimeError.new('invalid argument')
      end
      if path.start_with?('/')
        return path
      end
      return File.join(@prefix, path)
    end

    def exec_load(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      path = get_dict_path(expand(argv[1]))
      begin
        rdict, kdict = Kawari.create_dict(Kawari.read_dict(path))
      rescue #except IOError:
        raise RuntimeError.new('cannot read file')
      end
      if @pathlist.include?(path)
        i = @pathlist.index(path)
        @rdictlist[i].update(rdict)
        @kdictlist[i].update(kdict)
      else
        @pathlist.insert(0, path)
        @rdictlist.insert(0, rdict)
        @kdictlist.insert(0, kdict)
      end
      return ''
    end

    def exec_save(argv, crypt=false)
      if argv.length < 2
        raise RuntimeError.new('syntax error')
      end
      path = get_dict_path(expand(argv[1]))
      begin
        open(path, 'wb') do |f|
          f.write("#\r\n# Kawari save file\r\n#\r\n")
          for i in 2..argv.length-1
            name = expand(argv[i])
            if name.strip.empty?
              next
            end
            buf = []
            for segments in enumerate(name)
              buf << segments.join('')
            end
            line = [name, ' : ', buf.join(' , ')].join('').encode($charset, :invalid => :replace, :undef => :replace)
            name = name.encode($charset, :invalid => :replace, :undef => :replace)
            if crypt
              line = Kawari.encrypt(line)
            end
            f.write(['# Entry ',
                     name, "\r\n",
                     line, "\r\n"].join(''))
          end
        end
      rescue #except IOError:
        raise RuntimeError.new('cannot write file')
      end
      return ''
    end

    def exec_savecrypt(argv)
      return exec_save(argv, true)
    end

    def exec_textload(argv)
      if argv.length != 3
        raise RuntimeError.new('syntax error')
      end
      path = get_dict_path(expand(argv[1]))
      begin
        open(path, :encoding => $charset) do |f|
          linelist = f.readlines()
        end
      rescue #except IOError:
        raise RuntimeError.new('cannot read file')
      end
      name = expand(argv[2])
      n = 0
      for line in linelist
        n += 1
        entry = name.to_s + '.' + n.to_s
        if line.end_with?("\r\n")
          line = line[0..-3]
        elsif line.end_with?("\r") or line.end_with?("\n")
          line = line[0..-2]
        end
        if line.empty?
          clear(entry)
        else
          set(entry, line)
        end
      end
      set([name, '.size'].join(''), n.to_s)
      return ''
    end

    def exec_escape(argv)
      data = argv[1..-1].map {|s| expand(s) }.join(' ')
      data = data.gsub('\\', '\\\\')
      data = data.gsub('%', '\%')
      return data
    end

    def exec_echo(argv)
      return argv[1..-1].map {|s| expand(s) }.join(' ')
    end

    def exec_tolower(argv)
      return exec_echo(argv).downcase
    end

    def exec_toupper(argv)
      return exec_echo(argv).upcase
    end

    def exec_eval(argv)
      return parse_all(exec_echo(argv))
    end

    def exec_entry(argv)
      if argv.length == 2
        return get(expand(argv[1]))
      elsif argv.length == 3
        result = get(expand(argv[1]))
        if result
          return result
        else
          return expand(argv[2])
        end
      else
        raise RuntimeError.new('syntax error')
      end
    end

    def exec_null(argv)
      if argv.length != 1
        raise RuntimeError.new('syntax error')
      end
      return ''
    end

    def exec_chr(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      num = atoi(expand(argv[1]))
      if num < 256
        return num.chr
      end
      return [((num >> 8) & 0xff).chr, (num & 0xff).chr].join('')
    end

    def exec_choice(argv)
      if argv.length == 1
        return ''
      end
      i = rand(1..argv.length-1)        
      return expand(argv[i])
    end

    def exec_rand(argv)
      if argv.length != 2
        raise RuntimeError.new('syntax error')
      end
      bound = atoi(expand(argv[1]))
      if bound == 0
        return 0.to_s
      elsif bound > 0
        return rand(0..bound-1).to_s
      else
        return rand(bound + 1..-1).to_s
      end
    end

    def exec_date(argv)
      if argv.length == 1
        format_ = '%y/%m/%d %H:%M:%S'
      else
        format_ = argv[1..-1].map {|s| expand(s) }.join(' ')
      end
      buf = []
      i = 0
      j = format_.length
      now = Time.now
      while i < j
        if format_[i] == '%'
          i += 1
          if i < j
            c = format_[i]
            i += 1
          else
            break
          end
          if ['y', 'Y'].include?(c) # year (4 columns)
            buf << sprintf("%04d", now.year)
          elsif c == 'm' # month (01 - 12)
            buf << sprintf("%02d", now.month)
          elsif c == 'n' # month (1 - 12)
            buf << now.month.to_s
          elsif c == 'd' # day (01 - 31)
            buf << sprintf("%02d", now.day)
          elsif c == 'e' # day (1 - 31)
            buf << now.day.to_s
          elsif c == 'H' # hour (00 - 23)
            buf << sprintf("%02d", now.hour)
          elsif c == 'k' # hour (0 - 23)
            buf << now.hour.to_s
          elsif c == 'M' # minute (00 - 59)
            buf << sprintf("%02d", now.min)
          elsif c == 'N' # minute (0 - 59)
            buf << now.min.to_s
          elsif c == 'S' # second (00 - 59)
            buf << sprintf("%02d", now.sec)
          elsif c == 'r' # second (0 - 59)
            buf << now.sec.to_s
          elsif c == 'w' # weekday (0 = Sunday)
            buf << now.wday.to_s
          elsif c == 'j' # Julian day (001 - 366)
            buf << sprintf("%03d", now.yday)
          elsif c == 'J' # Julian day (1 - 366)
            buf << now.yday.to_s
          elsif c == '%'
            buf << '%'
          else
            buf << '%'
            i -= 1
          end
        else
          buf << format_[i]
          i += 1
        end
      end
      return buf.join('')
    end

    def exec_inc(argv)
      _inc = lambda {|value, step, bound| 
        value += step
        if bound != nil and value > bound
          return bound
        end
        return value
      }
      apply_counter_op(_inc, argv)
      return ''
    end

    def exec_dec(argv)
      _dec = lambda {|value, step, bound| 
        value -= step
        if bound != nil and value < bound
          return bound
        end
        return value
      }
      apply_counter_op(_dec, argv)
      return ''
    end

    def apply_counter_op(func, argv)
      if argv.length < 2 or argv.length > 4
        raise RuntimeError.new('syntax error')
      end
      name = expand(argv[1])
      value = atoi(get(name))
      if argv.length >= 3
        step = atoi(expand(argv[2]))
      else
        step = 1
      end
      if argv.length == 4
        bound = atoi(expand(argv[3]))
      else
        bound = nil
      end
      set(name, func.call(value, step, bound).to_s)
    end

    def exec_test(argv)
      if argv[0] == 'test' and argv.length == 4 or \
        argv[0] == '[' and argv.length == 5 and expand(argv[4]) == ']'
        op1 = expand(argv[1])
        op  = expand(argv[2])
        op2 = expand(argv[3])
      else
        raise RuntimeError.new('syntax error')
      end
      if ['=', '=='].include?(op)
        result = (op1 == op2).to_s
      elsif op == '!='
        result = (op1 != op2).to_s
      elsif op == '<='
        result = (op1 <= op2).to_s
      elsif op == '>='
        result = (op1 >= op2).to_s
      elsif op == '<'
        result = (op1 < op2).to_s
      elsif op == '>'
        result = (op1 > op2).to_s
      elsif op == '-eq'
        result = (atoi(op1) == atoi(op2)).to_s
      elsif op == '-ne'
        result = (atoi(op1) != atoi(op2)).to_s
      elsif op == '-le'
        result = (atoi(op1) <= atoi(op2)).to_s
      elsif op == '-ge'
        result = (atoi(op1) >= atoi(op2)).to_s
      elsif op == '-lt'
        result = (atoi(op1) < atoi(op2)).to_s
      elsif op == '-gt'
        result = (atoi(op1) > atoi(op2)).to_s
      else
        raise RuntimeError.new('unknown operator')
      end
      return result
    end

    def exec_expr(argv)
      tree = @expr_parser.parse(
        argv[1..-1].map {|e| e.join('') }.join(' '))
      if tree == nil
        raise RuntimeError.new('syntax error')
      end
      begin
        value = interp_expr(tree)
      rescue #except ExprError:
        raise RuntimeError.new('runtime error')
      end
      return value
    end

    def interp_expr(tree)
      if tree[0] == ExprParser::OR_EXPR
        for subtree in tree[1..-1]
          value = interp_expr(subtree)
          if value and not ['', '0', 'false', 'False'].include?(value)
            break
          end
        end
        return value
      elsif tree[0] == ExprParser::AND_EXPR
        buf = []
        for subtree in tree[1..-1]
          value = interp_expr(subtree)
          if not value or ['', '0', 'false', 'False'].include?(value)
            return '0'
          end
          buf << value
        end
        return buf[0]
      elsif tree[0] == ExprParser::CMP_EXPR
        op1 = interp_expr(tree[1])
        op2 = interp_expr(tree[3])
        if is_number(op1) and is_number(op2)
          op1 = Integer(op1)
          op2 = Integer(op2)
        end
        if ['=', '=='].include?(tree[2])
          return (op1 == op2).to_s
        elsif tree[2] == '!='
          return (op1 != op2).to_s
        elsif tree[2] == '<='
          return (op1 <= op2).to_s
        elsif tree[2] == '>='
          return (op1 >= op2).to_s
        elsif tree[2] == '<'
          return (op1 < op2).to_s
        elsif tree[2] == '>'
          return (op1 > op2).to_s
        else
          raise RuntimeError.new('unknown operator')
        end
      elsif tree[0] == ExprParser::ADD_EXPR
        for i in 1.step(tree.length-1, 2)
          tree[i] = interp_expr(tree[i])
          if not is_number(tree[i])
            raise ExprError
          end
        end
        value = Integer(tree[1])
        for i in 2.step(tree.length-1, 2)
          if tree[i] == '+'
            value += Integer(tree[i + 1])
          elsif tree[i] == '-'
            value -= Integer(tree[i + 1])
          end
        end
        return value.to_s
      elsif tree[0] == ExprParser::MUL_EXPR
        for i in 1.step(tree.length-1, 2)
          tree[i] = interp_expr(tree[i])
          if not is_number(tree[i])
            raise ExprError
          end
        end
        value = Integer(tree[1])
        for i in 2.step(tree.length-1, 2)
          if tree[i] == '*'
            value *= Integer(tree[i + 1])
          elsif tree[i] == '/'
            begin
              value /= Integer(tree[i + 1])
              value = value.to_i
            rescue # except ZeroDivisionError:
              raise ExprError
            end
          elsif tree[i] == '%'
            begin
              value = value % Integer(tree[i + 1])
            rescue # except ZeroDivisionError:
              raise ExprError
            end
          end
        end
        return value.to_s
      elsif tree[0] == ExprParser::STR_EXPR
        if tree[1] == 'length'
          length = get_characters(interp_expr(tree[2])).length
          return length.to_s
        elsif tree[1] == 'index'
          s = get_characters(interp_expr(tree[2]))
          c = get_characters(interp_expr(tree[3]))
          break_flag = false
          for pos in 0..s.length-1
            if c.include?(s[pos])
              break_flag = true
              break
            end
          end
          if not break_flag
            pos = 0
          end
          return pos.to_s
        elsif tree[1] == 'match'
          begin
            match = Regexp.new(interp_expr(tree[3])).match(interp_expr(tree[2]))
          rescue #except re.error:
            match = nil
          end
          if match
            length = match.end(0) - match.begin(0)
          else
            length = 0
          end
          return length.to_s
        elsif tree[1] == 'find'
          s = interp_expr(tree[3])
          pos = nterp_expr(tree[2]).index(s)
          if not pos or pos < 0
            return ''
          end
          return s
        elsif tree[1] == 'findpos'
          s = interp_expr(tree[3])
          pos = interp_expr(tree[2]).find(s);
          if not pos or pos < 0
            return ''
          end
          return (pos + 1).to_s
        elsif tree[1] == 'substr'
          s = interp_expr(tree[2])
          p = interp_expr(tree[3])
          n = interp_expr(tree[4])
          if is_number(p) and is_number(n)
            p = Integer(p) - 1
            n = p + Integer(n)
            if 0 <= p and p <= n
              characters = get_characters(s)
              return characters[p..n-1].join('')
            end
          end
          return ''
        end
      elsif tree[0] == ExprParser::LITERAL
        return expand(tree[1..-1])
      end
    end

    def get_characters(s)
      buf = []
      i = 0
      j = s.length
      while i < j
        buf << s[i]
        i += 1
      end
      return buf
    end
  end

  ###   EXPR PARSER   ###

  class ExprError < StandardError # ValueError
    #pass
  end

  
  class ExprParser
    attr_accessor :kawari

    def initialize
      #pass
      @kawari = nil
    end

    def show_progress(func, buf)
      if buf == nil
        Logging::Logging.debug(func.to_s + '() -> syntax error')
      else
        Logging::Logging.debug(func.to_s + '() -> ' + buf.to_s)
      end
    end

    Re_token = Regexp.new('^([():|&*/%+-]|[<>]=?|[!=]?=|match|index|findpos|find|substr|length|quote|(\\s+))')

    def tokenize(data)
      buf = []
      i = 0
      j = data.length
      while i < j
        match = Re_token.match(data[i..-1])
        if match
          buf << match[0]
          i += match.end(0)
        else
          i, segments = Kawari.parse(data, i, Re_token)
          buf.concat(segments)
        end
      end
      return buf
    end

    def parse(data)
      @tokens = tokenize(data)
      begin
        return get_expr()
      rescue #except ExprError:
        return nil # syntax error
      end
    end

    # internal
    def done
      return @tokens.empty?
    end

    def pop
      begin
        return @tokens.shift
      rescue #except IndexError:
        raise ExprError
      end
    end

    def look_ahead(index=0)
      begin
        return @tokens[index]
      rescue #except IndexError:
        raise ExprError
      end
    end

    def match(s)
      if pop() != s
        raise ExprError
      end
    end

    def match_space
      if not Kawari.is_space(pop())
        raise ExprError
      end
    end

    def check(s, index=0)
      return (look_ahead(index) == s)
    end

    def check_space(index=0)
      return Kawari.is_space(look_ahead(index))
    end

    # tree node types
    OR_EXPR  = 1
    AND_EXPR = 2
    CMP_EXPR = 3
    ADD_EXPR = 4
    MUL_EXPR = 5
    STR_EXPR = 6
    LITERAL  = 7

    def get_expr
      buf = get_or_expr()
      if not done()
        raise ExprError
      end
      show_progress('get_expr', buf)
      return buf
    end

    def get_or_expr
      buf = [OR_EXPR]
      while true
        buf << get_and_expr()
        if not done() and \
          check_space() and check('|', 1)
          pop() # space
          pop() # operator
          match_space()
        else
          break
        end
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_or_expr', buf)
      return buf
    end

    def get_and_expr
      buf = [AND_EXPR]
      while true
        buf << get_cmp_expr()
        if not done() and \
          check_space() and check('&', 1)
          pop() # space
          pop() # operator
          match_space()
        else
          break
        end
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_and_expr', buf)
      return buf
    end

    def get_cmp_expr
      buf = [CMP_EXPR]
      buf << get_add_expr()
      if not done() and \
        check_space() and \
        ['<=', '>=', '<', '>', '=', '==', '!='].include?(look_ahead(1))
        pop() # space
        buf << pop() # operator
        match_space()
        buf << get_add_expr()
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_cmp_expr', buf)
      return buf
    end

    def get_add_expr
      buf = [ADD_EXPR]
      while true
        buf << get_mul_expr()
        if not done() and \
          check_space() and ['+', '-'].include?(look_ahead(1))
          pop() # space
          buf << pop() # operator
          match_space()
        else
          break
        end
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_add_expr', buf)
      return buf
    end

    def get_mul_expr
      buf = [MUL_EXPR]
      while true
        buf << get_mat_expr()
        if not done() and \
          check_space() and ['*', '/', '%'].include?(look_ahead(1))
          pop() # space
          buf << pop() # operator
          match_space()
        else
          break
        end
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_mul_expr', buf)
      return buf
    end

    def get_mat_expr
      buf = [STR_EXPR]
      buf << get_str_expr()
      if not done() and \
        check_space() and check(':', 1)
        buf.insert(1, 'match')
        pop() # space
        pop() # ':'
        match_space()
        buf << get_str_expr()
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_mat_expr', buf)
      return buf
    end

    def get_str_expr
      argc = 0
      if check('length')
        argc = 1
      elsif ['match', 'index', 'find', 'findpos'].include?(look_ahead())
        argc = 2
      elsif check('substr')
        argc = 3
      end
      if argc > 0
        buf = [STR_EXPR, pop()] # fuction
        for _ in 0..argc-1
          match_space()
          buf << get_str_expr()
        end
      elsif check('quote')
        buf = [LITERAL]
        pop()
        match_space()
        if Re_token.match(look_ahead())
          buf << pop()
        else
          buf.concat(get_str_seq())
        end
      else
        buf = get_sub_expr()
      end
      show_progress('get_str_expr', buf)
      return buf
    end

    def get_sub_expr
      if check('(')
        pop()
        if check_space()
          pop()
        end
        buf = get_or_expr()
        if check_space()
          pop()
        end
        #begin specification bug work-around (3/3)
        @tokens[0] = @kawari.parse_all(@tokens[0])
        #end
        match(')')
      else
        buf = [LITERAL]
        buf.concat(get_str_seq())
      end
      show_progress('get_sub_expr', buf)
      return buf
    end

    def get_str_seq
      buf = []
      while not done() and \
           not Re_token.match(look_ahead())
        buf << pop()
      end
      if buf.empty?
        raise ExprError
      end
      return buf
    end
  end

# <<< EXPR SYNTAX >>>
# expr     := or-expr
# or-expr  := and-expr (sp or-op sp and-expr)*
# or-op    := '|'
# and-expr := cmp-expr (sp and-op sp cmp-expr)*
# and-op   := '&'
# cmp-expr := add-expr (sp cmp-op sp add-expr)?
# cmp-op   := <= | >= | < | > | == | = | !=
# add-expr := mul-expr (sp add-op sp mul-expr)*
# add-op   := '+' | '-'
# mul-expr := mat-expr (sp mul-op sp mat-expr)*
# mul-op   := '*' | '/' | '%'
# mat-expr := str-expr (sp ':' sp str-expr)?
# str-expr := 'quote' sp (OPERATOR | str-seq) |
#             'match' sp str-expr sp str-expr |
#             'index' sp str-expr sp str-expr |
#             'find' sp str-expr sp str-expr |
#             'findpos' sp str-expr sp str-expr |
#             'substr' sp str-expr sp str-expr sp str-expr |
#             'length' sp str-expr |
#             sub-expr
# sub-expr := '(' sp? or-expr sp? ')' | str-seq
# sp       := SPACE+ (white space)
# str-seq  := STRING+ (literal, "...", ${...}, and/or $(...))


  ###   API   ###

  DICT_FILE, INI_FILE = Array(0..1)

  def self.list_dict(kawari_dir, saori_ini={})
    return Kawari.scan_ini(kawari_dir, 'kawari.ini', saori_ini)
  end

  def self.scan_ini(kawari_dir, filename, saori_ini)
    buf = []
    ini_path = File.join(kawari_dir, filename)
    begin
      line_list = Kawari.read_dict(ini_path)
    rescue #except IOError:
      line_list = []
    end
    read_as_dict = false
    for entry, value, position in line_list
      if entry == 'dict'
        filename = Home.get_normalized_path(value)
        path = File.join(kawari_dir, filename)
        begin
          open(path, 'rb') do |f|
            f.read(64)
          end
        rescue #except IOError as e:
          ##errno, message = e.args
          Logging::Logging.debug('kawari.rb: read error: ' + path.to_s)
          next
        end
        buf << [DICT_FILE, path]
      elsif entry == 'include'
        filename = Home.get_normalized_path(value)
        buf.concat(Kawari.scan_ini(kawari_dir, filename, saori_ini))
      elsif entry == 'set'
        read_as_dict = true
      elsif ['randomseed', 'debug', 'security', 'set'].include?(entry)
        #pass
      elsif entry == 'saori'
        saori_list = value.split(',', 0)
        path = saori_list[0].strip()
        alias_ = saori_list[1].strip()
        if saori_list.length == 3
          option = saori_list[2].strip()
        else
          option = 'loadoncall'
        end
        saori_ini[alias_] = [path, option]
      else
        Logging::Logging.debug('kawari.rb: unknown entry: ' + entry.to_s)
      end
    end
    if read_as_dict
      buf << [INI_FILE, ini_path]
    end
    return buf
  end

  def self.read_ini(path)
    buf = []
    begin
      line_list = Kawari.read_dict(path)
    rescue #except IOError:
      line_list = []
    end
    for entry, value, position in line_list
      if entry == 'set'
        begin
          entry, value = value.split(nil, 2)
        rescue #except ValueError:
          next
        end
        buf << [entry.strip(), value.strip(), position]
      end
    end
    return buf
  end


  class Shiori < Kawari7

    def initialize(dll_name)
      @dll_name = dll_name
      @saori_list = {}
      @saori_ini = {}

      @kis_commands = {
        # flow controls
        'if' =>          'exec_new_if',
        'foreach' =>     'exec_foreach',
        'loop' =>        'exec_loop',
        'while' =>       'exec_while',
        'until' =>       'exec_until',
        # dictionary operators
        'adddict' =>     'exec_adddict',
        'array' =>       'exec_array',
        'clear' =>       'exec_clear',
        'enumerate' =>   'exec_enumerate',
        'set' =>         'exec_set',
        'load' =>        'exec_load',
        'save' =>        'exec_save',
        'savecrypt' =>   'exec_savecrypt',
        'textload' =>    'exec_textload',
        'size' =>        'exec_size',
        'get' =>         'exec_get',
        # list operators
        'unshift' =>     'exec_unshift',
        'shift' =>       'exec_shift',
        'push' =>        'exec_push',
        'pop' =>         'exec_pop',
        # counter operators
        'inc' =>         'exec_inc',
        'dec' =>         'exec_dec',
        # expression evaluators
        'expr' =>        'exec_expr',
        'test' =>        'exec_test',
        '[' =>           'exec_test',
        'entry' =>       'exec_entry',
        'eval' =>        'exec_eval',
        # utility functions
        'NULL' =>        'exec_null',
        '?' =>           'exec_choice',
        'date' =>        'exec_date',
        'rand' =>        'exec_rand',
        'echo' =>        'exec_echo',
        'escape' =>      'exec_escape',
        'tolower' =>     'exec_tolower',
        'toupper' =>     'exec_toupper',
        'pirocall' =>    'exec_pirocall',
        'split' =>       'exec_split',
        'urllist' =>     nil,
        'chr' =>         'exec_chr',
        'help' =>        nil,
        'ver' =>         nil,
        'searchghost' => nil,
        'saoriregist' => nil,
        'saorierase' =>  nil,
        'callsaori' =>   nil,
        'callsaorix' =>  nil,
      }

      @kis_commands['saoriregist'] = 'exec_saoriregist'
      @kis_commands['saorierase'] = 'exec_saorierase'
      @kis_commands['callsaori'] = 'exec_callsaori'
      @kis_commands['callsaorix'] = 'exec_callsaorix'
    end

    def use_saori(saori)
      @saori = saori
    end

    def load(dir: nil)
      @kawari_dir = dir
      pathlist = [nil]
      rdictlist = [{}]
      kdictlist = [{}]
      @saori_ini = {}
      for file_type, path in Kawari.list_dict(@kawari_dir, @saori_ini)
        pathlist << path
        if file_type == INI_FILE
          rdict, kdict = Kawari.create_dict(Kawari.read_ini(path))
        elsif Kawari.is_local_script(path)
          rdict, kdict = Kawari.read_local_script(path)
        else
          rdict, kdict = Kawari.create_dict(Kawari.read_dict(path))
        end
        rdictlist << rdict
        kdictlist << kdict
      end
      kawari_init(@kawari_dir, pathlist, rdictlist, kdictlist)
      for value in @saori_ini.values()
        if value[1] == 'preload'
          head, tail = File.split(value[0].gsub('\\', '/'))
          saori_load(value[0], File.join(@kawari_dir, head))
        end
      end
      return 1
    end

    def unload
      finalize
      for name in @saori_list.keys()
        @saori_list[name].unload()
        @saori_list.delete(name)
      end
      $charset = 'CP932' # reset
    end

    def find(dir, dll_name)
      result = 0
      if not Kawari.list_dict(dir).empty?
        result = 200
      end
      $charset = 'CP932' # reset
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: KAWARI compatible module for ninix\n" \
        "        Copyright (C) 2001, 2002 by Tamito KAJIYAMA\n" \
        "        Copyright (C) 2002, 2003 by MATSUMURA Namihiko\n" \
        "        Copyright (C) 2002-2015 by Shyouzou Sugitani\n" \
        "        Copyright (C) 2003 by Shun-ichi TAHARA")
    end

    def request(req_string)
      header = req_string.force_encoding($charset).encode("UTF-8", :invalid => :replace, :undef => :replace).split(/\r?\n/, 0)
      req_header = {}
      if not header.empty?
        line = header.shift
        line = line.strip()
        req_list = line.split(nil, -1)
        if req_list.length >= 2
          command = req_list[0].strip()
          protocol = req_list[1].strip()
        end
        for line in header
          line = line.strip()
          if line.empty?
            next
          end
          if not line.include?(':')
            next
          end
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          begin
            value = Integer(value)
          rescue
            value = value.to_s
          end
          req_header[key] = value
        end
      end
      result = ''
      to = nil
      if req_header.include?('ID')
        if req_header['ID'] == 'dms'
          result = getdms()
        elsif req_header['ID'] == 'OnAITalk'
          result = getaistringrandom()
        elsif ['\\ms', '\\mz', '\\ml', '\\mc', '\\mh', \
               '\\mt', '\\me', '\\mp'].include?(req_header['ID'])
          result = getword(req_header['ID'][1..-1])
        elsif req_header['ID'] == '\\m?'
          result = getword('m')
        elsif req_header['ID'] == 'otherghostname'
          otherghost = []
          for n in 0..127
            key = ['Reference', n.to_s].join('')
            if req_header.include?(key)
              otherghost << req_header[key]
            end
          end
          result = otherghostname(otherghost)
        elsif req_header['ID'] == 'OnTeach'
          if req_header.include?('Reference0')
            teach(req_header['Reference0'])
          end
        else
          result = getstring(req_header['ID'])
          if not result or result.empty?
            ref = []
            for n in 0..7
              key = ['Reference', n.to_s].join('')
              if req_header.include?(key)
                ref << req_header[key]
              else
                ref << nil
              end
            end
            ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7 = ref
            result = get_event_response(
              req_header['ID'], ref0, ref1, ref2, ref3, ref4,
              ref5, ref6, ref7)
          end
        end
        if result == nil
          result = ''
        end
        to = communicate_to()
      end
      result = "SHIORI/3.0 200 OK\r\n" \
               "Sender: Kawari\r\n" \
               "Charset: " + $charset.to_s + "\r\n" \
               "Value: " + result.to_s + "\r\n"
      if to != nil
        result = [result, "Reference0: " + to.to_s + "\r\n"].join('')
      end
      result = [result, "\r\n"].join('')
      return result.encode($charset)
    end

    def exec_saoriregist(kawari, argv)
      filename = expand(argv[1])
      alias_ = expand(argv[2])
      if argv.length == 4
        option = expand(argv[3])
      else
        option = 'loadoncall'
      end
      @saori_ini[alias_] = [filename, option]
      if @saori_ini[alias_][1] == 'preload'
        head, tail = File.split(
                @saori_ini[alias_][0].gsub('\\', '/'))
        saori_load(@saori_ini[alias_][0],
                   File.join(@kawari_dir, head))
      end
      return ''
    end

    def exec_saorierase(kawari, argv)
      alias_ = expand(argv[1])
      if @saori_ini.include?(alias_)
        saori_unload(@saori_ini[alias_][0])
      end
      return ''
    end

    def exec_callsaori(kawari, argv)
      alias_ = expand(argv[1])
      if not @saori_ini.include?(alias_)
        return ''
      end
      if not @saori_list.include?(@saori_ini[alias_][0])
        if @saori_ini[alias_][1] == 'preload'
          return ''
        else
          head, tail = File.split(
                  @saori_ini[alias_][0].gsub('\\', '/'))
          saori_load(@saori_ini[alias_][0],
                     File.join(@kawari_dir, head))
        end
      end
      saori_statuscode = ''
      saori_header = []
      saori_value = {}
      saori_protocol = ''
      req = "EXECUTE SAORI/1.0\r\n" \
            "Sender: KAWARI\r\n" \
            "SecurityLevel: local\r\n" \
            "Charset: " + $charset.to_s + "\r\n"
      for i in 2..argv.length-1
        req = [req,
               "Argument" + (i - 2).to_s + ": " + expand(argv[i]).to_s + "\r\n"].join('')
      end
      req = [req, "\r\n"].join('')
      response = saori_request(@saori_ini[alias_][0],
                               req.encode($charset, :invalid => :replace, :undef => :replace))
      header = response.splitlines()
      if not header.empty?
        line = header.shift
        line = line.strip()
        if line.include?(' ')
          saori_protocol, saori_statuscode = line.split(' ', 2)
          saori_protocol.strip!
          saori_statuscode.strip!
        end
        for line in header
          line = line.strip()
          if line.empty?
            next
          end
          if not line.include?(':')
            next
          end
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          if not key.empty?
            saori_header << key
            saori_value[key] = value
          end
        end
      end
      if saori_value.include?('Result')
        result = saori_value['Result']
      else
        result =  ''
      end
      if @saori_ini[alias_][1] == 'noresident'
        saori_unload(@saori_ini[alias_][0])
      end
      return result
    end

    def exec_callsaorix(kawari, argv)
      alias_ = expand(argv[1])
      entry = expand(argv[2])
      if not @saori_ini.include?(alias_)
        return ''
      end
      if not @saori_list.include?(@saori_ini[alias_][0])
        if @saori_ini[alias_][1] == 'preload'
          return ''
        else
          head, tail = File.split(
                  @saori_ini[alias_][0].gsub('\\', '/'))
          saori_load(@saori_ini[alias_][0],
                     File.join(@kawari_dir, head))
        end
      end
      saori_statuscode = ''
      saori_header = []
      saori_value = {}
      saori_protocol = ''
      req = "EXECUTE SAORI/1.0\r\n" \
            "Sender: KAWARI\r\n" \
            "SecurityLevel: local\r\n"
      for i in 3..argv.length-1
        req = [req,
               "Argument" + (i -3).to_s + ": " + expand(argv[i]) + "\r\n"].join('')
      end
      req = [req, "\r\n"].join('')
      response = saori_request(@saori_ini[alias_][0],
                               req.encode($charset, :invalid => :replace, :undef => :replace))
      header = response.splitlines()
      if not header.empty?
        line = header.shift
        line = line.strip()
        if line.include?(' ')
          saori_protocol, saori_statuscode = line.split(' ', 2)
          saori_protocol.strip!
          saori_statuscode.strip1
        end
        for line in header
          line = line.strip()
          if line.empty?
            next
          end
          if not line.include?(':')
            next
          end
          key, value = line.split(':', 2)
          key.strip!
          value.strip!
          if not key.empty?
            saori_header << key
            saori_value[key] = value
          end
        end
      end
      result = {}
      for key, value in saori_value.items()
        if key.start_with?('Value')
          result[key] = value
        end
      end
      for key, value in result.items()
        set([entry, '.', key].join(''), value)
      end
      if @saori_ini[alias_][1] == 'noresident'
        saori_unload(@saori_ini[alias_][0])
      end
      return result.length
    end

    def saori_load(saori, path)
      result = 0
      if @saori_list.keys().include?(saori)
        result = @saori_list[saori].load(:dir => path)
      else
        module_ = @saori.request(saori)
        if module_
          @saori_list[saori] = module_
          result = @saori_list[saori].load(:dir => path)
        end
      end
      return result
    end

    def saori_unload(saori)
      result = 0
      if @saori_list.keys().include?(saori)
        result = @saori_list[saori].unload()
      end
      return result
    end

    def saori_request(saori, req)
      result = 'SAORI/1.0 500 Internal Server Error'
      if @saori_list.include?(saori)
        result = @saori_list[saori].request(req)
      end
      return result
    end
  end

  def self.is_local_script(path)
    line = ''
    open(path, 'rb') do |f|
      line = f.readline()
    end
    return line.start_with?('[SAKURA]')
  end
end
