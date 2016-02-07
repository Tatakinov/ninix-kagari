# -*- coding: utf-8 -*-
#
#  Copyright (C) 2005-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'gettext'

module Version
  include GetText

  bindtextdomain("ninix-aya")

  def self.NUMBER
    return '4.999.1'
  end

  def self.CODENAME
    return 'shotgun debugging'
  end

  def self.VERSION
    return self.NUMBER + ' (' + self.CODENAME + ')'
  end

  def self.VERSION_INFO
    return '\h\s[0]\w8ninix-aya ' + self.VERSION + '\n' +
      _('Are igai No Nanika with "Nin\'i" for X') + '\n' +
      '\_q' +
      'Copyright (c) 2001, 2002 Tamito KAJIYAMA\n' +
      'Copyright (c) 2002-2006 MATSUMURA Namihiko\n' +
      'Copyright (c) 2002-2016 Shyouzou Sugitani\n' +
      'Copyright (c) 2002, 2003 ABE Hideaki\n' +
      'Copyright (c) 2003-2005 Shun-ichi TAHARA\e'
  end
end
