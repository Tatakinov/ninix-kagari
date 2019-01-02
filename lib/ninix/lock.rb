# -*- coding: utf-8 -*-
#
#  Copyright (C) 2011-2019 by Shyouzou Sugitani <shy@users.osdn.me>
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
end
