# -*- coding: utf-8 -*-
#
#  metamagic.rb - unknown unknowns
#  Copyright (C) 2011-2017 by Shyouzou Sugitani <shy@users.osdn.me>
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
      @parent = nil
      @handlers = {}
    end

    def set_responsible(parent)
      @parent = parent
    end

    def handle_request(event_type, event, *arglist)
      fail "assert" unless ['GET', 'NOTIFY'].include?(event_type)
      unless @handlers.include?(event)
        if self.class.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = @parent.handle_request(
            event_type, event, *arglist)
        end
      else
        result = method(@handlers[event]).call(*arglist)
      end
      return result if event_type == 'GET'
    end

    def create_menuitem(data)
      nil
    end

    def delete_by_myself
    end

    def key
      @key
    end

    def key=(data) # read only
    end

    def baseinfo
      @baseinfo
    end

    def baseinfo=(data)
      @baseinfo = data
      @menuitem = create_menuitem(data)
      delete_by_myself if menuitem.nil?
    end

    def menuitem
      @menuitem
    end

    def menuitem=(data) # read only
    end
  end


  class Holon
    attr_reader :baseinfo, :instance

    def initialize(key)
      @key = key
      @baseinfo = nil
      @menuitem = nil
      @instance = nil
      @parent = nil
    end

    def set_responsible(parent)
      @parent = parent
    end
   
    def handle_request(event_type, event, *arglist)
      fail "assert" unless ['GET', 'NOTIFY'].include?(event_type)
      unless @handlers.include?(event)
        if self.class.method_defined?(event)
          result = method(event).call(*arglist)
        else
          result = @parent.handle_request(
            event_type, event, *arglist)
        end
      else
        result = method(@handlers[event]).call(*arglist)
      end
      return result if event_type == 'GET'
    end

    def create_menuitem(data)
      nil
    end

    def delete_by_myself
    end

    def create_instance(data)
      nil
    end

    def key=(data) # read only
    end

    def key
      @key
    end

    def baseinfo # forbidden
      nil
    end

    def baseinfo=(data)
      @baseinfo = data
      @instance = create_instance(data) if @instance.nil?
      if @instance.nil?
        delete_by_myself()
      else
        @instance.new_(*data) # reset
        @menuitem = create_menuitem(data)
        delete_by_myself if menuitem.nil?
      end
    end

    def menuitem
      @menuitem
    end

    def menuitem=(data) # read only
    end

    def instance
      @instance
    end

    def instance=(data) # read only
    end
  end
end
