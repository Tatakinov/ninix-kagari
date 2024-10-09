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

require 'fileutils'
require 'socket'

class NinixSocket
  def self.sockdir
    Dir.tmpdir + '/ninix_kagari'
  end

  def self.finalize(socket, name)
    proc do
      socket.close
      if File.exist?(name)
        FileUtils.rm(name)
      end
    end
  end

  def initialize(name)
    name = File.join(NinixSocket.sockdir, name)
    FileUtils.rm(name) if File.exist?(name)
    @socket = UNIXServer.new(name)
    ObjectSpace.define_finalizer(self, NinixSocket.finalize(@socket, name))
  end

  def accept
    return @socket.accept_nonblock
  end
end
