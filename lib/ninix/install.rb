# -*- coding: utf-8 -*-
#
#  install.rb - an installer module for ninix
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by Shun-ichi TAHARA <jado@flowernet.gr.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "zip"
require "open-uri"
require "fileutils"

require "gtk3"

require_relative "home"
require_relative "logging"
require_relative "version"


module Install

  class InstallError < StandardError
    #pass
  end

  def self.fatal(error)
    Logging::Logging.error(error) # XXX
    fail InstallError.new(error)
  end

  class Installer

    def initialize
      @dialog = Gtk::MessageDialog.new(:type => Gtk::MessageType::QUESTION,
                                       :buttons_type => :yes_no)
      @select_dialog = Gtk::Dialog.new()
      @select_dialog.add_button("_Cancel", Gtk::ResponseType::REJECT)
      @select_dialog.add_button("_OK", Gtk::ResponseType::ACCEPT)
      ls = Gtk::ListStore.new(Integer, String)
      tv = Gtk::TreeView.new(model=ls)
      renderer = Gtk::CellRendererText.new()
      col0 = Gtk::TreeViewColumn.new('No.', renderer, :text => 0)
      col1 = Gtk::TreeViewColumn.new('Path', renderer, :text => 1)
      tv.append_column(col0)
      tv.append_column(col1)
      sw = Gtk::ScrolledWindow.new()
      sw.set_vexpand(true)
      sw.set_policy(Gtk::PolicyType::AUTOMATIC, Gtk::PolicyType::AUTOMATIC)
      sw.add(tv)
      sw.show_all() # XXX
      @treeview = tv
      label = Gtk::Label.new(label='Multiple candidates found.\nSelect the path name of the supplement target.') ## FIXME: gettext
      ##label.set_use_markup(True)
      content_area = @select_dialog.content_area
      content_area.add(label)
      label.show()
      content_area.add(sw)
      @select_dialog.set_title('Select the target') ## FIXME: gettext
      @select_dialog.set_default_size(-1, 200)
    end

    def check_archive(filename)
      # check archive format
      Install.fatal('unknown archive format') unless ['.nar', '.zip'].include?(File.extname(filename).downcase)
    end

    def extract_files(filename)
      # extract files from the archive
      tmpdir = Dir.mktmpdir('ninix-aya')
      FileUtils.remove_entry_secure(tmpdir)
      begin
        FileUtils.mkdir_p(tmpdir)
      rescue
        Install.fatal('cannot make temporary directory')
      end
      url = nil
      if filename.start_with?('http:') or filename.start_with?('ftp:')
        url = filename
        filename = download(filename, tmpdir)
        if filename.nil?
          FileUtils.remove_entry_secure(tmpdir)
          Install.fatal('cannot download the archive file')
        end
      else
        check_archive(filename)
      end
      begin
        zf = Zip::File.new(filename)
        for entry in zf
          name = entry.name
          next if entry.directory?
          path = File.join(tmpdir, name)
          dname, fname = File.split(path)
          FileUtils.mkdir_p(dname) unless Dir.exists?(dname)
          buf = zf.read(name)
          of = open(path, 'wb')
          of.write(buf)
          of.close()
        end
        zf.close()
      rescue
        FileUtils.remove_entry_secure(tmpdir)
        Install.fatal('cannot extract files from the archive')
      end
      Dir.glob(tmpdir) { |path|
        if File.directory?(path)
          st_mode = File.stat(path).mode
          File.chmod(st_mode | 128 | 256 | 64, path)
        end
        if File.file?(path)
          st_mode = File.stat(path).mode
          File.chmod(st_mode | 128 | 256, path)
        end
      }
      rename_files(tmpdir)
      return tmpdir
    end

    def get_file_type(tmpdir)
      errno = 0
      # check the file type
      inst = Home.read_install_txt(tmpdir)
      if inst.nil?
        if File.exists?(File.join(tmpdir, 'kinoko.ini'))
          filetype = 'kinoko'
        else
          Install.fatal('cannot read install.txt from the archive')
        end
      else
        filetype = inst.get('type')
      end
      case filetype
      when 'ghost'
        unless Dir.exists?(File.join(tmpdir, 'ghost', 'master'))
          filetype = 'ghost.inverse'
        end
      when 'ghost with balloon'
        filetype = 'ghost.inverse'
      when 'shell', 'shell with balloon', 'supplement'
        if inst.include?('accept')
          filetype = 'supplement'
        else
          filetype = 'shell.inverse'
        end
      when 'balloon'
        # pass
      when 'skin'
        filetype = 'nekoninni'
      when 'katochan'
        # pass
      when 'kinoko'
        # pass
      else
        errno = 2 # unsupported file type
      end
      if ['shell.inverse', 'ghost.inverse'].include?(filetype)
        errno = 2 # unsupported file type
      end
      return filetype, errno
    end

    def install(filename, homedir)
      errno = 0
      begin
        tmpdir = extract_files(filename)
      rescue
        errno = 1
      end
      return nil, nil, nil, errno unless errno.zero?
      begin
        filetype, errno = get_file_type(tmpdir)
      rescue
        errno = 4
        filetype = nil
      end
      unless errno.zero?
        FileUtils.remove_entry_secure(tmpdir)
        return filetype, nil, nil, errno
      end
      begin
        case filetype
        when "ghost"
          target_dirs, names, errno = install_ghost(filename, tmpdir, homedir)
        when "supplement"
          target_dirs, names, errno = install_supplement(filename, tmpdir, homedir)
        when "balloon"
          target_dirs, names, errno = install_balloon(filename, tmpdir, homedir)
        when "kinoko"
          target_dirs, names, errno = install_kinoko(filename, tmpdir, homedir)
        when "nekoninni"
          target_dirs, names, errno = install_nekoninni(filename, tmpdir, homedir)
        when "katochan"
          target_dirs, names, errno = install_katochan(filename, tmpdir, homedir)
        else
          # should not reach here
        end
      rescue
        target_dirs = nil
        names = nil
        errno = 5
      ensure
        FileUtils.remove_entry_secure(tmpdir)
      end
      return filetype, target_dirs, names, errno
    end

    def download(url, basedir)
      #Logging::Logging.debug('downloading ' + url)
      begin
        ifile = open(url)
      rescue # IOError
        return nil
      end
      #Logging::Logging.debug(
      #  '(size = ' + ifile.length.to_s + ' bytes)')
      arcdir = Home.get_archive_dir()
      FileUtils.mkdir_p(arcdir) unless Dir.exists?(arcdir)
      basedir = arcdir
      filename = File.join(basedir, File.basename(url))
      begin
        ofile = open(filename, 'wb')
        while true
          data = ifile.read(4096)
          break if data.nil? # EOF
          ofile.write(data)
        end
      rescue # IOError, SystemCallError
        return nil
      end
      ofile.close()
      ifile.close()
      # check the format of the downloaded file
      check_archive(filename)
      begin
        zf = Zip::File.new(filename)
      rescue
        return nil
      ensure
        zf.close()
      end
      return filename
    end

    def rename_files(basedir)
      return if RUBY_PLATFORM.downcase =~ /mswin(?!ce)|mingw|cygwin|bccwin/ # XXX
      Dir.foreach(basedir) { |filename|
        next if /\A\.+\z/ =~ filename
        filename2 = filename.downcase
        path = File.join(basedir, filename2)
        if filename != filename2
          File.rename(File.join(basedir, filename), path)
        end
        rename_files(path) if File.directory?(path)
      }
    end

    def list_all_directories(top, basedir)
      dirlist = []
      Dir.foreach(File.join(top, basedir)) { |path|
        next if /\A\.+\z/ =~ path
        if File.directory?(File.join(top, basedir, path))
          dirlist += list_all_directories(top, File.join(basedir, path))
          dirlist << File.join(basedir, path)
        end
      }
      return dirlist
    end

    def remove_files_and_dirs(target_dir, mask)
      path = File.absolute_path(target_dir)
      return unless File.directory?(path)
      Dir.foreach(path) { |filename|
        next if /\A\.+\z/ =~ filename
        remove_files(mask, path, filename)
      }
      dirlist = list_all_directories(path, '')
      dirlist.sort!
      dirlist.reverse!
      for name in dirlist
        current_path = File.join(path, name)
        if File.directory?(current_path)
          head, tail = File.split(current_path)
          if not mask.include?(tail) and Dir.entries(current_path).reject{|entry| entry =~ /\A\.{1,2}\z/}.empty?
            FileUtils.remove_entry_secure(current_path)
          end
        end
      end
    end

    def remove_files(mask, top_dir, name)
      path = File.join(top_dir, name)
      if File.directory?(path) or mask.include?(name)
        # pass
      else
        File.delete(path)
      end
    end

    def lower_files(top_dir)
      return if RUBY_PLATFORM.downcase =~ /mswin(?!ce)|mingw|cygwin|bccwin/ # XXX
      n = 0
      Dir.foreach(top_dir) { |filename|
        next if /\A\.+\z/ =~ filename
        filename2 = filename.downcase
        path = File.join(top_dir, filename2)
        if filename != filename2
          File.rename(File.join(top_dir, filename), path)
          Logging::Logging.info(
            'renamed ' + File.join(top_dir, filename))
          n += 1
        end
        n += lower_files(path) if File.directory?(path)
      }
      return n
    end

    def confirm(message)
      @dialog.set_markup(message)
      response = @dialog.run()
      @dialog.hide()
      return response == Gtk::ResponseType::YES
    end

    def confirm_overwrite(path, type_string)
      return confirm(['Overwrite "', path, '"(', type_string, ')?'].join(''))
    end

    def confirm_removal(path, type_string)
      return confirm(['Remove "', path, '"(', type_string, ')?'].join(''))
    end

    def confirm_refresh(path, type_string)
      return confirm(['Remove "', path, '"(', type_string, ') to Refresh Install?'].join(''))
    end

    def select(candidates)
      fail "assert" unless candidates.length >= 1
      return candidates[0] if candidates.length == 1
      ls = @treeview.get_model()
      ls.clear()
      for i, item in enumerate(candidates)
        ls << [i, item]
      end
      ts = @treeview.get_selection()
      ts.select_iter(ls.get_iter_first())
      response = @select_dialog.run()
      @select_dialog.hide()
      return nil if response != Gtk::ResponseType::ACCEPT
      model, it = ts.get_selected()
      return candidates[model.get_value(it, 0)]
    end

    def install_ghost(archive, tmpdir, homedir)
      # find install.txt
      inst = Home.read_install_txt(tmpdir)
      Install.fatal('install.txt not found') if inst.nil?
      target_dir = inst.get('directory')
      Install.fatal('"directory" not found in install.txt') if target_dir.nil?
      prefix = File.join(homedir, 'ghost', target_dir)
      ghost_src = File.join(tmpdir, 'ghost', 'master')
      shell_src = File.join(tmpdir, 'shell')
      ghost_dst = File.join(prefix, 'ghost', 'master')
      shell_dst = File.join(prefix, 'shell')
      filelist = []
      ##filelist << [File.join(tmpdir, 'install.txt'),
      ##             File.join(prefix, 'install.txt')] # XXX
      readme_txt = File.join(tmpdir, 'readme.txt')
      if File.exists?(readme_txt)
        filelist << [readme_txt,
                     File.join(prefix, 'readme.txt')]
      end
      thumbnail_png = File.join(tmpdir, 'thumbnail.png')
      thumbnail_pnr = File.join(tmpdir, 'thumbnail.pnr')
      if File.exists?(thumbnail_png)
        filelist << [thumbnail_png,
                     File.join(prefix, 'thumbnail.png')]
      elsif File.exists?(thumbnail_pnr)
        filelist << [thumbnail_pnr,
                     File.join(prefix, 'thumbnail.pnr')]
      end
      for path in list_all_files(ghost_src, '')
        filelist << [File.join(ghost_src, path),
                     File.join(ghost_dst, path)]
      end
      ghost_name = inst.get('name')
      # find shell
      for path in list_all_files(shell_src, '')
        filelist << [File.join(shell_src, path),
                     File.join(shell_dst, path)]
      end
      # find balloon
      balloon_dir = inst.get('balloon.directory')
      balloon_name = nil
      unless balloon_dir.nil?
        balloon_dir = Home.get_normalized_path(balloon_dir)
        balloon_dst = File.join(homedir, 'balloon', balloon_dir)
        balloon_src = inst.get('balloon.source.directory')
        unless balloon_src.nil?
          balloon_src = Home.get_normalized_path(balloon_src)
        else
          balloon_src = balloon_dir
        end
        inst_balloon = Home.read_install_txt(
                                             File.join(tmpdir, balloon_src))
        if Dir.exists?(balloon_dst) and \
          not confirm_removal(balloon_dst, 'balloon')
          # pass # don't install balloon
        else
          if Dir.exists?(balloon_dst)
            # uninstall older versions of the balloon
            remove_files_and_dirs(balloon_dst, [])
          end
          balloon_list = []
          for path in list_all_files(File.join(tmpdir, balloon_src), '')
            balloon_list << [File.join(tmpdir, balloon_src, path),
                             File.join(balloon_dst, path)]
          end
          install_files(balloon_list)
          unless inst_balloon.nil?
            balloon_name = inst_balloon.get('name')
          end
        end
      end
      if Dir.exists?(prefix)
        inst_dst = Home.read_install_txt(prefix)
        unless inst.get('refresh', :default => 0).to_i.zero?
          # uninstall older versions of the ghost
          if confirm_refresh(prefix, 'ghost')
            mask = []
            for path in inst.get('refreshundeletemask', :default => '').split(':', 0)
              mask << Home.get_normalized_path(path)
            end
            mask << 'HISTORY'
            remove_files_and_dirs(prefix, mask)
          else
            return nil, nil, 3
          end
        else
          unless confirm_overwrite(prefix, 'ghost')
            return nil, nil, 3
          end
        end
      end
      # install files
      Logging::Logging.info('installing ' + archive + ' (ghost)')
      install_files(filelist)
      # create SETTINGS
      path = File.join(prefix, 'SETTINGS')
      unless File.exists?(path)
        begin
          f = open(path, 'w')
          unless balloon_dir.nil?
            f.write(["balloon_directory, ", balloon_dir, "\n"].join(''))
          end
        rescue # IOError, SystemCallError => e
          Logging::Logging.error('cannot write ' + path)
        ensure
          f.close()
        end
        if balloon_dir.nil? # XXX
          balloon_dir = ''
        end
      end
      return [[target_dir, balloon_dir], [ghost_name, balloon_name], 0]
    end

    def install_supplement(archive, tmpdir, homedir)
      inst = Home.read_install_txt(tmpdir)
      if not inst.nil? and inst.include?('accept')
        Logging::Logging.info('searching supplement target ...')
        candidates = []
        begin
          dirlist = Dir.entries(File.join(homedir, 'ghost')).reject{|entry| entry =~ /\A\.{1,2}\z/}
        rescue SystemCallError
          dirlist = []
        end
        for dirname in dirlist
          path = File.join(homedir, 'ghost', dirname)
          if File.exists?(File.join(path, 'shell', 'surface.txt'))
            next # ghost.inverse(obsolete)
          end
          desc = Home.read_descript_txt(
                                        File.join(path, 'ghost', 'master'))
          if not desc.nil? and desc.get('sakura.name') == inst.get('accept')
            candidates << dirname
          end
        end
        if candidates.empty?
          Logging:Logging.info('not found')
          return nil, nil, 4
        else
          target = select(candidates)
          if target.nil?
            return nil, nil, 4
          end
          path = File.join(homedir, 'ghost', target)
          if inst.include?('directory')
            if inst.get('type') == 'shell'
              path = File.join(path, 'shell', inst['directory'])
            else
              unless inst.include?('type')
                Logging::Logging.error('supplement type not specified')
              else
                Logging::Logging.error('unsupported supplement type: ' + inst['type'])
              end
              return nil, nil, 4
            end
          end
          Logging::Logging.info('found')
          unless Dir.exists?(path)
            FileUtils.mkdir_p(path)
          end
          File.delete(File.join(tmpdir, 'install.txt'))
          distutils.dir_util.copy_tree(tmpdir, path)
          return target, inst.get('name'), 0
        end
      end
    end

    def install_balloon(archive, srcdir, homedir)
      # find install.txt
      inst = Home.read_install_txt(srcdir)
      if inst.nil?
        Install.fatal('install.txt not found')
      end
      target_dir = inst.get('directory')
      if target_dir.nil?
        Install.fatal('"directory" not found in install.txt')
      end
      dstdir = File.join(homedir, 'balloon', target_dir)
      filelist = []
      for path in list_all_files(srcdir, '')
        filelist << [File.join(srcdir, path),
                     File.join(dstdir, path)]
      end
      ##filelist << [File.join(srcdir, 'install.txt'),
      ##             File.join(dstdir, 'install.txt')]
      if Dir.exists?(dstdir)
        inst_dst = Home.read_install_txt(dstdir)
        unless inst.get('refresh', :default => 0).to_i.zero?
          # uninstall older versions of the balloon
          if confirm_refresh(dstdir, 'balloon')
            mask = []
            for path in inst.get('refreshundeletemask', :default => '').split(':', 0)
              mask << Home.get_normalized_path(path)
            end
            remove_files_and_dirs(dstdir, mask)
          else
            return nil, nil, 3
          end
        else
          unless confirm_overwrite(dstdir, 'balloon')
            return nil, nil, 3
          end
        end
      end
      # install files
      Logging::Logging.info('installing ' + archive + ' (balloon)')
      install_files(filelist)
      return target_dir, inst.get('name'), 0
    end

    def uninstall_kinoko(homedir, name)
      begin
        dirlist = Dir.entries(File.join(homedir, 'kinoko')).reject{|entry| entry =~ /\A\.{1,2}\z/}
      rescue SystemCallError
        return
      end
      for subdir in dirlist
        path = File.join(homedir, 'kinoko', subdir)
        kinoko = Home.read_kinoko_ini(path)
        if kinoko.nil?
          next
        end
        kinoko_name = kinoko['title']
        if kinoko_name == name
          kinoko_dir = File.join(homedir, 'kinoko', subdir)
          if confirm_removal(kinoko_dir, 'kinoko')
            FileUtils.remove_entry_secure(kinoko_dir)
          end
        end
      end
    end

    def install_kinoko(archive, srcdir, homedir)
      # find kinoko.ini
      kinoko = Home.read_kinoko_ini(srcdir)
      if kinoko.nil?
        Install.fatal('failed to read kinoko.ini')
      end
      kinoko_name = kinoko['title']
      unless kinoko['extractpath'].nil?
        dstdir = File.join(homedir, 'kinoko', kinoko['extractpath'])
      else
        dstdir = File.join(homedir, 'kinoko', File.basename(archive)[0,-4])
      end
      # find files
      filelist = []
      Dir.foreach(srcdir) { |filename|
        next if /\A\.+\z/ =~ filename
        path = File.join(srcdir, filename)
        if File.file?(path)
          filelist << [path, File.join(dstdir, filename)]
        end
      }
      # uninstall older versions of the kinoko
      uninstall_kinoko(homedir, kinoko_name)
      # install files
      Logging::Logging.info('installing ' + archive + ' (kinoko)')
      install_files(filelist)
      return dstdir, [kinoko_name, kinoko['ghost'], kinoko['category']], 0
    end

    def uninstall_nekoninni(homedir, dir)
      nekoninni_dir = File.join(homedir, 'nekodorif', 'skin', dir)
      return unless Dir.exists?(nekoninni_dir)
      if confirm_removal(nekoninni_dir, 'nekodorif skin')
        FileUtils.remove_entry_secure(nekoninni_dir)
      end
    end

    def install_nekoninni(archive, srcdir, homedir)
      # find install.txt
      inst = Home.read_install_txt(srcdir)
      if inst.nil?
        Install.fatal('install.txt not found')
      end
      target_dir = inst.get('directory')
      if target_dir.nil?
        Install.fatal('"directory" not found in install.txt')
      end
      dstdir = File.join(homedir, 'nekodorif', 'skin', target_dir)
      # find files
      filelist = []
      Dir.foreach(srcdir) { |filename|
        next if /\A\.+\z/ =~ filename
        path = File.join(srcdir, filename)
        if File.file?(path)
          filelist << [path, File.join(dstdir, filename)]
        end
      }
      # uninstall older versions of the skin
      uninstall_nekoninni(homedir, target_dir)
      # install files
      Logging::Logging.info('installing ' + archive + ' (nekodorif skin)')
      install_files(filelist)
      return target_dir, inst.get('name'), 0
    end

    def uninstall_katochan(homedir, target_dir)
      katochan_dir = File.join(homedir, 'nekodorif', 'katochan', target_dir)
      return unless Dir.exists?(katochan_dir)
      if confirm_removal(katochan_dir, 'nekodorif katochan')
        FileUtils.remove_entry_secure(katochan_dir)
      end
    end

    def install_katochan(archive, srcdir, homedir)
      # find install.txt
      inst = Home.read_install_txt(srcdir)
      if inst.nil?
        Install.fatal('install.txt not found')
      end
      target_dir = inst.get('directory')
      if target_dir.nil?
        Install.fatal('"directory" not found in install.txt')
      end
      dstdir = File.join(homedir, 'nekodorif', 'katochan', target_dir)
      # find files
      filelist = []
      Dir.foreach(srcdir) { |filename|
        next if /\A\.+\z/ =~ filename
        path = File.join(srcdir, filename)
        if File.file?(path)
          filelist << [path, File.join(dstdir, filename)]
        end
      }
      # uninstall older versions of the skin
      uninstall_katochan(homedir, target_dir)
      # install files
      Logging::Logging.info('installing ' + archive + ' (nekodorif katochan)')
      install_files(filelist)
      return target_dir, inst.get('name'), 0
    end

    def list_all_files(top, target_dir)
      filelist = []
      Dir.foreach(File.join(top, target_dir)) { |path|
        next if /\A\.+\z/ =~ path
        if File.directory?(File.join(top, target_dir, path))
          filelist += list_all_files(
                                     top, File.join(target_dir, path))
        else
          filelist << File.join(target_dir, path)
        end
      }
      return filelist
    end

    def install_files(filelist)
      for from_path, to_path in filelist
        dirname, filename = File.split(to_path)
        FileUtils.mkdir_p(dirname) unless Dir.exists?(dirname)
        FileUtils.copy(from_path, to_path)
      end
    end
  end
end
