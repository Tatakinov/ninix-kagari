require "logger"

module Logging

  class Logging
    @@logger = Logger.new(STDOUT)

    def initialize
      ##@@logger.level = Logger::SEV_LABEL[2]
    end

    def self.info(message)
      @@logger.info(message)
    end

    def self.error(message)
      @@logger.error(message)
    end

    def self.warning(message)
      @@logger.warn(message)
    end

    def self.debug(message)
      @@logger.debug(message)
    end
  end
end
