# -*- coding: utf-8 -*-
#
#  mciaudior.rb - a MCIAUDIOR compatible Saori module for ninix
#  Copyright (C) 2003-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "uri"

require "gst"

require_relative "../home"
require_relative "../dll"


module MCIAudioR

  class Saori < DLL::SAORI

    def initialize
      super()
      @player = Gst::ElementFactory.make('playbin', 'player')
      fakesink = Gst::ElementFactory.make('fakesink', 'fakesink')
      @player.set_property('video-sink', fakesink)
      bus = @player.bus
      bus.add_watch do |bus, message|
        on_message(bus, message)
      end
      @filepath = nil
      @loop = false
    end

    def check_import
      if Gst != nil
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
      if argv == nil
        return RESPONSE[400]
      end
      argc = argv.length
      if argc == 1
        rasie "assert" unless @player != nil
        if argv[0] == 'stop'
          @player.set_state(Gst::State::NULL)
        elsif ['play', 'loop'].include?(argv[0])
          if argv[0] == 'loop'
            @loop = true
          end
          if @player.get_state(timeout=Gst::SECOND)[1] == Gst::State::PAUSED
            @player.set_state(Gst::State::PLAYING)
            return RESPONSE[204]
          elsif @player.get_state(timeout=Gst::SECOND)[1] == Gst::State::PLAYING
            @player.set_state(Gst::State::PAUSED)
            return RESPONSE[204]
          end
          if @filepath != nil and File.exist?(@filepath)
            @player.set_property(
              'uri', 'file://' + URI.escape(@filepath))
            @player.set_state(Gst::State::PLAYING)
          end
        end
      elsif argc == 2
        if argv[0] == 'load'
          @player.set_state(Gst::State::NULL)
          filename = Home.get_normalized_path(argv[1])
          @filepath = File.join(@dir, filename)
        end
      end
      return RESPONSE[204]
    end

    def on_message(bus, message)
      if message == nil # XXX: workaround for Gst Version < 0.11
        return
      end
      t = message.type
      if t == Gst::MessageType::EOS
        @player.set_state(Gst::State::NULL)
        if @loop
          @player.set_state(Gst::State::PLAYING)
        end
      elsif t == Gst::MessageType::ERROR
        @player.set_state(Gst::State::NULL)
        err, debug = message.parse_error()
        logging.error('Error: ' + err.to_s + ', ' + debug.to_s)
        @loop = false
      end
    end
  end
end
