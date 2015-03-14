# coding: utf-8

require "ninix/entry_db"

module NinixTest

  class EntryDBTest

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

NinixTest::EntryDBTest.new
