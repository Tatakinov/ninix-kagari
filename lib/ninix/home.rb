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

require_relative "config"
require_relative "alias"
require_relative "dll"
require_relative "logging"


module Home

  def self.get_ninix_home()
    File.join(File.expand_path('~'), '.ninix')
  end

  def self.get_archive_dir()
    File.join(get_ninix_home, 'archive')
  end

  def self.get_pango_fontrc()
    File.join(get_ninix_home, 'pango_fontrc')
  end

  def self.get_preferences()
    File.join(get_ninix_home, 'preferences')
  end

  def self.get_normalized_path(path)
    path = path.gsub("\\", '/')
    path = path.downcase if File.absolute_path(path) != path
    #FIXME: expand_path is NOT equivalent for os.path.normpath
    #return os.path.normpath(os.fsencode(path))
    return path
  end

  def self.load_config()
    return nil unless File.exists?(get_ninix_home())
    ghosts = search_ghosts
    balloons = search_balloons
    nekoninni = search_nekoninni
    katochan = search_katochan
    kinoko = search_kinoko
    return ghosts, balloons, nekoninni, katochan, kinoko
  end

  def self.get_shiori()
    table = {}
    shiori_lib = DLL::Library.new('shiori', :saori_lib => nil)
    path = DLL.get_path
    Dir.foreach(path, :encoding => 'UTF-8') do |filename|
      next if filename == '..' or filename == '.'
      if File.readable_real?(File.join(path, filename))
        name = nil
        basename = File.basename(filename, ".*")
        ext = File.extname(filename)
        ext = ext.downcase
        name = basename if ['.rb'].include?(ext)
        unless name.nil? or table.include?(name)
          shiori = shiori_lib.request(['', name])
          table[name] = shiori unless shiori.nil?
        end
      end
    end
    return table
  end

  def self.search_ghosts(target: nil, check_shiori: true)
    home_dir = get_ninix_home()
    ghosts = {}
    unless target.nil?
      dirlist = []
      dirlist += target
    else
      begin
        dirlist = []
        Dir.foreach(File.join(home_dir, 'ghost'), :encoding => 'UTF-8') do |file|
          next if file == '..' or file == '.'
          dirlist << file
        end
      rescue SystemCallError
        dirlist = []
      end
    end
    shiori_table = get_shiori()
    for subdir in dirlist
      prefix = File.join(home_dir, 'ghost', subdir)
      ghost_dir = File.join(prefix, 'ghost', 'master')
      desc = read_descript_txt(ghost_dir)
      desc = NConfig.null_config() if desc.nil?
      shiori_dll = desc.get('shiori')
      # find a pseudo AI, shells, and a built-in balloon
      candidate = {
        'name' => '',
        'score' => 0
      }
      # SHIORI compatible modules
      for name, shiori in shiori_table.each_entry
        score = shiori.find(ghost_dir, shiori_dll).to_i
        if score > candidate['score']
          candidate['name'] = name
          candidate['score'] = score
        end
      end
      shell_name, surface_set = find_surface_set(prefix)
      next if check_shiori and candidate['score'].zero?
      shiori_name = candidate['name']
      if desc.get('name') == 'default'
        pos = 0
      else
        pos = ghosts.length
      end
      use_makoto = find_makoto_dll(ghost_dir)
      ## FIXME: check surface_set
      ghosts[subdir] = [desc, ghost_dir, use_makoto,
                        surface_set, prefix,
                        shiori_dll, shiori_name]
    end
    return ghosts
  end

  def self.search_balloons(target: nil)
    home_dir = get_ninix_home()
    balloons = {}
    balloon_dir = File.join(home_dir, 'balloon')
    unless target.nil?
      dirlist = []
      dirlist += target
    else
      begin
        dirlist = []
        Dir.foreach(balloon_dir, :encoding => 'UTF-8') do |file|
          next if file == '..' or file == '.'
          dirlist << file
        end
      rescue SystemCallError
        dirlist = []
      end
    end
    for subdir in dirlist
      path = File.join(balloon_dir, subdir)
      next unless File.directory?(path)
      desc = read_descript_txt(path) # REQUIRED
      next if desc.nil?
      balloon_info = read_balloon_info(path) # REQUIRED
      next if balloon_info.empty?
      if balloon_info.include?('balloon_dir') # XXX
        Logging::Logging.warninig('Oops: balloon id confliction')
        next
      else
        balloon_info['balloon_dir'] = [subdir, NConfig.null_config()]
      end
      balloons[subdir] = [desc, balloon_info]
    end
    return balloons
  end

  def self.search_nekoninni()
    home_dir = get_ninix_home()
    buf = []
    skin_dir = File.join(home_dir, 'nekodorif/skin')
    begin
      dirlist = []
      Dir.foreach(skin_dir, :encoding => 'UTF-8') do |file|
        next if file == '..' or file == '.'
        dirlist << file
      end
    rescue SystemCallError
      dirlist = []
    end
    for subdir in dirlist
      nekoninni = read_profile_txt(File.join(skin_dir, subdir))
      next if nekoninni.nil?
      buf << nekoninni
    end
    return buf
  end

  def self.search_katochan()
    home_dir = get_ninix_home()
    buf = []
    katochan_dir = File.join(home_dir, 'nekodorif/katochan')
    begin
      dirlist = []
      Dir.foreach(katochan_dir, :encoding => 'UTF-8') do |file|
        next if file == '..' or file == '.'
        dirlist << file
      end
    rescue SystemCallError
      dirlist = []
    end
    for subdir in dirlist
      katochan = read_katochan_txt(File.join(katochan_dir, subdir))
      next if katochan.nil?
      buf << katochan
    end
    return buf
  end

  def self.search_kinoko()
    home_dir = get_ninix_home()
    buf = []
    kinoko_dir = File.join(home_dir, 'kinoko')
    begin
      dirlist = []
      Dir.foreach(kinoko_dir, :encoding => 'UTF-8') do |file|
        next if file == '..' or file == '.'
        dirlist << file
      end
    rescue SystemCallError
      dirlist = []
    end
    for subdir in dirlist
      kinoko = read_kinoko_ini(File.join(kinoko_dir, subdir))
      next if kinoko.nil?
      buf << kinoko
    end
    return buf
  end

  def self.read_kinoko_ini(top_dir)
    path = File.join(top_dir, 'kinoko.ini')
    kinoko = {}
    kinoko['base'] = 'surface0.png'
    kinoko['animation'] = nil
    kinoko['category'] = nil
    kinoko['title'] = nil
    kinoko['ghost'] = nil
    kinoko['dir'] = top_dir
    kinoko['offsetx'] = 0
    kinoko['offsety'] = 0
    kinoko['ontop'] = 0
    kinoko['baseposition'] = 0
    kinoko['baseadjust'] = 0
    kinoko['extractpath'] = nil
    kinoko['nayuki'] = nil
    if File.readable_real?(path)
      f = open(path, 'rb:CP932')
      line = f.readline()
      return nil if line.strip.empty? or line.strip() != '[KINOKO]'
      lineno = 0
      error = nil
      for line in f
        lineno += 1
        if line.end_with?("\x00") # XXX
          line = line[0, line.length - 2]
        end
        next if line.strip.empty?
        line = line.encode('UTF-8', :invalid => :replace, :undef => :replace)
        unless line.include?('=')
          error = 'line ' + lineno.to_s + ': syntax error'
          break
        end
        x = line.split('=', 2)
        name = x[0].strip()
        value = x[1].strip()
        if ['title', 'ghost', 'category'].include?(name)
          kinoko[name] = value
        elsif ['offsetx', 'offsety'].include?(name)
          kinoko[name] = value.to_i
        elsif ['base', 'animation', 'extractpath'].include?(name)
          kinoko[name] = value
        elsif ['ontop', 'baseposition', 'baseadjust'].include?(name)
          kinoko[name] = value.to_i
        end
        unless error.nil?
          Logging::Logging.error('Error: ' + error + "\n" + path +' (skipped)')
          return nil
        end
      end
    end
    unless kinoko['title'].empty?
      return kinoko
    else
      return nil
    end
  end

  def self.read_profile_txt(top_dir)
    path = File.join(top_dir, 'profile.txt')
    name = nil
    if File.readable_real?(path)
      f = open(path, 'rb:CP932')
      line = f.readline()
      unless line.nil?
        name = line.strip.encode("UTF-8", :invalid => :replace, :undef => :replace)
      end
    end
    unless name.empty?
      return [name, top_dir]
    else
      return nil
    end
  end

  def self.read_katochan_txt(top_dir)
    path = File.join(top_dir, 'katochan.txt')
    katochan = {}
    katochan['dir'] = top_dir
    if File.readable_real?(path)
      f = open(path, 'rb:CP932')
      name = nil
      lineno = 0
      error = nil
      for line in f
        lineno += 1
        next if line.strip.empty?
        if line.start_with?('#')
          name = line[1, line.length - 1].strip()
          next
        elsif name.empty?
          error = 'line ' + lineno.to_s + ': syntax error'
          break
        else
          value = line.strip.encode("UTF-8", :invalid => :replace, :undef => :replace)
          if ['name', 'category'].include?(name)
            katochan[name] = value
          end
          if name.start_with?('before.script') or \
            name.start_with?('hit.script') or \
            name.start_with?('after.script') or \
            name.start_with?('end.script') or \
            name.start_with?('dodge.script')
            ## FIXME: should be array
            katochan[name] = value
          elsif ['before.fall.speed',
                 'before.slide.magnitude',
                 'before.slide.sinwave.degspeed',
                 'before.appear.ofset.x',
                 'before.appear.ofset.y',
                 'hit.waittime', 'hit.ofset.x', 'hit.ofset.y',
                 'after.fall.speed', 'after.slide.magnitude',
                 'after.slide.sinwave.degspeed'].include?(name)
            katochan[name] = value.to_i
          elsif ['target',
                 'before.fall.type', 'before.slide.type',
                 'before.wave', 'before.wave.loop',
                 'before.appear.direction',
                 'hit.wave', 'hit.wave.loop',
                 'after.fall.type', 'after.slide.type',
                 'after.wave', 'after.wave.loop',
                 'end.wave', 'end.wave.loop',
                 'end.leave.direction',
                 'dodge.wave', 'dodge.wave.loop'].include?(name)
            katochan[name] = value
          else
            name = nil
          end
        end
      end
      unless error.nil?
        Logging::Logging.error('Error: ' + error + "\n" + path + ' (skipped)')
        return nil
      end
    end
    unless katochan['name'].empty?
      return katochan
    else
      return nil
    end
  end

  def self.read_descript_txt(top_dir)
    path = File.join(top_dir, 'descript.txt')
    if File.readable_real?(path)
      return NConfig.create_from_file(path)
    end
    return nil
  end

  def self.read_install_txt(top_dir)
    path = File.join(top_dir, 'install.txt')
    if File.readable_real?(path)
      return NConfig.create_from_file(path)
    end
    return nil
  end

  def self.read_alias_txt(top_dir)
    path = File.join(top_dir, 'alias.txt')
    if File.readable_real?(path)
      return Alias.create_from_file(path)
    end
    return nil
  end

  def self.find_makoto_dll(top_dir)
    if File.readable_real?(File.join(top_dir, 'makoto.dll'))
      return true
    else
      return false
    end
  end

  def self.find_surface_set(top_dir)
    desc = read_descript_txt(File.join(top_dir, 'ghost', 'master'))
    default_sakura = desc.get('sakura.seriko.defaultsurface', :default => '0')
    default_kero = desc.get('kero.seriko.defaultsurface', :default => '10')
    unless desc.nil?
      shell_name = desc.get('name')
    else
      shell_name = nil
    end
    if shell_name.nil? or shell_name.empty?
      inst = read_install_txt(top_dir)
      unless inst.nil?
        shell_name = inst.get('name')
      end
    end
    surface_set = {}
    shell_dir = File.join(top_dir, 'shell')
    for name, desc, subdir in find_surface_dir(shell_dir)
      surface_dir = File.join(shell_dir, subdir)
      surface_info, alias_, tooltips, seriko_descript = read_surface_info(surface_dir)
      if not surface_info.nil? and \
        surface_info.include?('surface' + default_sakura.to_s) and \
        surface_info.include?('surface' + default_kero.to_s)
        if alias_.nil?
          alias_ = read_alias_txt(surface_dir)
        end
        surface_set[subdir] = [name, surface_dir, desc, alias_,
                               surface_info, tooltips, seriko_descript]
      end
    end
    return shell_name, surface_set
  end

  def self.find_surface_dir(top_dir)
    buf = []
    path = File.join(top_dir, 'surface.txt')
    if File.exists?(path)
      config = NConfig.create_from_file(path)
      for name, subdir in config.each_entry
        subdir = subdir.downcase
        desc = read_descript_txt(File.join(top_dir, subdir))
        desc = NConfig.null_config() if desc.nil?
        buf << [name, desc, subdir]
      end
    else
      begin
        dirlist = []
        Dir.foreach(top_dir, :encoding => 'UTF-8') do |file|
          next if file == '..' or file == '.'
          dirlist << file
        end
      rescue SystemCallError
        dirlist = []
      end
      for subdir in dirlist
        desc = read_descript_txt(File.join(top_dir, subdir))
        desc = NConfig.null_config() if desc.nil?
        name = desc.get('name', :default => subdir)
        buf << [name, desc, subdir]
      end
    end
    return buf
  end

  def self.read_surface_info(surface_dir)
    re_surface = Regexp.new('\Asurface([0-9]+)\.(png|dgp|ddp)')
    surface = {}
    begin
      filelist = []
      Dir.foreach(surface_dir, :encoding => 'UTF-8') do |file|
        next if file == '..' or file == '.'
        filelist << file
      end
    rescue SystemCallError
      filelist = []
    end
    filename_alias = {}
    path = File.join(surface_dir, 'alias.txt')
    if File.exists?(path)
      dic = Alias.create_from_file(path)
      for basename, alias_ in dic.each_entry
        if basename.start_with?('surface')
          filename_alias[alias_] = basename
        end
      end
    end
    # find png image and associated configuration file
    for filename in filelist
      basename = File.basename(filename, ".*")
      ext = File.extname(filename)
      if filename_alias.include?(basename)
        match = re_surface.match([filename_alias[basename], ext].join(''))
      else
        match = re_surface.match(filename)
      end
      next if match.nil?
      img = File.join(surface_dir, filename)
      next unless File.readable_real?(img)
      key = ['surface', match[1].to_i.to_s].join('')
      txt = File.join(surface_dir, [basename, 's.txt'].join(''))
      if File.readable_real?(txt)
        config = NConfig.create_from_file(txt)
      else
        config = NConfig.null_config()
      end
      txt = File.join(surface_dir, [basename, 'a.txt'].join(''))
      if File.readable_real?(txt)
        config.update(NConfig.create_from_file(txt))
      end
      surface[key] = [img, config]
    end
    # find surfaces.txt
    alias_ = nil
    tooltips = {}
    seriko_descript = {}
    for key, config in read_surfaces_txt(surface_dir)
      if key == '__alias__'
        alias_ = config
      elsif key == '__tooltips__'
        tooltips = config
      elsif key.start_with?('surface')
        if surface.keys.include?(key)
          img, prev_config = surface[key]
          config = prev_config.merge(config)
        else
          img = nil
        end
        surface[key] = [img, config]
      elsif key == 'descript'
        seriko_descript = config
      end
    end
    # find surface elements
    for key in surface.keys
      value = surface[key]
      img, config = value
      for key, method, filename, x, y in list_surface_elements(config)
        filename = filename.downcase
        basename = File.basename(filename, ".*")
        ext = File.extname(filename)
        unless surface.include?(basename)
          surface[basename] = [File.join(surface_dir, filename),
                               NConfig.null_config()]
        end
      end
    end
    return surface, alias_, tooltips, seriko_descript
  end

  def self.read_surfaces_txt(surface_dir)
    re_alias = Regexp.new('\A(sakura|kero|char[0-9]+)\.surface\.alias\z')
    config_list = []
    return config_list unless File.directory?(surface_dir)
    Dir.foreach(surface_dir) do |file|
      next if /^\.+$/ =~ file
      if file.start_with?("surfaces") and file.end_with?(".txt")
        path = File.join(surface_dir, file)
        begin
          f = open(path, 'rb')
          alias_buffer = []
          tooltips = {}
          charset = 'CP932'
          buf = []
          key = nil
          opened = false
          if f.read(3).bytes == [239, 187, 191] # "\xEF\xBB\xBF"
            f.close
            f = File.open(path, 'rb:BOM|UTF-8')
            charset = 'UTF-8'
          else
            f.seek(0) # rewind
          end
          for line in f
            next if line.start_with?('#') or line.start_with?('//')
            if charset == 'CP932'
              # "\x81\x40": full-width space in CP932(Shift_JIS)
              temp = line.gsub(0x81.chr + 0x40.chr, "").strip()
            else
              temp = line.strip()
            end
            next if temp.empty?
            if temp.start_with?('charset')
              begin
                charset = temp.split(',', 2)[1].strip().force_encoding('ascii')
              rescue
                #pass
              end
              next
            end
            if key.nil?
              if temp.end_with?('{')
                key = temp[0, temp.length - 1].force_encoding(charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
                opened = true
              else
                key = temp.force_encoding(charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
              end
            elsif temp == '{'
              opened = true
            elsif temp.end_with?('}')
              if temp[0, temp.length - 2]
                buf << temp[0, temp.length - 2]
              end
              Logging::Logging.error('syntax error: unbalnced "}" in surfaces.txt.') unless opened
              match = re_alias.match(key)
              if not match.nil?
                alias_buffer << key
                alias_buffer << '{'
                for line in buf
                  alias_buffer << line.force_encoding(charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
                end
                alias_buffer << '}'
              elsif key.end_with?('.tooltips')
                begin
                  key = key[0, -10]
                rescue
                  #pass
                end
                value = {}
                for line in buf
                  s = line.split(',', 2)
                  region = s[0].strip().force_encoding(charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
                  text = s[1].strip().force_encoding(charset).encode("UTF-8", :invalid => :replace, :undef => :replace)
                  value[region] = text
                  tooltips[key] = value
                end
              elsif key.start_with?('surface')
                keys = key.split(',', 0)
                include_list = []
                exclude_list = []
                flg_append = false
                for key in keys
                  flg_delete = false
                  next if key.empty?
                  if key.start_with?('surface')
                    unless include_list.empty?
                      for num in (include_list - exclude_list)
                        key = ['surface', num].join('')
                        if flg_append
                          config_list.reverse_each {|x|
                            break x[1].update(NConfig.create_from_buffer(buf, :charset => charset)) if x[0] == key
                          }
                        else
                          config_list << [key, NConfig.create_from_buffer(buf, :charset => charset)]
                        end
                      end
                    end
                    include_list = []
                    exclude_list = []
                    flg_append = false
                  end
                  if key.start_with?('surface.append')
                    flg_append = true
                    key_range = key[14, key.length - 1]
                  elsif key.start_with?('surface')
                    key_range = key[7, key.length - 1]
                  elsif key.start_with?("!")
                    flg_delete = true
                    key_range = key[1, key.length - 1]
                  else
                    key_range = key
                  end
                  s, e = key_range.split("-", 2)
                  e = s if e.nil?
                  begin
                    s = Integer(s)
                    e = Integer(e)
                  rescue
                    next
                  end
                  if flg_delete
                    exclude_list.concat(Range.new(s, e).to_a)
                  else
                    include_list.concat(Range.new(s, e).to_a)
                  end
                end
                unless include_list.empty?
                  for num in (include_list - exclude_list)
                    key = ['surface', num].join('')
                    if flg_append
                      config_list.reverse_each {|x|
                        break x[1].update(NConfig.create_from_buffer(buf, :charset => charset)) if x[0] == key
                      }
                    else
                      config_list << [key, NConfig.create_from_buffer(buf, :charset => charset)]
                    end
                  end
                end
              elsif key == 'descript'
                config_list << [key, NConfig.create_from_buffer(buf, :charset => charset)]
              end
              buf = []
              key = nil
              opened = false
            else
              buf << temp
            end
          end
        rescue SystemCallError
          return config_list
        end
        unless alias_buffer.empty?
          config_list << ['__alias__', Alias.create_from_buffer(alias_buffer)]
        end
        config_list << ['__tooltips__', tooltips]
      end
    end
    return config_list
  end

  def self.list_surface_elements(config)
    buf = []
    for n in 0..255
      key = ['element', n.to_s].join('')
      break unless config.include?(key)
      spec = []
      for value in config[key].split(',', 0)
        spec << value.strip()
      end
      begin
        method, filename, x, y = spec
        x = Integer(x)
        y = Integer(y)
      rescue
        Loggin::Logging.error(
          'invalid element spec for ' + key + ': ' + config[key])
        next
      end
      buf << [key, method, filename, x, y]
    end
    return buf
  end

  def self.read_balloon_info(balloon_dir)
    re_balloon = Regexp.new('\Aballoon([skc][0-9]+)\.(png)')
    re_annex   = Regexp.new('\A(arrow[01]|sstp)\.(png)')
    balloon = {}
    begin
      filelist = []
      Dir.foreach(balloon_dir, :encoding => 'UTF-8') do |file|
        next if file == '..' or file == '.'
        filelist << file
      end
    rescue SystemCallError
      filelist = []
    end
    for filename in filelist
      match = re_balloon.match(filename)
      next if match.nil?
      img = File.join(balloon_dir, filename)
      if match[2] != 'png' and \
        File.readable_real?([img[img.length - 4, img.length - 1], 'png'].join(''))
        next
      end
      next unless File.readable_real?(img)
      key = match[1]
      txt = File.join(balloon_dir, 'balloon' + key.to_s + 's.txt')
      if File.readable_real?(txt)
        config = NConfig.create_from_file(txt)
      else
        config = NConfig.null_config()
      end
      balloon[key] = [img, config]
    end
    for filename in filelist
      match = re_annex.match(filename)
      next if match.nil?
      img = File.join(balloon_dir, filename)
      next unless File.readable_real?(img)
      key = match[1]
      config = NConfig.null_config()
      balloon[key] = [img, config]
    end
    return balloon
  end
end
