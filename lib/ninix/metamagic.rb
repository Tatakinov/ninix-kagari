# -*- coding: utf-8 -*-
#
#  metamagic.py - unknown unknowns
#  Copyright (C) 2011-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module MetaMagic

  class Meme

    def initialize(key)
      @key = key
      @baseinfo = nil
      @menuitem = nil
    end

    def create_menuitem(data)
      return nil
    end

    def delete_by_myself
    end

    def key
      return @key
    end

    def key=(data) # read only
    end

    def baseinfo
      return @baseinfo
    end

    def baseinfo=(data)
      @baseinfo = data
      @menuitem = create_menuitem(data)
      if menuitem == nil
        delete_by_myself()
        return
      end
      @menuitem = menuitem
    end

    def menuitem
      return @menuitem
    end

    def menuitem=(data) # read only
    end
  end


  class Holon

    def initialize(key)
      @key = key
      @baseinfo = nil
      @menuitem = nil
      @instance = nil
    end
   
    def create_menuitem(data)
      return nil
    end

    def delete_by_myself
    end

    def create_instance(data)
      return nil
    end

    def key=(data) # read only
    end

    def key
      return @key
    end

    def baseinfo # forbidden
      return nil
    end

    def baseinfo=(data)
      @baseinfo = data
      if @instance == nil
        @instance = create_instance(data)
      end
      if @instance == nil
        delete_by_myself()
        return
      else
        @instance.new(data) # reset
        menuitem = create_menuitem(data)
        if menuitem == nil
          delete_by_myself()
          return
        end
        @menuitem = menuitem
      end
    end

    def menuitem
      return @menuitem
    end

    def menuitem=(data) # read only
    end

    def instance
      return @instance
    end

    def instance=(data) # read only
    end
  end

  class TEST_Meme < Meme

    def create_menuitem(data)
      return data => 'menu'
    end
  end

  class TEST_Holon < Holon

    def create_menuitem(data)
      return data => 'menu'
    end

    def create_instance(data)
      return Hash
    end
  end

  class TEST

    def initialize
      meme = TEST_Meme.new('meta')
      meme.baseinfo = 'base'
      meme.key = ''
      meme.menuitem = ''
      print("Meme: \n")
      print("  KEY: ")
      print(meme.key)
      print("\n")
      print("  BASE INFO: ")
      print(meme.baseinfo)
      print("\n")
      print("  MENU ITEM: ")
      print(meme.menuitem)
      print("\n")

      holon = TEST_Holon.new('magic')
      holon.baseinfo = 'base'
      holon.key = ''
      holon.menuitem = ''
      holon.instance = ''
      print("HOLON: \n")
      print("  KEY: ")
      print(holon.key)
      print("\n")
      print("  BASE INFO: ")
      print(holon.baseinfo)
      print("\n")
      print("  MENU ITEM: ")
      print(holon.menuitem)
      print("\n")
      print("  INSTANCE: ")
      print(holon.instance)
      print("\n")
    end
  end
end

MetaMagic::TEST.new
