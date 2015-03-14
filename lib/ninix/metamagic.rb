# -*- coding: utf-8 -*-
#
#  metamagic.rb - unknown unknowns
#  Copyright (C) 2011-2015 by Shyouzou Sugitani <shy@users.sourceforge.jp>
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
end
