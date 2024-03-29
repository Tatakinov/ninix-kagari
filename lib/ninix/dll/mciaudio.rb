# -*- coding: utf-8 -*-
#
#  mciaudio.rb - a MCIAUDIO compatible Saori module for ninix
#  Copyright (C) 2002-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "uri"

begin
  require "gst"
rescue LoadError
  Gst = nil
end

require_relative "../home"
require_relative "../dll"
require_relative "../logging"


module Mciaudio

  class Saori < DLL::SAORI

    def initialize
      super()
      @player = Gst::ElementFactory.make('playbin', 'player')
      fakesink = Gst::ElementFactory.make('fakesink', 'fakesink')
      @player.set_property('video-sink', fakesink)
      bus = @player.bus
      bus.add_watch do |bus, message|
        on_message(bus, message)
        true
      end
      @filepath = nil
      @__sakura = nil
    end

    def need_ghost_backdoor(sakura)
      @__sakura = sakura
    end

    def check_import
      unless @__sakura.nil? or Gst.nil?
        return 1
      else
        return 0
      end
    end

    def finalize
      @player.set_state(Gst::State::NULL)
      @player = nil
      @filepath = nil
      return 1
    end

    def execute(argv)
      return RESPONSE[400] if argv.nil?
      argc = argv.length
      case argc
      when 1
        fail "assert" if @player.nil?
        case argv[0]
        when 'stop'
          @player.set_state(Gst::State::NULL)
        when 'play'
          case @player.get_state(timeout=Gst::SECOND)[1]
          when Gst::State::PAUSED
            @player.set_state(Gst::State::PLAYING)
            return RESPONSE[204]
          when Gst::State::PLAYING
            @player.set_state(Gst::State::PAUSED)
            return RESPONSE[204]
          end
          if not @filepath.nil? and File.exist?(@filepath)
            @player.set_property(
              'uri', 'file://' + URI.escape(@filepath))
            @player.set_state(Gst::State::PLAYING)
          end
        end
      when 2
        if argv[0] == 'load'
          @player.set_state(Gst::State::NULL)
          filename = Home.get_normalized_path(argv[1])
          if File.absolute_path(filename) == filename
            return RESPONSE[400]
          end
          @filepath = File.join(@__sakura.get_prefix(),
                                'ghost/master',
                                @dir,
                                filename)
        end
      end
      return RESPONSE[204]
    end

    def on_message(bus, message)
      return if message.nil? # XXX: workaround for Gst Version < 0.11
      case message.type
      when Gst::MessageType::EOS
        @player.set_state(Gst::State::NULL)
      when Gst::MessageType::ERROR
        @player.set_state(Gst::State::NULL)
        err, debug = message.parse_error()
        Logging::Logging.error("Error: #{err}, #{debug}")
      end
    end
  end
end
