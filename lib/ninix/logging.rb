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
