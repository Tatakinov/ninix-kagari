# -*- coding: utf-8 -*-
#
#  dll.rb - a pseudo DLL (SHIORI/SAORI API support) module for ninix
#  Copyright (C) 2002-2016 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require_relative "logging"

module DLL

  def self.get_path() # XXX
    File.expand_path(File.join(File.dirname(__FILE__), 'dll'))
  end


  class SAORI

    RESPONSE = {
      204 => "SAORI/1.0 204 No Content\r\n\r\n",
      400 => "SAORI/1.0 400 Bad Request\r\n\r\n",
      500 => "SAORI/1.0 500 Internal Server Error\r\n\r\n",
    }

    def initialize
      @loaded = 0
    end

    def check_import
      1
    end

    def load(dir: nil)
      dir = File.expand_path(File.dirname(__FILE__)) if dir.nil?
      @dir = dir
      result = 0
      if check_import.zero?
        #pass
      elsif not @loaded.zero?
        result = 2
      else
        unless setup.zero?
          @loaded = 1
          result = 1
        end
      end
      return result
    end

    def setup
      1
    end

    def unload
      return 0 if @loaded.zero?
      @loaded = 0
      return finalize()
    end

    def finalize
      1
    end

    def request(req)
      req_type, argument = evaluate_request(req)
      case req_type
      when nil
        return RESPONSE[400]
      when 'GET Version'
        return RESPONSE[204]
      when 'EXECUTE'
        result = execute(argument)
        return RESPONSE[204] if result.nil?
        return result
      else
        return RESPONSE[400]
      end
    end

    def execute(args)
      nil
    end

    def evaluate_request(req)
      req_type = nil
      argument = []
      @charset = 'CP932' # default
      for line in req.split("\n", 0)
        line = line.force_encoding(@charset).strip.encode("UTF-8", :invalid => :replace, :undef => :replace)
        next if line.empty?
        if req_type.nil?
          for request in ['EXECUTE', 'GET Version']
            if line.start_with?(request)
              req_type = request
            end
          end
          next
        end
        next if line.index(':').nil?
        key, value = line.split(':', 2)
        key = key.strip()
        if key == 'Charset'
          charset = value.strip()
          if not Encoding.name_list.include?(charset)
            Logging::Logging.warning('DLL: Unsupported charset ' + charset)
          end
          @charset = charset
        end
        if key.start_with?('Argument')
          argument << value.strip
        else
          next
        end
      end
      return req_type, argument
    end
  end


  class Library

    def initialize(dll_type, sakura: nil, saori_lib: nil)
      @type = dll_type
      @sakura = sakura
      @saori_lib = saori_lib
    end

    def request(name)
      if @type == 'shiori'
        dll_name, name = name
        if name.empty? and not dll_name.empty?
          name = dll_name
        end
      end
      name = name.gsub('\\', '/')
      head, tail = File.split(name)
      name = tail
      return nil if name.nil? or name.empty?
      if name.downcase.end_with?('.dll') # XXX
        name = name[0, name.length - 4]
      end
      path = File.join(DLL::get_path, name.downcase).concat('.rb') # XXX
      if File.exist?(path)
        require(path)
        begin
          module_ = Module.module_eval(name[0].upcase + name.downcase[1..name.length-1])
        rescue #if not module_
          return nil
        end
      else
        return nil
      end
      instance = nil
      case @type
      when 'saori'
        begin
          saori_ = module_.class_eval('Saori')
          saori = saori_.new()
          if saori_.method_defined?('need_ghost_backdoor')
            saori.need_ghost_backdoor(@sakura)
          end
        rescue
          saori = nil
        end
        instance = saori
      when 'shiori'
        begin
          shiori_ = module_.class_eval('Shiori')
          shiori = shiori_.new(dll_name)
          if shiori_.method_defined?('use_saori')
            shiori.use_saori(@saori_lib)
          end
        rescue
          shiori = nil
        end
        instance = shiori
      end
      return instance
    end

    def __import_module(name)
      path = get_path()
      loader = importlib.find_loader(name, [path])
      begin
        return loader.load_module(name)
      rescue
        return nil
      end
    end
  end
end
