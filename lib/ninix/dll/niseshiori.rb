# -*- coding: utf-8 -*-
#
#  niseshiori.rb - a "偽栞" compatible Shiori module for ninix
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

require_relative "../logging"


module Niseshiori

  REVISION = '$Revision: 1.28 $' ## FIXME

  # tree node types
  ADD_EXPR     = 1
  MUL_EXPR     = 2
  UNARY_EXPR   = 3
  PRIMARY_EXPR = 4

  def self.list_dict(top_dir)
    buf = []
    begin
      filelist = []
      Dir.foreach(top_dir, :encoding => 'UTF-8') do |file|
        if file == '..' or file == '.'
          next
        end
        filelist << file
      end
    rescue #except OSError:
      filelist = []
    end
    re_dict_filename = Regexp.new('^ai.*\.(dtx|txt)$')
    for filename in filelist
      if re_dict_filename.match(filename)
        buf << File.join(top_dir, filename)
      end
    end
    return buf
  end


  class NiseShiori

    def initialize
      @dict = {}
      @type_chains = {}
      @word_chains = {}
      @keywords = {}
      @responses = {}
      @greetings = {}
      @events = {}
      @resources = {}
      @variables = {}
      @dbpath = nil
      @expr_parser = ExprParser.new()
      @username = ''
      @ai_talk_interval = 180
      @ai_talk_count = 0
      @surf0 = 0
      @surf1 = 10
      @event = nil
      @reference = nil
      @jump_entry = nil
      @motion_area = nil
      @motion_count = 0
      @mikire = 0
      @kasanari = 0
      @otherghost = []
      @to = ''
      @sender = ''
    end

    def load(top_dir)
      # read dictionaries
      dictlist = Niseshiori.list_dict(top_dir)
      if dictlist.empty?
        return 1
      end
      for path in dictlist
        read_dict(path)
      end
      # read variables
      @dbpath = File.join(top_dir, 'niseshiori.db')
      load_database(@dbpath)
      return 0
    end

    def load_database(path)
      begin
        open(path, encoding='utf-8') do |f|
          dic = {}
          for line in f
            if line.start_with?('# ns_st: ')
              begin
                @ai_talk_interval = Integer(line[9..-1])
              rescue #except ValueError:
                #pass
              end
              next
            elsif line.start_with?('# ns_tn: ')
              @username = line[9..-1].strip()
              next
            end
            begin
              name, value = line.split('=', 2)
              name.strip!
              value.strip!
            rescue #except ValueError:
              Logging::Logging.error(
                'niseshiori.py: malformed database (ignored)')
              return
            end
            dic[name] = value
          end
        end
      rescue #except IOError:
        return
      end
      @variables = dic
    end

    def save_database
      if @dbpath == nil
        return
      end
      begin
        open(@dbpath, 'w') do |f|
          f.write('# ns_st: ' + @ai_talk_interval.to_i.to_s + "\n")
          f.write('# ns_tn: ' + @username.to_s + "\n")
          for name in @variableskeys
            value = @variables[name]
            if not name.start_with?('_')
              f.write(name.to_s + '=' + value.to_s + "\n")
            end
          end
        end
      rescue #except IOError:
        Logging::Logging.error('niseshiori.py: cannot write database (ignored)')
        return
      end
    end

    def finalize
      #pass
    end

    Re_type = Regexp.new('^\\\(m[szlchtep?]|[dk])')
    Re_user = Regexp.new('^\\\u[a-z]')
    Re_category = Regexp.new('^\\\(m[szlchtep]|[dk])?\[([^\]]+)\]')

    def read_dict(path)
      # read dict file and decrypt if necessary
      buf = []
      open(path, 'rb') do |f|
        basename = File.basename(path, ".*")
        ext = File.extname(path)
        ext = ext.downcase
        if ext == '.dtx'
          buf = decrypt(f.read())
        else
          buf = f.readlines()
        end
      end
      # omit empty lines and comments and merge continuous lines
      definitions = []
      decode = lambda {|line| line.force_encoding('CP932').encode('UTF-8', :invalid => :replace, :undef => :replace) }
      in_comment = false
      i, j = 0, buf.length
      while i < j
        line = buf[i].strip()
        i += 1
        if line.empty?
          next
        elsif i == 1 and line.start_with?('#Charset:')
          charset = line[9..-1].force_encoding('ascii').strip()
          if ['UTF-8', 'EUC-JP', 'EUC-KR'].include?(charset) # XXX
            decode = lambda {|line| line.force_encoding(charset).encode('UTF-8', :invalid => :replace, :undef => :replace) }
          end
          next
        elsif line.start_with?('/*')
          in_comment = true
          next
        elsif line.start_with?('*/')
          in_comment = false
          next
        elsif in_comment or line.start_with?('#') or line.start_with?('//')
          next
        end
        lines = [line]
        while i < j and buf[i] and \
             (buf[i].start_with?(' ') or buf[i].start_with?("\t"))
          lines << buf[i].strip()
          i += 1
        end
        definitions << lines.join('')
      end
      # parse each line
      for line in definitions
        line = decode.call(line)
        # special case: words in a category
        match = Re_category.match(line)
        if match
          line = line[match.end(0)..-1].strip()
          if line.empty? or not line.start_with?(',')
            syntax_error(path, line)
            next
          end
          words = split(line).map {|s| s.strip if not s.strip.empty? }
          words.delete(nil)
          cattype = match.to_a[1]
          catlist = match.to_a[2..-1]
          for cat in catlist.map {|s| s.strip }
            if cattype == nil
              keylist = [[nil, cat]]
            else
              keylist = [[nil, cat], [cattype, cat]]
            end
            for key in keylist
              value = @dict.include?(key) ? @dict[key] : []
              value.concat(words)
              @dict[key] = value
            end
          end
          if cattype != nil
            key = ['\\', cattype].join('')
            value = @dict.include?(key) ? @dict[key] : []
            value.concat(words)
            @dict[key] = value
          end
          next
        end
        # other cases
        begin
          command, argv = split(line, 1)
          command.strip!
          argv.strip!
        rescue #except ValueError:
          syntax_error(path, line)
          next
        end
        if command == '\ch'
          argv = split(argv).map {|s| s.strip }
          if argv.length == 5
            t1, w1, t2, w2, c = argv
          elsif argv.length == 4
            t1, w1, t2, w2 = argv
            c = nil
          elsif argv.length == 3
            t1, w1, c = argv
            t2 = w2 = nil
          else
            syntax_error(path, line)
            next
          end
          if not Re_type.match(t1) and not Re_user.match(t1)
            syntax_error(path, line)
            next
          end
          if c != nil
            ch_list = @type_chains.include?(t1) ? @type_chains[t1] : []
            ch_list << [c, w1]
            @type_chains[t1] = ch_list
          end
          if t2 == nil
            next
          end
          if not Re_type.match(t2) and not Re_user.match(t2)
            syntax_error(path, line)
            next
          end
          if c != nil
            ch_list = @type_chains.include?(t2) ? @type_chains[t2] : []
            ch_list << [c, w2]
            @type_chains[t2] = ch_list
          end
          m1 = ['%', t1[1..-1]].join('')
          m2 = ['%', t2[1..-1]].join('')
          key = [m1, w1]
          dic = @word_chains.include?(key) ? @word_chains[key] : {}
          ch_list = dic.include?(m2) ? dic[m2] : []
          if not ch_list.include?([c, w2])
            ch_list << [c, w2]
            dic[m2] = ch_list
            @word_chains[key] = dic
          end
          key = [m2, w2]
          dic = @word_chains.include?(key) ? @word_chains[key] : {}
          ch_list = dic.include?(m1) ? dic[m1] : []
          if not ch_list.include?([c, w1])
            ch_list << [c, w1]
            dic[m1] = ch_list
            @word_chains[key] = dic
          end
          ch_list = @dict.include?(t1) ? @dict[t1] : []
          if not ch_list.include?(w1)
            ch_list << w1
            @dict[t1] = ch_list
          end
          ch_list = @dict.include?(t2) ? @dict[t2] : []
          if not ch_list.include?(w2)
            ch_list << w2
            @dict[t2] = ch_list
          end
        elsif Re_type.match(command) or Re_user.match(command)
          words = split(argv).map {|s| s.strip if not s.strip.empty? }
          words.delete(nil)
          value = @dict.include?(command) ? @dict[command] : []
          value.concat(words)
          @dict[command] = value
        elsif ['\dms', '\e'].include?(command)
          value = @dict.include?(command) ? @dict[command] : []
          value << argv
          @dict[command] = value
        elsif command == '\ft'
          argv = split(argv, 2).map {|s| s.strip }
          if argv.length != 3
            syntax_error(path, line)
            next
          end
          w, t, s = argv
          if not Re_type.match(t)
            syntax_error(path, line)
            next
          end
          @keywords[[w, t]] = s
        elsif command == '\re'
          argv = split(argv, 1).map {|s| s.strip }
          if argv.length == 2
            cond = parse_condition(argv[0])
            re_list = @responses.include?(cond) ? @responses[cond] : []
            re_list << argv[1]
            @responses[cond] = re_list
          end
        elsif command == '\hl'
          argv = split(argv, 1).map {|s| s.strip }
          if argv.length == 2
            hl_list = @greetings.include?(argv[0]) ? @greetings[argv[0]] : []
            hl_list << argv[1]
            @greetings[argv[0]] = hl_list
          end
        elsif command == '\ev'
          argv = split(argv, 1).map {|s| s.strip }
          if argv.length == 2
            cond = parse_condition(argv[0])
            ev_list = @events.include?(cond) ? @events[cond] : []
            ev_list << argv[1]
            @events[cond] = ev_list
          end
        elsif command == '\id'
          argv = split(argv, 1).map {|s| s.strip }
          if argv.length == 2
            if ['sakura.recommendsites',
                'kero.recommendsites',
                'sakura.portalsites'].include?(argv[0])
              id_list = @resources.include?(argv[0]) ? @resources[argv[0]] : ''
              if not id_list.empty?
                id_list = [id_list, "\2"].join('')
              end
              id_list = [id_list, argv[1].gsub(' ', "\1")].join('')
              @resources[argv[0]] = id_list
            else
              @resources[argv[0]] = argv[1]
            end
          end
        elsif command == '\tc'
          #pass
        else
          syntax_error(path, line)
        end
      end
    end

    def split(line, maxcount=nil)
      buf = []
      count = 0
      end_ = pos = 0
      while maxcount == nil or count < maxcount
        pos = line.index(',', pos)
        if not pos or pos < 0
          break
        elsif pos > 0 and line[pos - 1] == '\\'
          pos += 1
        else
          if pos != 0
            buf << line[end_..pos-1]
            count += 1
          end
        end
        end_ = pos = pos + 1
      end
      buf << line[end_..-1]
      return buf.map {|s| s.gsub('\\,', ',') }
    end

    def syntax_error(path, line)
      Logging::Logging.debug(
        'niseshiori.py: syntax error in ' + File.basename(path, ".*"))
      Logging::Logging.debug(line)
    end

    Re_comp_op = Regexp.new('<[>=]?|>=?|=')
    COND_COMPARISON = 1
    COND_STRING     = 2

    def parse_condition(condition)
      buf = []
      for expr in condition.split('&', -1).map {|s| s.strip }
        match = Re_comp_op.match(expr)
        if match
          buf << [COND_COMPARISON, [
                    expr[0..match.begin(0)-1].strip(),
                    match.to_s,
                    expr[match.end(0)..-1].strip()]]
        else
          buf << [COND_STRING, expr]
        end
      end
      return buf
    end

    def decrypt(data)
      buf = []
      a = 0x61
      i = 0
      j = data.length
      line = []
      while i < j
        if data[i].ord == 64 # == '@'[0]
          i += 1
          buf << line.join('')
          line = []
          next
        end
        y = data[i].ord
        i += 1
        x = data[i].ord
        i += 1
        x -= a
        a += 9
        y -= a
        a += 2
        if a > 0xdd
          a = 0x61
        end
        line << ((x & 0x03) | ((y & 0x03) << 2) | \
                 ((y & 0x0c) << 2) | ((x & 0x0c) << 4)).chr
      end
      return buf
    end

    def getaistringrandom
      result = get_event_response('OnNSRandomTalk')
      if not result or result.empty?
        result = get('\e')
      end
      return result
    end

    def get_event_response(event,
                           ref0=nil, ref1=nil, ref2=nil, ref3=nil,
                           ref4=nil, ref5=nil, ref6=nil, ref7=nil)
      ref = [ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7]
      if ['OnSecondChange', 'OnMinuteChange'].include?(event)
        if ref[1] == 1
          @mikire += 1
          script = get_event_response('OnNSMikireHappen')
          if script != nil
            return script
          end
        elsif @mikire > 0
          @mikire = 0
          return get_event_response('OnNSMikireSolve')
        end
        if ref[2] == 1
          @kasanari += 1
          script = get_event_response('OnNSKasanariHappen')
          if script != nil
            return script
          end
        elsif @kasanari > 0
          @kasanari = 0
          return get_event_response('OnNSKasanariHappen')
        end
        if event == 'OnSecondChange' and @ai_talk_interval > 0
          @ai_talk_count += 1
          if @ai_talk_count == @ai_talk_interval
            @ai_talk_count = 0
            if not @otherghost.empty? and \
              (0..10).to_a.sample == 0
              target = []
              for name, s0, s1 in @otherghost
                if @greetings.include?(name)
                  target << name
                end
              end
              if not target.empty?
                @to = target.sample
              end
              if not @to.empty?
                @current_time = Time.now
                s = @greetings[@to].sample
                if not s.empty?
                  s = replace_meta(s)
                  while true
                    match = Re_ns_tag.match(s)
                    if not match
                      break
                    end
                    value = eval_ns_tag(match.to_s)
                    s = [s[0..match.begin(0)-1],
                         value.to_s,
                         s[match.end(0)..-1]].join('')
                  end
                end
                return s
              end
            end
            return getaistringrandom()
          end
        end
        return nil
      elsif event == 'OnMouseMove'
        if @motion_area != [ref[3], ref[4]]
          @motion_area = [ref[3], ref[4]]
          @motion_count = 0
        else
          @motion_count += 5 # sensitivity
        end
      elsif event == 'OnSurfaceChange'
        @surf0 = ref[0]
        @surf1 = ref[1]
      elsif event == 'OnUserInput' and ref[0] == 'ninix.niseshiori.username'
        @username = ref[1]
        save_database()
        return '\e'
      elsif event == 'OnCommunicate'
        @event = ''
        @reference = [ref[1]]
        if ref[0] == 'user'
          @sender = 'User'
        else
          @sender = ref[0]
        end
        candidate = []
        for cond in @responses
          if eval_condition(cond)
            candidate << cond
          end
        end
        script = nil
        @to = ref[0]
        if not candidate.empty?
          cond = candidate.sample
          script = @responses[cond].sample
        end
        if (not script or script.empty?) and @responses.include?('nohit')
          script = @responses['nohit'].sample
        end
        if not script or script.empty?
          @to = ''
        else
          script = replace_meta(script)
          while 1
            match = Re_ns_tag.match(script)
            if not match
              break
            end
            value = eval_ns_tag(match.to_s)
            script = [script[0..match.begin(0)-1],
                      value.to_s,
                      script[match.end(0)..-1]].join('')
          end
        end
        @sender = ''
        return script
      end
      key = 'action'
      @dict[key] = []
      @event = event
      @reference = ref
      @current_time = Time.now
      for condition in @events.keys
        actions = @events[condition]
        if eval_condition(condition)
          @dict[key].concat(actions)
        end
      end
      script = get(key, default=nil)
      if script != nil
        @ai_talk_count = 0
      end
      @event = nil
      @reference = nil
      if script != nil
        script = script
      end
      return script
    end

    def otherghostname(ghost_list)
      @otherghost = []
      for ghost in ghost_list
        name, s0, s1 = ghost.split(1.chr, 3)
        @otherghost << [name, s0, s1]
      end
      return ''
    end

    def communicate_to
      to = @to
      @to = ''
      return to
    end

    def eval_condition(condition)
      for cond_type, expr in condition
        if not eval_conditional_expression(cond_type, expr)
          return false
        end
      end
      return true
    end

    def eval_conditional_expression(cond_type, expr)
      if cond_type == COND_COMPARISON
        value1 = expand_meta(expr[0])
        value2 = expr[2]
        begin
          op1 = Integer(value1)
          op2 = Integer(value2)
        rescue #except ValueError:
          op1 = value1.to_s
          op2 = value2.to_s
        end
        if expr[1] == '>='
          return op1 >= op2
        elsif expr[1] == '<='
          return op1 <= op2
        elsif expr[1] == '>'
          return op1 > op2
        elsif expr[1] == '<'
          return op1 < op2
        elsif expr[1] == '='
          return op1 == op2
        elsif expr[1] == '<>'
          return op1 != op2
        end
      elsif cond_type == COND_STRING
        if @event.include?(expr)
          return true
        end
        for ref in @reference
          if ref != nil and ref.to_s.include?(expr)
            return true
          end
        end
        return false
      else
        return false
      end
    end

    Re_ns_tag = Regexp.new('\\\(ns_(st(\[[0-9]+\])?|cr|hl|rf\[[^\]]+\]|ce|tc\[[^\]]+\]|tn(\[[^\]]+\])?|jp\[[^\]]+\]|rt)|set\[[^\]]+\])')

    def get(key, default='')
      @current_time = Time.now
      s = expand(key, '', default)
      if s and not s.empty?
        while true
          match = Re_ns_tag.match(s)
          if not match
            break
          end
          value = eval_ns_tag(match.to_s)
          s = [s[0..match.begin(0)-1], value.to_s, s[match.end(0)..-1]].join('')
        end
      end
      return s
    end

    def eval_ns_tag(tag)
      value = ''
      if tag == '\ns_cr'
        @ai_talk_count = 0
      elsif tag == '\ns_ce'
        @to = ''
      elsif tag == '\ns_hl'
        if not @otherghost.empty?
          @to = @otherghost.sample[0]
        elsif tag.start_with?('\ns_st[') and tag.end_with?(']')
          begin
            num = Integer(tag[7..-2])
          rescue #except ValueError:
            @pass
          else
            if num == 0
              @ai_talk_interval = 0
            elsif num == 1
              @ai_talk_interval = 420
            elsif num == 2
              @ai_talk_interval = 180
            elsif num == 3
              @ai_talk_interval = 60
            else
              @ai_talk_interval = min(max(num, 4), 999)
            end
            save_database()
            @ai_talk_count = 0
          end
        elsif tag.start_with?('\ns_jp[') and tag.end_with?(']')
          name = tag[7..-2]
          @jump_entry = name
          value = get_event_response('OnNSJumpEntry')
          if not value or value.empty?
            value = ''
          end
          @jump_entry = nil
        elsif tag.start_with?('\set[') and tag.end_with?(']')
          statement = tag[5..-2]
          if not statement.include?('=')
            Logging::Logging.debug('niseshiori.py: syntax error')
            Logging::Logging.debug(tag)
          else
            name, expr = statement.split('=', 2)
            name.strip!
            expr .strip!
            value = eval_expression(expr)
            if value != nil
              @variables[name] = value
              if not name.start_with?('_')
                save_database()
              end
              Logging::Logging.debug('set ' + name.to_s + ' = "' + value.to_s + '"')
            else
              Logging::Logging.debug('niseshiori.py: syntax error')
              Logging::Logging.debug(tag)
            end
          end
        end
      elsif tag == '\ns_rt'
        value = '\a'
      elsif tag == '\ns_tn'
        value = '\![open,inputbox,ninix.niseshiori.username,-1]'
      elsif tag.start_with?('\ns_tn[') and tag.end_with?(']')
        @username = tag[7..-2]
        save_database()
      end
      return value
    end

    Re_meta = Regexp.new('%((rand([1-9]|\[[0-9]+\])|selfname2?|sakuraname|keroname|username|friendname|year|month|day|hour|minute|second|week|ghostname|sender|ref[0-7]|surf[01]|word|ns_st|get\[[^\]]+\]|jpentry|plathome|platform|move|mikire|kasanari|ver)|(dms|(m[szlchtep?]|[dk])(\[[^\]]*\])?|\[[^\]]*\]|u[a-z])([2-9]?))')

    def replace_meta(s)
      pos = 0
      buf = []
      variables = {}
      variable_chains = []
      while true
        match = Re_meta.match(s, pos)
        if not match
          buf << s[pos..-1]
          break
        end
        if match.begin(0) != 0
          buf << s[pos..match.begin(0)-1]
        end
        meta = match.to_s
        if match[4] != nil # %ms, %dms, %ua, etc.
          if not variables.include?(meta)
            chained_meta = ['%', match[4]].join('')
            break_flag = false
            for chains in variable_chains
              if chains.include?(meta)
                candidates_A, candidates_B = chains[chained_meta]
                if not candidates_A.empty?
                  word = candidates_A.sample
                  candidates_A.delete(word)
                else
                  word = candidates_B.sample
                  candidates_B.delete(word)
                end
                if candidates_A.empty? and candidates_B.empty?
                  chains.delete(chained_meta)
                end
                Logging::Logging.debug('chained: ' + meta.to_s + ' => ' + word.to_s)
                break_flag = true
                break
              end
            end
            if not break_flag
              if match[4] == 'm?'
                word = expand(
                  ['\\',
                   ['ms', 'mz', 'ml',
                    'mc', 'mh', 'mt',
                    'me', 'mp'].sample].join(''), s)
              else
                word = expand(
                  ['\\', match[4]].join(''), s)
              end
            end
            chains = find_chains([chained_meta, word], s)
            prefix = 'chain:'
            for k in chains.keys
              candidates_A, candidates_B = chains[k]
              for w in candidates_A
                Logging::Logging.debug(prefix.to_s + ' ' + k.to_s + ', ' + w.to_s)
                prefix = '      '
              end
              for w in candidates_B
                Logging::Logging.debug(prefix.to_s + ' ' + k.to_s + ', ' + w.to_s)
                prefix = '      '
              end
            end
            variables[meta] = word
            variable_chains << chains
          end
          buf << variables[meta]
        else
          buf << expand_meta(meta).to_s
        end
        pos = match.end(0)
      end
      t = buf.join('')
      return t
    end

    def expand(key, context, default='')
      choices = []
      for keyword, word in (@type_chains.include?(key) ? @type_chains[key] : [])
        if context.include?(keyword)
          Logging::Logging.debug('chain keyword: ' + keyword.to_s)
          choices << word
        end
      end
      if choices.empty?
        match = Re_category.match(key)
        if match
          key = match.to_a[1..2]
        end
        choices = @dict[key]
      end
      if not choices or choices.empty?
        if key.is_a?(Array)
          key = '(' + key[0].to_s + ', ' + key[1..-1].to_s + ')'
        end
        Logging::Logging.debug(key.to_s + ' not found')
        return default
      end
      s = choices.sample
      t = replace_meta(s)
      if key.is_a?(Array)
        if not key[0]
          key = '\\[' + key[1].to_s + ']'
        else
          key = '\\' + key[0].to_s + '[' + key[1].to_s + ']'
        end
      end
      Logging::Logging.debug([key, '=>', s].join(''))
      Logging::Logging.debug([' ' * key.length, '=>', t].join(''))
      return t
    end

    def find_chains(key, context)
      chains = {}
      dic = @word_chains.include?(key) ? @word_chains[key] : {}
      for chained_meta in dic.keys
        candidates_A = []
        candidates_B = []
        for keyword, chained_word in dic[chained_meta]
          if keyword and context.include?(keyword)
            candidates_A << chained_word
          else
            candidates_B << chained_word
          end
        end
        chains[chained_meta] = [candidates_A, candidates_B]
      end
      return chains
    end

    WEEKDAY_NAMES = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']

    def expand_meta(name)
      if ['%selfname', '%selfname2', '%keroname', '%friendname'].include?(name)
        result = name
      elsif name == '%sakuraname'
        result = '%selfname'
      elsif name == '%username'
        result = @username or '%username'
      elsif name.start_with?('%get[') and name.end_with?(']')
        value = @variables.include?(name[5..-2]) ? @variables[name[5..-2]] : '?'
        begin
          result = Integer(value)
        rescue #except ValueError:
          result = value
        end
      elsif name.start_with?('%rand[') and name.end_with?(']')
        n = name[6..-2].to_i
        result = (1..n).to_a.sample
      elsif name.start_with?('%rand') and name.length == 6
        n = name[5].to_i
        result = (10**(n - 1)..10**n - 1).to_a.sample
      elsif name.start_with?('%ref') and name.length == 5 and \
           '01234567'.include?(name[4])
        if @reference == nil
          result = ''
        else
          n = name[4].to_i
          if @reference[n] == nil
            result = ''
          else
            result = @reference[n]
          end
        end
      elsif name == '%jpentry'
        if @jump_entry == nil
          result = ''
        else
          result = @jump_entry
        end
      elsif name == '%year'
        result = @current_time.year.to_s
      elsif name == '%month'
        result = @current_time.month.to_s
      elsif name == '%day'
        result = @current_time.day.to_s
      elsif name == '%hour'
        result = @current_time.hour.to_s
      elsif name == '%minute'
        result = @current_time.min.to_s
      elsif name == '%second'
        result = @current_time.to_s
      elsif name == '%week'
        result = WEEKDAY_NAMES[@current_time.wday]
      elsif name == '%ns_st'
        result = @ai_talk_interval
      elsif name == '%surf0'
        result = @surf0.to_s
      elsif name == '%surf1'
        result = @surf1.to_s
      elsif ['%plathome', '%platform'].include?(name) ## FIXME
        result = 'ninix'
      elsif name == '%move'
        result = @motion_count.to_s
      elsif name == '%mikire'
        result = @mikire.to_s
      elsif name == '%kasanari'
        result = @kasanari.to_s
      elsif name == '%ver' ## FIXME
        if REVISION[1..10] == 'Revision: '
          result = '偽栞 for ninix (rev.' + REVISION[11..-3] + ')'
        else
          result = '偽栞 for ninix'
        end
      elsif name == '%sender'
        if not @sender.empty?
          result = @sender
        else
          result = ''
        end
      elsif name == '%ghost'
        if not @to.empty?
          result = @to
        elsif not @otherghost.empty?
          result = @otherghost.sample[0]
        else
          result = ''
        end
      else
        result = ['\\', name].join('')
      end
      return result
    end

    def eval_expression(expr)
      tree = @expr_parser.parse(expr)
      if tree == nil
        return nil
      else
        return interp_expr(tree)
      end
    end

    def __interp_add_expr(tree)
      value = interp_expr(tree[0])
      1.step(tree.length-1, 2) do |i|
        operand = interp_expr(tree[i + 1])
        begin
          if tree[i] == '+'
            value = Integer(value) + Integer(operand)
          elsif tree[i] == '-'
            value = Integer(value) - Integer(operand)
          end
        rescue #except ValueError:
          value = [value, tree[i], operand].join('')
        end
      end
      return value
    end

    def __interp_mul_expr(tree)
      value = interp_expr(tree[0])
      1.step(tree.length-1, 2) do |i|
        operand = interp_expr(tree[i + 1])
        begin
          if tree[i] == '*'
            value = Integer(value) * Integer(operand)
          elsif tree[i] == '/'
            value = (Integer(value) / Integer(operand)).to_i
          elsif tree[i] == '\\'
            value = Integer(value) % Integer(operand)
          end
        rescue #except (ValueError, ZeroDivisionError):
          value = [value, tree[i], operand].join('')
        end
      end
      return value
    end

    def __interp_unary_expr(tree)
      operand = interp_expr(tree[1])
      begin
        if tree[0] == '+'
          return Integer(operand)
        elsif tree[0] == '-'
          return - Integer(operand)
        end
      rescue #except ValueError:
        return [tree[0], operand].join('')
      end
    end

    def __interp_primary_expr(tree)
      if is_number(tree[0])
        return tree[0].to_i
      elsif tree[0].start_with?('%')
        return expand_meta(tree[0])
      end
      begin
        return @variables[tree[0]]
      rescue #except KeyError:
        return '?'
      end
    end

    __expr = {
        ADD_EXPR => '__interp_add_expr',
        MUL_EXPR => '__interp_mul_expr',
        UNARY_EXPR => '__interp_unary_expr',
        PRIMARY_EXPR => '__interp_primary_expr',
        }

    def interp_expr(tree)
      key = tree[0]
      if @__expr.include?(key)
        return method(@__expr[key]).call(self, tree[1..-1])
      else
        raise RuntimeError('should not reach here')
      end
    end

    def is_number(s)
      return (s and s.chars.map.all? {|c| '0123456789'.include?(c) })
    end
  end


  class ExprError < StandardError # ValueError
    #pass
  end


  class ExprParser

    def initialize
      #pass
    end

    def show_progress(func, buf)
      if buf == nil
        Logging::Logging.debug(func.to_s + '() -> syntax error')
      else
        Logging::Logging.debug(func.to_s + '() -> ' + buf.to_s)
      end
    end

    Re_token_A = Regexp.new('^[()*/\+-]|\d+|\s+')
    Re_token_B = Regexp.new('[()*/\+-]|\d+|\s+')

    def tokenize(data)
      buf = []
      end_ = 0
      while 1
        match = NiseShiori::Re_meta.match(data, end_)
        if match
          buf << match.to_s
          end_ = match.end(0)
          next
        end
        match = Re_token_A.match(data, end_)
        if match
          if not match.to_s.strip().empty?
            buf << match.to_s
          end
          end_ = match.end(0)
          next
        end
        match = Re_token_B.match(data, end_)
        if match
          buf << data[end_..match.begin(0)-1]
          if not match.to_s.strip().empty?
            buf << match.to_s
          end
          end_ = match.end(0)
        else
          if end_ < data.length
            buf << data[end_..-1]
          end
          break
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

    def get_expr
      buf = get_add_expr()
      if not done()
        raise ExprError
      end
      show_progress('get_expr', buf)
      return buf
    end

    def get_add_expr
      buf = [ADD_EXPR]
      while 1
        buf << get_mul_expr()
        if done() or not ['+', '-'].include?(look_ahead())
          break
        end
        buf << pop() # operator
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_add_expr', buf)
      return buf
    end

    def get_mul_expr
      buf = [MUL_EXPR]
      while 1
        buf << get_unary_expr()
        if done() or not ['*', '/', '\\'].include?(look_ahead())
          break
        end
        buf << pop() # operator
      end
      if buf.length == 2
        buf = buf[1]
      end
      show_progress('get_mul_expr', buf)
      return buf
    end

    def get_unary_expr
      if ['+', '-'].include?(look_ahead())
        buf = [UNARY_EXPR, pop(), get_unary_expr()]
      else
        buf = get_primary_expr()
      end
      show_progress('get_unary_expr', buf)
      return buf
    end

    def get_primary_expr
      if look_ahead() == '('
        match('(')
        buf = get_add_expr()
        match(')')
      else
        buf = [PRIMARY_EXPR, pop()]
      end
      show_progress('get_primary_expr', buf)
      return buf
    end
  end

# <<< EXPRESSION SYNTAX >>>
# expr         := add-expr
# add-expr     := mul-expr (add-op mul-expr)*
# add-op       := '+' | '-'
# mul-expr     := unary-expr (mul-op unary-expr)*
# mul-op       := '*' | '/' | '\'
# unary-expr   := unary-op unary-expr | primary-expr
# unary-op     := '+' | '-'
# primary-expr := identifier | constant | '(' add-expr ')'


  class Shiori < NiseShiori

    def initialize(dll_name)
      super()
      @dll_name = dll_name
    end

    def load(dir: nil)
      super(dir)
      return 1
    end

    def unload
      finalize
    end

    def find(top_dir, dll_name)
      result = 0
      if not Niseshiori.list_dict(top_dir).empty?
        result = 100
      end
      return result
    end

    def show_description
      Logging::Logging.info(
        "Shiori: NiseShiori compatible module for ninix\n" \
        "        Copyright (C) 2001, 2002 by Tamito KAJIYAMA\n" \
        "        Copyright (C) 2002, 2003 by MATSUMURA Namihiko\n" \
        "        Copyright (C) 2002-2015 by Shyouzou Sugitani\n" \
        "        Copyright (C) 2003 by Shun-ichi TAHARA")
    end

    def request(req_string)
      header = req_string.split(/\r?\n/, 0)
      req_header = {}
      line = header.shift
      if not line.empty?
        line = line.strip()
        req_list = line.split(nil, -1)
        if req_list.length >= 2
          command = req_list[0].strip()
          protocol = req_list[1].strip()
        end
        for line in header
          line = line.encode('utf-8', :invalid => :replace, :undef => :replace).strip()
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
            #pass
          end
          req_header[key] = value
        end
      end
      result = ''
      to = nil
      if req_header.include?('ID')
        if req_header['ID'] == 'dms'
          result = get('\dms')
        elsif req_header['ID'] == 'OnAITalk'
          result = getaistringrandom()
        elsif ['\\ms', '\\mz', '\\ml', '\\mc', '\\mh',
               '\\mt', '\\me', '\\mp'].include?(req_header['ID'])
          result = get(req_header['ID'])
        elsif req_header['ID'] == '\\m?'
          result = get(['\\ms', '\\mz', '\\ml',
                             '\\mc', '\\mh', '\\mt',
                             '\\me', '\\mp'].sample)
        elsif req_header['ID'] == 'otherghostname'
          otherghost = []
          for n in 0..127
            if req_header.include?(['Reference', n.to_s].join(''))
              otherghost << 
                req_header[['Reference', n.to_s].join('')]
            end
          end
          result = otherghostname(otherghost)
        elsif req_header['ID'] == 'OnTeach'
          if req_header.include?('Reference0')
            #teach(req_header['Reference0'])
            #pass ## FIXME
          end
        else
          result = @resources[req_header['ID']]
          if result == nil
            ref = []
            for n in 0..7
              if req_header.include?(['Reference', n.to_s].join(''))
                ref << 
                  req_header[['Reference', n.to_s].join('')]
              else
                ref << nil
              end
            end
            ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7 = ref
            result = get_event_response(
              req_header['ID'],
              ref0, ref1, ref2, ref3, ref4, ref5, ref6, ref7)
          end
        end
        if result == nil
          result = ''
        end
        to = communicate_to()
      end
      result = ["SHIORI/3.0 200 OK\r\n",
                "Sender: Niseshiori\r\n",
                "Charset: UTF-8\r\n",
                "Value: ",
                result,
                "\r\n"].join("")
      if to != nil
        result = [result,
                  "Reference0: ",
                  to,
                  "\r\n"].join("")
      end
      result = [result, "\r\n"].join("")
      return result.encode('utf-8', :invalid => :replace, :undef => :replace)
    end
  end
end
