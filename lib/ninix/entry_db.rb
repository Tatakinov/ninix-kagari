# -*- coding: utf-8 -*-
#
#  Copyright (C) 2001, 2002 by Tamito KAJIYAMA
#  Copyright (C) 2004-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
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
      elsif
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

  class TEST

    def initialize
      entry_db = EntryDB::EntryDatabase.new
      print('is_empty() =', entry_db.is_empty(), "\n")
      entry_db.add('#temp0', '\hふーん。\e')
      entry_db.add('#temp0', '\hそうなのかぁ。\e')
      entry_db.add('#temp0', '\hほうほう。\e')
      entry_db.add('#temp2', '\hいい感じだね。\e')
      entry_db.add('#temp3', '\hなるほど。\e')
      for _ in 0..4
        print('#temp0', entry_db.get('#temp0'), "\n")
      end
      for key in ['#temp1', '#temp2', '#temp3']
        print(key, entry_db.get(key), "\n")
      end
      print('is_empty() =', entry_db.is_empty(), "\n")
    end
  end
end

EntryDB::TEST.new
