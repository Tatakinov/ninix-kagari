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

require 'gettext'

module Version
  include GetText

  bindtextdomain("ninix-kagari")

  def self.NUMBER
    '2.2.2'
  end

  def self.CODENAME
    'power cycle'
  end

  def self.VERSION
    "#{self.NUMBER} (#{self.CODENAME})"
  end

  def self.VERSION_INFO
    '\h\s[0]\w8ninix-kagari '
      .concat("#{self.VERSION}")
      .concat('\n')
      .concat(_('Are igai No Nanika with "Nin\'i" for X'))
      .concat('\n')
      .concat('\_q')
      .concat('Copyright (c) 2001, 2002 Tamito KAJIYAMA\n')
      .concat('Copyright (c) 2002-2006 MATSUMURA Namihiko\n')
      .concat('Copyright (c) 2002-2019 Shyouzou Sugitani\n')
      .concat('Copyright (c) 2002, 2003 ABE Hideaki\n')
      .concat('Copyright (c) 2003-2005 Shun-ichi TAHARA\n')
      .concat('Copyright (c) 2024, 2025 Tatakinov\e')
  end
end
