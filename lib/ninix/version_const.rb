# -*- coding: utf-8 -*-
#
#  Copyright (C) 2005-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module Version

  def self.NUMBER
    '3.3.0'
  end

  def self.CODENAME
    'power cycle'
  end

  def self.VERSION
    "#{self.NUMBER} (#{self.CODENAME})"
  end
end
