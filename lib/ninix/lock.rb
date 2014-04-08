# -*- coding: utf-8 -*-
#
#  Copyright (C) 2011-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module Lock

  def self.lockfile(fileobj)
    fileobj.flock(File::LOCK_EX | File::LOCK_NB)
  end

  def self.unlockfile(fileobj)
    fileobj.flock(File::LOCK_UN)
  end


  class TEST

    def initialize(path)
      f = open(path, "w")
      if Lock.lockfile(f)
        print("LOCK\n")
        sleep(5)
        Lock.unlockfile(f)
        print("UNLOCK\n")
      else
        print("LOCK: failed.\n")
      end
      f.close
    end
  end
end

$:.unshift(File.dirname(__FILE__))

Lock::TEST.new(ARGV.shift)
