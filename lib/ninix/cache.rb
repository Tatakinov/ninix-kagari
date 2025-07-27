# -*- coding: utf-8 -*-
#
#  Copyright (C) 2025 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require 'weakref'

module Cache
  class WeakCache < Hash
    def self.finalize(hash, key)
      proc do
        hash.delete(key)
      end
    end

    def []=(key, value)
      ObjectSpace.define_finalizer(value, WeakCache.finalize(self, key))
      super(key, WeakRef.new(value))
    end

    def [](key)
      begin
        return super(key).__getobj__ if include?(key)
      rescue WeakRef::RefError
        # nop
      end
      return nil
    end
  end

  class ImageCache < Hash
    def initialize(...)
      super
      @prev_time = Time.now.to_i
      @info = Hash.new do |h, k|
        h[k] = {count: 0, time: Time.now.to_i}
      end
      @weak = WeakCache.new
    end

    def pop(key)
      time = Time.now.to_i
      # 10秒以内に1回しか使われなかったオブジェクトを
      # WeakCache送りにする
      if time <= @prev_time + 1
        return
      end
      @prev_time = time
      delete_if do |k, v|
        if @info[k][:count] <= 1 and time - @info[k][:time] > 10 and k != key
          @info.delete(k)
          @weak[k] = v
          next true
        else
          @info[k][:count] = 0
          @info[k][:time] = time
          next false
        end
      end
    end

    def []=(key, value)
      pop(key)
      @info[key][:count] += 1
      return super
    end

    def [](key)
      pop(key)
      @info[key][:count] += 1
      return super if include?(key)
      return @weak[key]
    end
  end
end
