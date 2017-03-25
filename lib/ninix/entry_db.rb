# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2004-2017 by Shyouzou Sugitani <shy@users.osdn.me>
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

    def initialize(db: nil)
      fail "assert" unless (db.nil? or db.is_a?(Hash))
      @__db = (db.nil? ? Hash.new : db)
    end

    def add(key, script)
      @__db[key] = [] if not @__db.has_key?(key)
      @__db[key] << script
    end

    def get(key, default: nil)
      @__db.has_key?(key) ? @__db[key].sample : default
    end

    def is_empty
      @__db.empty?
    end
  end
end
