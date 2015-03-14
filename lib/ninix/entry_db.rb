# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2004-2015 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module EntryDB

  class EntryDatabase

    def initialize(db=nil)
      if db != nil
        @__db = db
      elsif
        @__db = Hash.new
      end
    end

    def add(key, script)
      if @__db.has_key?(key)
        entries = @__db[key]
      else
        entries = []
      end
      entries << script
      @__db[key] = entries
    end

    def get(key, default=nil)
      if @__db.has_key?(key)
        entries = @__db[key]
        return entries.sample
      else
        return default
      end
    end

    def is_empty
      return @__db.empty?
    end
  end
end
