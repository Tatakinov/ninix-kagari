# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2003-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require_relative "logging"

module NConfig

  class Config < Hash

    def get(name, default: nil)
      keylist = (name.is_a?(Array) ? name : [name])
      key = keylist.find {|x| keys.include?(x) }
      if key.nil?
        if @child.nil?
          default
        else
          @child.get(name, default: default)
        end
      else
        self[key]
      end
    end

    def set_child(child)
      @child = child
    end
  end

  class SurfaceConfig < Config
    RE_ANIMATION = Regexp.new('\A([0-9]+)')
    RE_ANIMATION_2 = Regexp.new('\Aanimation([0-9]+)')
    RE_ANIMATION_PATTERN = Regexp.new('\A[0-9]+pattern([0-9]+)')
    RE_ANIMATION_PATTERN_2 = Regexp.new('\Aanimation[0-9]+\.pattern([0-9]+)')

    def initialize(ifnone = nil)
      super(ifnone)
      @animation = {}
    end

    def []=(key, value)
      super(key, value)
      match = nil
      [RE_ANIMATION, RE_ANIMATION_2].each do |r|
        unless match.nil?
          next
        end
        match = r.match(key)
      end
      if match.nil?
        return
      end
      id = match[1].to_i
      if value.nil?
        @animation.delete(id)
        return
      end
      unless @animation.include?(id)
        @animation[id] = []
      end
      match = nil
      [RE_ANIMATION_PATTERN, RE_ANIMATION_PATTERN_2].each do |r|
        unless match.nil?
          next
        end
        match = r.match(key)
      end
      if match.nil?
        return
      end
      pattern = match[1].to_i
      unless @animation[id].include?(pattern)
        @animation[id] << pattern
      end
    end

    def delete(key)
      match = nil
      [RE_ANIMATION, RE_ANIMATION_2].each do |r|
        unless match.nil?
          next
        end
        match = r.match(key)
      end
      if match.nil?
        return
      end
      id = match[1].to_i
      @animation.delete(id)
    end

    def each_animation
      return @animation.keys.sort
    end

    def each_pattern(id)
      return [] unless @animation.include?(id)
      return @animation[id].sort
    end
  end

  class DescriptConfig < Config
    RE_CHAR = Regexp.new('\A([^\.]+)\.(bind|menuitem)')
    RE_GROUP = Regexp.new('\A[^\.]+\.bindgroup([0-9]+)')
    RE_OPTION = Regexp.new('\A[^\.]+\.bindoption([0-9]+)')
    RE_MENU = Regexp.new('\A[^\.]+\.menuitem([0-9]+)')
    RE_MENU_EX = Regexp.new('\A[^\.]+\.menuitemex([0-9]+)')

    def initialize(ifnone = nil)
      super(ifnone)
      @group = {}
      @option = {}
      @menuitem = {}
      @menuitemex = {}
    end

    def []=(key, value)
      super(key, value)
      match = RE_CHAR.match(key)
      if match.nil?
        return
      end
      id = match[1]
      if value.nil?
        @group.delete(id)
        @option.delete(id)
        return
      end
      unless @group.include?(id) and @option.include?(id)
        @group[id] = []
        @option[id] = []
        @menuitem[id] = []
        @menuitemex[id] = []
      end
      match = RE_GROUP.match(key)
      unless match.nil?
        index = match[1].to_i
        @group[id] << index
        return
      end
      match = RE_OPTION.match(key)
      unless match.nil?
        index = match[1].to_i
        @option[id] << index
        return
      end
      match = RE_MENU.match(key)
      unless match.nil?
        index = match[1].to_i
        @menuitem[id] << index
        return
      end
      match = RE_MENU_EX.match(key)
      unless match.nil?
        index = match[1].to_i
        @menuitemex[id] << index
        return
      end
    end

    def delete(key)
      match = RE_CHAR.match(key)
      if match.nil?
        return
      end
      id = match[1]
      @animation.delete(id)
    end

    def each_group(char)
      return [] unless @group.include?(char)
      return @group[char].sort
    end

    def each_option(char)
      return [] unless @option.include?(char)
      return @option[char].sort
    end

    def each_menuitem(char)
      return [] unless @menuitem.include?(char)
      return @menuitem[char].sort
    end

    def each_menuitemex(char)
      return [] unless @menuitemex.include?(char)
      return @menuitemex[char].sort
    end
  end

  def self.create_from_file(path, klass = Config)
    has_bom = File.open(path) {|f| f.read(3) } == "\xEF\xBB\xBF"
    charset = has_bom ? 'UTF-8' : 'CP932'
    buf = []
    File.open(path, has_bom ? 'rb:BOM|UTF-8' : 'rb') {|f|
      while line = f.gets
        line = line.strip
        buf << line unless line.empty?
      end
    }
    return create_from_buffer(buf, klass = klass, charset: charset)
  end

  def self.create_from_buffer(buf, klass = Config, charset: 'CP932')
    dic = klass.new
    buf.each do |line|
      line = line.force_encoding(charset).encode(
        "UTF-8", :invalid => :replace, :undef => :replace)
      key, value = line.split(",", 2)
      next if key.nil? or value.nil?
      key.strip!
      case key
      when 'charset'
        value.strip!
        if Encoding.name_list.include?(value)
          charset = value
        else
          Logging::Logging.error('Unsupported charset ' + value)
        end
      when 'refreshundeletemask', 'icon', 'cursor', 'shiori', 'makoto'
        dic[key] = value
      else
        dic[key] = value.strip
      end
    end
    return dic
  end

  def self.null_config(klass = Config)
    klass.new
  end
end
