# -*- coding: utf-8 -*-
#
#  Copyright (C) 2015-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "logger"

module Logging

  class Logging
    @@logger = []
    @@logger << Logger.new(STDOUT)
    @@level = Logger::WARN

    def initialize
      ##@@logger.level = Logger::WARN
    end

    def self.set_level(level)
      @@logger.each do |logger|
        logger.level = level
      end
      @@level = level
    end

    def self.add_logger(logger)
      @@logger << logger
      logger.level = @@level
    end

    def self.info(message)
      @@logger.each do |logger|
        logger.info(message)
      end
    end

    def self.error(message)
      @@logger.each do |logger|
        logger.error(message)
      end
    end

    def self.warning(message)
      @@logger.each do |logger|
        logger.warn(message)
      end
    end

    def self.debug(message)
      @@logger.each do |logger|
        logger.debug(message)
      end
    end
  end
end
