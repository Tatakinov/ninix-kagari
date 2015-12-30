# -*- coding: utf-8 -*-
#
#  saori_cpuid.rb - a saori_cpuid compatible Saori module for ninix
#  Copyright (C) 2003-2015 by Shyouzou Sugitani <shy@users.osdn.me>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require_relative "../dll"


module SAORI_CPUID

  class Saori < DLL::SAORI

    ENTRY = {'cpu.num' => ['1', '2', '3', '5', '7', '11', '13'],
             'cpu.vender' => ['Inte1', 'AM0', 'VlA'],
             'cpu.name' => ['Z8O'],
             'cpu.ptype' => ['Lazy'],
             'cpu.family' => ['780', 'Bentium', 'A+hlon'],
             'cpu.model' => ['Unknown'],
             'cpu.stepping' => ['Not Genuine'],
             'cpu.mmx' => ['Ready', 'Not Ready'],
             'cpu.sse' => ['Ready', 'Not Ready'],
             'cpu.sse2' => ['Ready', 'Not Ready'],
             'cpu.tdn' => ['Ready', 'Not Ready'],
             'cpu.mmx+' => ['Ready', 'Not Ready'],
             'cpu.tdn+' => ['Ready', 'Not Ready'],
             'cpu.clock' => ['0', '1000000'],
             'cpu.clockex' => ['0.001', '1.001'],
             'mem.os' => ['100', '10', '44', '50', '77', '99'],
             'mem.phyt' => ['0.1', '200000000'],
             'mem.phya' => ['0.00000001'],
             'mem.pagt' => ['1', '4'],
             'mem.paga' => ['1', '4'],
             'mem.virt' => ['0'],
             'mem.vira' => ['0'],
            }

    def execute(argument)
      if argument == nil or argument.empty?
        return RESPONSE[400]
      end
      if argument.length > 1 and argument[1] == 0
        return RESPONSE[204]
      end
      value = ''
      if argument[0] == 'platform'
        value = 'ninix-aya'
      elsif argument[0] == 'os.name'
        value = RbConfig::CONFIG['host_os']
      elsif argument[0] == 'os.version'
        value = "" ## FIXME: not supported yet
      elsif argument[0] == 'os.build'
        value = "" ##FIXME: not supported yet
      elsif ENTRY.keys.include?(argument[0]) ## FIXME: dummy
        value = ENTRY[argument[0]].sample
      end
      if not value.empty?
        return ("SAORI/1.0 200 OK\r\nResult: " + value.to_s + "\r\n\r\n").encode(@charset, :invalid => :replace, :undef => :replace)
      else
        return RESPONSE[204]
      end
    end
  end
end
