# -*- coding: utf-8 -*-
#
#  dll.rb - a pseudo DLL (SHIORI/SAORI API support) module for ninix
#  Copyright (C) 2002-2015 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#  Copyright (C) 2002, 2003 by MATSUMURA Namihiko <nie@counterghost.net>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

module DLL

  def self.get_path() # XXX
    return File.expand_path(File.join(File.dirname(__FILE__), 'dll'))
  end


  class SAORI

    RESPONSE = {
      204 => 'SAORI/1.0 204 No Content\r\n\r\n',
      400 => 'SAORI/1.0 400 Bad Request\r\n\r\n',
      500 => 'SAORI/1.0 500 Internal Server Error\r\n\r\n',
    }

    def initialize
      @loaded = 0
    end

    def check_import
      return 1
    end

    def load(dir: nil)
      if dir == nil
        dir = File.expand_path(File.dirname(__FILE__))
      end
      @dir = dir
      result = 0
      if check_import != 0
        #pass
      elsif @loaded != 0
        result = 2
      else
        if setup() != 0
          @loaded = 1
          result = 1
        end
      end
      return result
    end

    def setup
      return 1
    end

    def unload
      if @loaded == 0
        return 0
      else
        @loaded = 0
        return finalize()
      end
    end

    def finalize
      return 1
    end

    def request(req)
      req_type, argument = evaluate_request(req)
      if not req_type
        return RESPONSE[400]
      elsif req_type == 'GET Version'
        return RESPONSE[204]
      elsif req_type == 'EXECUTE'
        result = execute(argument)
        if result == nil
          return RESPONSE[204]
        else
          return result
        end
      else
        return RESPONSE[400]
      end
    end

    def execute(args)
      return nil
    end

    def evaluate_request(req)
      req_type = nil
      argument = []
      @charset = 'CP932' # default
      for line in req.split("\n")
        line = line.force_encoding(@charset).strip.encode("UTF-8", :invalid => :replace)
        if line.empty?
          next
        end
        if req_type == nil
          for request in ['EXECUTE', 'GET Version'] ## FIXME
            if line.start_with?(request)
              req_type = request
            end
          end
          next
        end
        if line.index(':') == nil
          next
        end
        key, value = line.split(':', 2)
        key = key.strip()
        if key == 'Charset'
          charset = value.strip()
          if not Encoding.name_list.include?(charset) ##FIXME
            #logging.warning('DLL: Unsupported charset {0}'.format(repr(charset)))
          end
          @charset = charset
        end
        if key.start_with?('Argument') ## FIXME
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
      if not name or name.empty?
        return nil
      end
      if name.downcase.end_with?('.dll') # XXX
        name = name[0, name.length - 4]
      end
      path = File.join(DLL::get_path, name.downcase).concat('.rb') # XXX
      if File.exist?(path)
        require(path)
        begin
          module_ = Module.module_eval(name[0].upcase + name.downcase[1, name.length])
        rescue #if not module_
          return nil
        end
      else
        return nil
      end
      instance = nil
      if @type == 'saori'
        begin
          saori_ = module_.class_eval('Saori')
          saori = saori_.new()
          if saori_.method_defined?('need_ghost_backdoor')
            saori.need_ghost_backdoor(@sakura)
          else
            saori = nil
          end
        rescue
          saori = nil
        end
        instance = saori
      elsif @type == 'shiori'
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
      if instance == nil
        #del module_
        ## this is NOT proper: infects the working ghost(s).
        ##del sys.modules[name]
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
