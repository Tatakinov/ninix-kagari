# -*- coding: utf-8 -*-
#
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module CaseInsensitiveFile
  def self.exist?(path, dir: false)
    if dir and Dir.exist?(path)
      return path
    end
    if not dir and File.exist?(path)
      return path
    end
    dirname = exist?(File.dirname(path), dir: true)
    if dirname.nil?
      return nil
    end
    basename = File.basename(path)
    Dir.open(dirname).each_child do |f|
      if basename.downcase == f.downcase
        return File.join(dirname, f)
      end
    end
    return nil
  end
end
