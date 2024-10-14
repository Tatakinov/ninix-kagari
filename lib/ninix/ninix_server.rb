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
require 'tmpdir'

require_relative "home"
require_relative "metamagic"

class NinixServer < MetaMagic::Holon
  def self.sockdir
    File.join(Home.get_ninix_home, 'sock')
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
    super("") ## FIXME
    name = File.join(NinixServer.sockdir, name)
    # TODO error handling
    FileUtils.mkdir_p(NinixServer.sockdir) if not Dir.exist?(NinixServer.sockdir)
    FileUtils.rm(name) if File.exist?(name)
    @socket = UNIXServer.new(name)
    ObjectSpace.define_finalizer(self, NinixServer.finalize(@socket, name))
  end

  def accept_nonblock
    return @socket.accept_nonblock
  end

  def close
    @socket.close
  end
end
