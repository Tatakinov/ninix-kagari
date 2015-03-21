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

require "ninix/config"
require "ninix/alias"
require "ninix/dll"


module Home

  PLUGIN_STANDARD = [3.0, 3.1]

  def self.get_ninix_home()
    return File.join(File.expand_path('~'), '.ninix')
  end

  def self.get_archive_dir()
    return File.join(get_ninix_home(), 'archive')
  end

  def self.get_pango_fontrc()
    return File.join(get_ninix_home(), 'pango_fontrc')
  end

  def self.get_preferences()
    return File.join(get_ninix_home(), 'preferences')
  end

  def self.get_normalized_path(path)
    path = path.gsub('\\', '/')
    if File.absolute_path(path) != path
      path = path.downcase
    end
    #FIXME: expand_path is NOT equivalent for os.path.normpath
    #return os.path.normpath(os.fsencode(path))
    return path
  end

  def self.load_config()
    if not File.exists?(get_ninix_home())
      return nil
    end
    ghosts = search_ghosts()
    balloons = search_balloons()
    plugins = search_plugins()
    nekoninni = search_nekoninni()
    katochan = search_katochan()
    kinoko = search_kinoko()
    return ghosts, balloons, plugins, nekoninni, katochan, kinoko
  end

  def self.get_shiori()
    table = {}
    shiori_lib = DLL::Library.new('shiori', saori_lib=nil)
    path = DLL.get_path()
    Dir.foreach(path, :encoding => 'UTF-8') do |filename|
      if filename == '..' or filename == '.'
        next
      end
      if File.readable_real?(File.join(path, filename))
        name = nil
        basename = File.basename(filename, ".*")
        ext = File.extname(filename)
        ext = ext.downcase
        if ['.rb'].include?(ext)
          name = basename
        end
        if !name.empty? and not table.include?(name)
          shiori = shiori_lib.request(['', name])
          if shiori
            table[name] = shiori
          end
        end
      end
    end
    return table
  end

  def self.search_ghosts(target=nil, check_shiori=true)
    home_dir = get_ninix_home()
    ghosts = {}
    if target
      dirlist = []
      dirlist.extend(target)
    else
      begin
        dirlist = []
        Dir.foreach(File.join(home_dir, 'ghost'), :encoding => 'UTF-8') do |file|
          if file == '..' or file == '.'
            next
          end
          dirlist << file
        end
      rescue #except OSError:
        dirlist = []
      end
    end
    shiori_table = get_shiori()
    for subdir in dirlist
      prefix = File.join(home_dir, 'ghost', subdir)
      ghost_dir = File.join(prefix, 'ghost', 'master')
      desc = read_descript_txt(ghost_dir)
      if desc == nil
        desc = NConfig.null_config()
      end
      shiori_dll = desc.get('shiori')
      # find a pseudo AI, shells, and a built-in balloon
      candidate = {
        'name' => '',
        'score' => 0
      }
      # SHIORI compatible modules
      for name, shiori in shiori_table.each_entry
        score = int(shiori.find(ghost_dir, shiori_dll))
        if score > candidate['score']
          candidate['name'] = name
          candidate['score'] = score
        end
      end
      shell_name, surface_set = find_surface_set(prefix)
      if check_shiori and candidate['score'] == 0
        next
      end
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

  def self.search_balloons(target=nil)
    home_dir = get_ninix_home()
    balloons = {}
    balloon_dir = File.join(home_dir, 'balloon')
    if target
      dirlist = []
      dirlist.extend(target)
    else
      begin
        dirlist = []
        Dir.foreach(balloon_dir, :encoding => 'UTF-8') do |file|
          if file == '..' or file == '.'
            next
          end
          dirlist << file
        end
      rescue # except OSError:
        dirlist = []
      end
    end
    for subdir in dirlist
      path = File.join(balloon_dir, subdir)
      if not File.directory?(path)
        next
      end
      desc = read_descript_txt(path) # REQUIRED
      if not desc
        next
      end
      balloon_info = read_balloon_info(path) # REQUIRED
      if balloon_info.empty?
        next
      end
      if balloon_info.include?('balloon_dir') # XXX
        logging.warninig('Oops: balloon id confliction')
        next
      else
        balloon_info['balloon_dir'] = [subdir, NConfig.null_config()]
      end
      balloons[subdir] = [desc, balloon_info]
    end
    return balloons
  end

  def self.search_plugins()
    home_dir = get_ninix_home()
    buf = []
    plugin_dir = File.join(home_dir, 'plugin')
    begin
      dirlist = []
      Dir.foreach(plugin_dir, :encoding => 'UTF-8') do |file|
        if file == '..' or file == '.'
          next
        end
        dirlist << file
      end
    rescue #except OSError:
      dirlist = []
    end
    for subdir in dirlist
      plugin = read_plugin_txt(File.join(plugin_dir, subdir))
      if plugin == nil
        next
      end
      buf << plugin
    end
    return buf
  end

  def self.search_nekoninni()
    home_dir = get_ninix_home()
    buf = []
    skin_dir = File.join(home_dir, 'nekodorif/skin')
    begin
      dirlist = []
      Dir.foreach(skin_dir, :encoding => 'UTF-8') do |file|
        if file == '..' or file == '.'
          next
        end
        dirlist << file
      end
    rescue # except OSError:
      dirlist = []
    end
    for subdir in dirlist
      nekoninni = read_profile_txt(File.join(skin_dir, subdir))
      if nekoninni == nil
        next
      end
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
        if file == '..' or file == '.'
          next
        end
        dirlist << file
      end
    rescue #except OSError:
      dirlist = []
    end
    for subdir in dirlist
      katochan = read_katochan_txt(File.join(katochan_dir, subdir))
      if katochan == nil
        next
      end
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
        if file == '..' or file == '.'
          next
        end
        dirlist << file
      end
    rescue # except OSError:
        dirlist = []
    end
    for subdir in dirlist
      kinoko = read_kinoko_ini(File.join(kinoko_dir, subdir))
      if kinoko == nil
        next
      end
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
      if line.strip.empty? or line.strip() != '[KINOKO]'
        return nil
      end
      lineno = 0
      error = nil
      for line in f
        lineno += 1
        if line.end_with?("\x00") # XXX
          line = line[0, line.length - 2]
        end
        if line.strip.empty?
          next
        end
        line = line.encode('UTF-8', :invalid => :replace)
        if not line.include?('=')
          error = 'line {0:d}: syntax error'.format(lineno)
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
        if error
          logging.error('Error: {0}\n{1} (skipped)'.format(error, path))
          return nil
        end
      end
    end
    if not kinoko['title'].empty?
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
      if line
        name = line.strip.encode("UTF-8", :invalid => :replace)
      end
    end
    if not name.empty?
      return [name, top_dir] ## FIXME
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
        if line.strip.empty?
          next
        end
        if line.start_with?('#')
          name = line[1, line.length - 1].strip()
          next
        elsif name.empty?
          error = 'line ' + lineno.to_s + ': syntax error'
          break
        else
          value = line.strip.encode("UTF-8", :invalid => :replace)
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
      if error
        #logging.error('Error: {0}\n{1} (skipped)'.format(error, path))
        return nil
      end
    end
    if not katochan['name'].empty?
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
    default_sakura = desc.get('sakura.seriko.defaultsurface', '0')
    default_kero = desc.get('kero.seriko.defaultsurface', '10')
    if desc
      shell_name = desc.get('name')
    else
      shell_name = nil
    end
    if not shell_name or shell_name.empty?
      inst = read_install_txt(top_dir)
      if inst
        shell_name = inst.get('name')
      end
    end
    surface_set = {}
    shell_dir = File.join(top_dir, 'shell')
    for name, desc, subdir in find_surface_dir(shell_dir)
      surface_dir = File.join(shell_dir, subdir)
      surface_info, alias_, tooltips, seriko_descript = read_surface_info(surface_dir)
      if surface_info and \
        surface_info.include?('surface' + default_sakura.to_s) and \
        surface_info.include?('surface' + default_kero.to_s)
        if alias_ == nil
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
        if desc == nil
          desc = NConfig.null_config()
        end
        buf << [name, desc, subdir]
      end
    else
      begin
        dirlist = []
        Dir.foreach(top_dir, :encoding => 'UTF-8') do |file|
          if file == '..' or file == '.'
            next
          end
          dirlist << file
        end
      rescue #except OSError:
        dirlist = []
      end
      for subdir in dirlist
        desc = read_descript_txt(File.join(top_dir, subdir))
        if desc == nil
          desc = NConfig.null_config()
        end
        name = desc.get('name', subdir)
        buf << [name, desc, subdir]
      end
    end
    return buf
  end

  def self.read_surface_info(surface_dir)
    re_surface = Regexp.new('surface([0-9]+)\.(png|dgp|ddp)')
    surface = {}
    begin
      filelist = []
      Dir.foreach(surface_dir, :encoding => 'UTF-8') do |file|
        if file == '..' or file == '.'
          next
        end
        filelist << file
      end
    rescue #except OSError:
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
      if not match
        next
      end
      img = File.join(surface_dir, filename)
      if not File.readable_real?(img)
        next
      end
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
        begin
          img, prev_config = surface[key]
          prev_config.update(config)
          config = prev_config
        rescue #except KeyError:
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
        if not surface.include?(basename)
          surface[basename] = [File.join(surface_dir, filename),
                               NConfig.null_config()]
        end
      end
    end
    return surface, alias_, tooltips, seriko_descript
  end

  def self.read_surfaces_txt(surface_dir)
    re_alias = Regexp.new('^(sakura|kero|char[0-9]+)\.surface\.alias$')
    config_list = []
    path = File.join(surface_dir, 'surfaces.txt')
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
        if line.start_with?('#') or line.start_with?('//')
          next
        end
        if charset == 'CP932'
          # '\x81\x40': full-width space in CP932(Shift_JIS)
          temp = line.gsub('\x81\x40', '').strip()
        else
          temp = line.strip()
        end
        if temp.empty?
          next
        end
        if temp.start_with?('charset')
          begin
            charset = temp.split(',', 2)[1].strip().force_encoding('ascii')
          rescue #except:
            pass
          end
          next
        end
        if key == nil
          if temp.end_with?('{')
            key = temp[0, temp.length - 2].force_encoding(charset).encode("UTF-8", :invalid => :replace)
            opened = true
          else
            key = temp.force_encoding(charset).encode("UTF-8", :invalid => :replace)
          end
        elsif temp == '{'
          opened = true
        elsif temp.end_with?('}')
          if temp[0, temp.length - 2]
            buf << temp[0, temp.length - 2]
          end
          if not opened
            logging.error(
                          'syntax error: unbalnced "}" in surfaces.txt.')
          end
          match = re_alias.match(key)
          if match
            alias_buffer << key
            alias_buffer << '{'
            for line in buf
              alias_buffer << line.force_encoding(charset).encode("UTF-8", :invalid => :replace)
            end
            alias_buffer << '}'
          elsif key.end_with?('.tooltips')
            begin
              key = key[0, -10]
            rescue #except:
              pass
            end
            value = {}
            for line in buf
              line = line.split(',', 2)
              region << s[0].strip().force_encoding(charset).encode("UTF-8", :invalid => :replace)
              text << s[1].strip().force_encoding(charset).encode("UTF-8", :invalid => :replace)
              value[region] = text
              tooltips[key] = value
            end
          elsif key.start_with?('surface')
            keys = key.split(',')
            for key in keys
              if key.empty?
                next
              end
              if key.start_with?('surface')
                begin
                  key = [key[0, 7], key[7, key.length - 1].to_i.to_s].join('')
                rescue #except ValueError:
                  pass
                end
              else
                begin
                  key = ['surface', key.to_i.to_s].join('')
                rescue #except ValueError:
                  pass
                end
              end
              config_list << [key, NConfig.create_from_buffer(buf, charset)]
            end
          elsif key == 'descript'
            config_list << [key, NConfig.create_from_buffer(buf, charset)]
          end
          buf = []
          key = nil
          opened = false
        else
          buf << temp
        end
      end
    rescue #except IOError:
      return config_list
    end
    if not alias_buffer.empty?
      config_list << ['__alias__', Alias.create_from_buffer(alias_buffer)]
    end
    config_list << ['__tooltips__', tooltips]
    return config_list
  end

  def self.list_surface_elements(config)
    buf = []
    for n in 0..255
      key = ['element', n.to_s].join('')
      if not config.include?(key)
        break
      end
      spec = []
      for value in config[key].split(',')
        spec << value.strip()
      end
      begin
        method, filename, x, y = spec
        x = x.to_i
        y = y.to_i
      rescue #except ValueError:
        logging.error(
                      'invalid element spec for {0}: {1}'.format(key, config[key]))
        next
      end
      buf << [key, method, filename, x, y]
    end
    return buf
  end

  def self.read_balloon_info(balloon_dir)
    re_balloon = Regexp.new('balloon([skc][0-9]+)\.(png)')
    re_annex   = Regexp.new('(arrow[01]|sstp)\.(png)')
    balloon = {}
    begin
      filelist = []
      Dir.foreach(balloon_dir, :encoding => 'UTF-8') do |file|
        if file == '..' or file == '.'
          next
        end
        filelist << file
      end
    rescue #except OSError:
      filelist = []
    end
    for filename in filelist
      match = re_balloon.match(filename)
      if not match
        next
      end
      img = File.join(balloon_dir, filename)
      if match[2] != 'png' and \
        File.readable_real?([img[img.length - 4, img.length - 1], 'png'].join(''))
        next
      end
      if not File.readable_real?(img)
        next
      end
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
      if not match
        next
      end
      img = File.join(balloon_dir, filename)
      if not File.readable_real?(img)
        next
      end
      key = match[1]
      config = NConfig.null_config()
      balloon[key] = [img, config]
    end
    return balloon
  end

  def self.read_plugin_txt(src_dir)
    path = File.join(src_dir, 'plugin.txt')
    begin
      error = nil
      f = open(path, 'rb')
      charset = 'UTF-8' # default
      standard = 0.0
      plugin_name = startup = nil
      menu_items = []
      lineno = 0
      if f.read(3).bytes == [239, 187, 191] # "\xEF\xBB\xBF"
        f.close
        f = File.open(path, 'rb:BOM|UTF-8')
        charset = 'UTF-8'
      else
        f.seek(0) # rewind
      end
      error = nil
      for line in f
        lineno += 1
        if line.strip.empty? or line.start_with?('#')
          next
        end
        if not line.include?(':')
          error = 'line ' + lineno.to_s + ': syntax error'
          break
        end
        x = line.split(':', 2)
        name = x[0].strip()
        value = x[1].strip()
        if name == 'charset'
          charset = value.force_encoding('ascii')
        elsif name == 'standard'
          standard = value.to_f
        elsif name == 'name'
          plugin_name = value.force_encoding(charset).encode("UTF-8", :invalid => :replace)
        elsif name == 'startup'
          startup_list = value.force_encoding(charset).encode("UTF-8", :invalid => :replace).split(',')
          if not File.exists?(File.join(src_dir, startup_list[0]))
            error = 'line ' + lineno.to_s + ': invalid program name'
            break
          end
          startup = startup_list
        elsif name == 'menuitem'
          menuitem_list = value.force_encoding(charset).encode("UTF-8", :invalid => :replace).split(',')
          if menuitem_list.length < 2
            error = 'line ' + lineno.to_s + ': syntax error'
            break
          end
          menuitem_list[1] = File.join(plugin_dir, menuitem_list[1])
          if not File.exists?(File.join(src_dir, menuitem_list[1]))
            error = 'line ' + lineno.to_s + ': invalid program name'
            break
          end
          menu_items << [menuitem_list[0], menuitem_list[1, menuitem_list.length - 1]]
        elsif name == 'directory'
          plugin_dir = value.force_encoding(charset).encode("UTF-8", :invalid => :replace)
        else
          error = 'line ' + lineno.to_s + ': syntax error'
          break
        end
      end
      if error == nil
        if plugin_name == nil
          error = "the 'name' header field is required"
        elsif not startup and menu_items.empty?
          error = "either 'startup' or 'menuitem' header field is required"
        elsif standard < PLUGIN_STANDARD[0] or \
          standard > PLUGIN_STANDARD[1]
          error = "standard version mismatch"
        end
      end
    rescue #except IOError:
      return nil
    end
    if error
      #sys.stderr.write('Error: ' + error + '\n' + path + ' (skipped)\n')
      print("Error: " + error + "\n" + path + " (skipped)\n")
      return nil
    end
    menu_items << ['Uninstall', []]
    return plugin_name, plugin_dir, startup, menu_items
  end
end
