# -*- coding: utf-8 -*-
#
#  gomi.rb - a gomi.dll compatible Saori module for ninix
#  Copyright (C) 2012-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "optparse"

require "gio2"

require_relative "../dll"


module Gomi

  class Saori < DLL::SAORI

    def initialize
      if ENV.include?('XDG_DATA_HOME')
        @xdg_data_home = ENV['XDG_DATA_HOME']
      else
        @xdg_data_home = File.join(ENV['HOME'], '.local' , 'share')
      end
      @home_trash = File.join(@xdg_data_home, 'Trash')
      super()
    end

    def setup
      @parser = OptionParser.new
      begin
        @notify = Gio::DBusProxy.new(
          Gio::BusType::SESSION, 0, nil,
          'org.gnome.Nautilus', '/org/gnome/Nautilus',
          'org.gnome.Nautilus.FileOperations', nil)
        return 1
      rescue
        @notify = nil
        return 0
      end
    end

    def get_volume_trash
      vm = Gio::VolumeMonitor.get()
      result = []
      for m in vm.mounts
        mp = m.default_location.path
        next if mp.nil?
        volume_trash = File.join(mp, '.Trash', Process::UID.eid.to_s)
        unless File.exist?(volume_trash)
          volume_trash = File.join(mp, '.Trash-' + Process::UID.eid.to_s)
        end
        next unless File.exist?(volume_trash)
        result << volume_trash
      end
      return result
    end

    def get_dir_size(dir_name)
      file_count = 0
      dir_size = 0
      for file in Dir.glob(File.join(dir_name, '**', '*'))
        file_count += 1
        if File.file?(file)
          dir_size += File.size(file)
        end
      end
      return [file_count, dir_size]
    end

    def empty_trash(path)
      Dir.foreach(File.join(path, 'info')) { |info|
        next if info == '.' or info == '..'
        trash = info[0..-'.trashinfo'.length-1]
        filepath = File.join(path, 'files', trash)
        infopath = File.join(path, 'info', info)
        if File.file?(filepath) or File.symlink?(filepath)
          File.delete(filepath)
          File.delete(infopath)
        elsif File.directory?(filepath)
          FileUtils.rm_rf(filepath)
          File.delete(infopath)
        end
      }
    end

    def execute(argument)
      return RESPONSE[400] if argument.nil? or argument.empty?
      args = @parser.getopts(
        argument[0].split(nil, 0),
        'enVafqsvw:',
        'empty', 'number-of-items', 'version', 'asynchronous', 'force',
        'quiet', 'silent', 'verbose', 'hwnd:')
      return RESPONSE[400] if @notify.nil?
      if args['number-of-items'] or args['n']
        file_count, dir_size = get_dir_size(@home_trash)
        for volume_trash in get_volume_trash()
          count, size = get_dir_size(volume_trash)
          file_count += count
          dir_size += size
        end
        return ["SAORI/1.0 200 OK\r\n",
                "Result: ",
                file_count.to_s.encode('ascii', :invalid => :replace, :undef => :replace),
                "\r\n",
                "Reference0: ",
                dir_size.to_s.encode('ascii', :invalid => :replace, :undef => :replace),
                "\r\n\r\n"].join("")
      elsif args['empty'] or args['e']
        if args['force'] or args['f']
          empty_trash(@home_trash)
          for volume_trash in get_volume_trash()
            empty_trash(volume_trash)
          end
        else
          result = @notify.call_sync(
            'EmptyTrash', nil, ## GLib.Variant('()', ()),
            Gio::DBusCallFlags::NONE, -1, nil)
        end
        return ["SAORI/1.0 200 OK\r\n",
                "Result: ",
                "1", # FIXME
                "\r\n\r\n"].join("")
      end
    end
  end
end
