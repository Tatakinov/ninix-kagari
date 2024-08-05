# -*- coding: utf-8 -*-
#
#  Copyright (C) 2003-2019 by Shyouzou Sugitani <shy@users.osdn.me>
#  Copyright (C) 2024 by Tatakinov
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "narray"
require "digest/md5"
require "gtk3"

require_relative "logging"

module Pix

  def self.surface_to_region(surface)
    region = Cairo::Region.new()
    width = surface.width
    pix_na = NArray.to_na(surface.data, NArray::BYTE)
    pix_na.reshape!(4, pix_na.size / 4)
    curr_y = nil
    start_x = nil
    end_x = nil
    pix_na[3, true].where.each {|i|
      y, x = i.divmod(width)
      unless start_x.nil?
        if y != curr_y or x != (end_x + 1)
          region.union!(start_x, curr_y, end_x - start_x + 1, 1)
          curr_y = y
          start_x = x
        end
      else
        curr_y = y
        start_x = x
      end
      end_x = x
    }
    region.union!(start_x, curr_y, end_x - start_x + 1, 1) unless start_x.nil?
    return region
  end

  def self.surface_to_region_with_hints(surface, device_extents)
    device_x1, device_y1, device_x2, device_y2 = device_extents
    region = Cairo::Region.new()
    width = surface.width
    height = surface.height
    stride = surface.stride
    device_x1 = [0, [device_x1, width - 1].min].max
    device_x2 = [0, [device_x2, width - 1].min].max
    device_y1 = [0, [device_y1, height - 1].min].max
    device_y2 = [0, [device_y2, height - 1].min].max
    device_w = device_x2 - device_x1 + 1
    device_h = device_y2 - device_y1 + 1
    pix_na = NArray.to_na(surface.data[device_y1 * stride, device_h * stride], NArray::BYTE)
    pix_na.reshape!(4, width, device_h)
    pix_na = pix_na.slice(3, device_x1..device_x2, true)
    curr_y = nil
    start_x = nil
    end_x = nil
    pix_na.where.each {|i|
      y, x = i.divmod(device_w)
      unless start_x.nil?
        if y != curr_y or x != (end_x + 1)
          region.union!(start_x, curr_y, end_x - start_x + 1, 1)
          curr_y = y
          start_x = x
        end
      else
        curr_y = y
        start_x = x
      end
      end_x = x
    }
    region.union!(start_x, curr_y, end_x - start_x + 1, 1) unless start_x.nil?
    region.translate!(device_x1, device_y1)
    return region
  end

  class BaseTransparentWindow < Gtk::Window
    alias :base_move :move
    attr_reader :supports_alpha

    def initialize(type: Gtk::WindowType::TOPLEVEL)
      @width, @height = 1, 1
      super(type)
      set_decorated(false)
      #set_resizable(false)
      signal_connect('size-allocate') do |w, alloc, data|
        unless @width == alloc.width and @height == alloc.height
          @width, @height = alloc.width, alloc.height
          # XXX draw中にresizeすると
          # Assertion failed: CAIRO_REFERENCE_COUNT_HAS_REFERENCE (&surface->ref_count)
          # で落ちる(Windowsのみ)が、サイズが変わるタイミングで
          # GCすると*なぜか*落ちなくなる。
          if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
            GC.start
          end
        end
        next false
      end
      signal_connect("screen-changed") do |widget, old_screen|
        screen_changed(widget, :old_screen => old_screen)
        next true
      end
      # set to minimum
      set_size_request(1, 1)
      resize(@width, @height)
      screen_changed(self)
    end

    def screen_changed(widget, old_screen: nil)
      if composited?
        set_visual(screen.rgba_visual)
      else
        set_visual(screen.system_visual)
        Logging::Logging.debug("screen does NOT support alpha.\n")
      end
      @supports_alpha = composited?
      fail "assert" unless not visual.nil?
    end
  end


  class TransparentWindow < BaseTransparentWindow

    attr_accessor :darea

    def initialize
      super()
      set_app_paintable(true)
      set_focus_on_map(false)
      @__surface_position = [0, 0]
      @prev_position = [0, 0]
      # create drawing area
      @darea = Gtk::DrawingArea.new
      @darea.set_size_request(*size) # XXX
      @darea.show()
      add(@darea)
      @region = nil
      @device_extents = nil
      @tmp_surface = nil
    end

    def get_draw_offset
      return @__surface_position
    end

    def winpos_to_surfacepos(x, y, scale)
      surface_x, surface_y = @__surface_position
      new_x = ((x - surface_x) * 100 / scale).to_i
      new_y = ((y - surface_y) * 100 / scale).to_i
      return new_x, new_y
    end

    def set_surface(cr, surface, scale, reshape)
      cr.save()
      # clear
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.set_source_rgba(0, 0, 0, 0)
      cr.paint
      # HACK
      # ウィンドウの透過に非対応な環境ではcr.size <= surface.sizeとなり
      # surface_to_region(cr.target.map_to_image)では
      # 正しいregionが取得出来ないので、surface_to_region(surface)で
      # 正しいregionを取得したい。
      # しかし、set_shapeのreshapeに対応する必要があるため、
      # 仕方なくsurfaceをshapeまで保持する
      s = cr.target.map_to_image
      if (@region.nil? or reshape) and not @supports_alpha and (s.width < surface.width or s.height < surface.height)
        @tmp_surface = surface
      end
      cr.scale(scale / 100.0, scale / 100.0)
      cr.set_source(surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      # copy rectangle on the destination
      cr.rectangle(0, 0, surface.width, surface.height)
      extents = cr.path_extents # cr.fill_extents
      device_x1, device_y1 = cr.user_to_device(
                   extents[0],
                   extents[1])
      device_x2, device_y2 = cr.user_to_device(
                   extents[2],
                   extents[3])
      @device_extents = [device_x1, device_y1, device_x2, device_y2].map {|f| f.to_i}
      cr.fill()
      cr.restore()
      # resize window
      x, y, w, h = @device_extents
      unless @width == w and @height == h
        resize(w, h)
      end
    end

    def set_shape(cr, reshape)
      return if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      if @region.nil? or reshape
        if @tmp_surface.nil?
          if @device_extents.nil?
            @region = Pix.surface_to_region(cr.target.map_to_image)
          else
            @region = Pix.surface_to_region_with_hints(cr.target.map_to_image, @device_extents)
          end
        else
          @region = Pix.surface_to_region(@tmp_surface)
        end
      end
      @prev_position = @__surface_position
      if @supports_alpha
        input_shape_combine_region(nil)
        input_shape_combine_region(@region)
      else
        shape_combine_region(nil)
        shape_combine_region(@region)
      end
    end
  end


  class TransparentApplicationWindow < Gtk::ApplicationWindow

    def initialize(application)
      Gdk.set_program_class('Ninix')
      super(application)
      @size = [0, 0]
      init_size = size
      geometry = display.primary_monitor.geometry
      set_decorated(false)
      set_app_paintable(true)
      set_focus_on_map(false)
      if composited?
        input_shape_combine_region(Cairo::Region.new) # empty region
      end
      signal_connect("screen-changed") do |widget, old_screen|
        screen_changed(widget, :old_screen => old_screen)
        next true
      end
      signal_connect('size-allocate') do |widget, allocation, data|
        @size = size
        if maximized?
          # HACK 最大化しても初期サイズと一緒ならタイル型WMとして扱う。
          # スクリーンサイズはこのwindowではなく別途取得したものを使う。
          if init_size == @size
            @size = [geometry.width, geometry.height]
          end
          hide
        end
        next false
      end
      set_keep_below(true)
      set_skip_pager_hint(true)
      set_skip_taskbar_hint(true)
      screen_changed(self)
    end

    def get_size
      return @size
    end

    def screen_changed(widget, old_screen: nil)
      if composited?
        set_visual(screen.rgba_visual)
      else
        set_visual(screen.system_visual)
        Logging::Logging.debug("screen does NOT support alpha.\n")
      end
      fail "assert" unless not visual.nil?
      maximize # not fullscreen
      show
    end
  end


  def self.get_png_size(path)
    return 0, 0 if not File.exist?(path)
    buf =
      case File.extname(path)
      when '.dgp'
        get_DGP_IHDR(path)
      when '.ddp'
        get_DDP_IHDR(path)
      else
        get_png_IHDR(path)
      end
    fail "assert" unless buf[0] == 137.chr # png format # XXX != "\x89"
    fail "assert" unless buf[1..7] == "PNG\r\n\x1a\n" # png format
    fail "assert" unless buf[12..15] == "IHDR" # name of the first chunk in a PNG datastream
    w = buf[16, 4]
    h = buf[20, 4]
    width = ((w[0].ord << 24) + (w[1].ord << 16) + (w[2].ord << 8) + w[3].ord)
    height = ((h[0].ord << 24) + (h[1].ord << 16) + (h[2].ord << 8) + h[3].ord)
    return width, height
  end

  def self.get_png_lastpix(path)
    return nil if not File.exist?(path)
    pixbuf = pixbuf_new_from_file(path)
    fail "assert" unless [3, 4].include?(pixbuf.n_channels)
    fail "assert" unless pixbuf.bits_per_sample == 8
    '#%02x%02x%02x' % [pixbuf.pixels[-3].ord,
                       pixbuf.pixels[-2].ord,
                       pixbuf.pixels[-1].ord]
  end

  def self.get_DGP_IHDR(path)
    head, tail = File.split(path) # XXX
    filename = tail
    m_half = Digest::MD5.hexdigest(filename[0..filename.length/2-1])
    m_full = Digest::MD5.hexdigest(filename)
    tmp = [m_full, filename].join('')
    key = ''
    j = 0
    for i in 0..tmp.length-1
      value = (tmp[i].ord ^ m_half[j].ord)
      break if value.zero?
      key << value.chr
      j += 1
      j = 0 if j >= m_half.length
    end
    key_length = key.length
    if key_length.zero? # not encrypted
      Logging::Logging.warning([filename, ' generates a null key.'].join(''))
      return get_png_IHDR(path)
    end
    key = [key[1..-1], key[0]].join('')
    key_pos = 0
    buf = ''
    f = File.open(path, 'rb')
    for i in 0..23
      c = f.read(1)
      buf << (c[0].ord ^ key[key_pos].ord).chr
      key_pos += 1
      key_pos = 0 if key_pos >= key_length
    end
    return buf
  end

  def self.get_DDP_IHDR(path)
    size = File.size(path)
    key = (size << 2)
    buf = ""
    f = File.open(path, 'rb')
    for i in 0..23
      c = f.read(1)
      key = ((key * 0x08088405 + 1) & 0xffffffff)
      buf << ((c[0].ord ^ key >> 24) & 0xff).chr
    end
    return buf
  end

  def self.get_png_IHDR(path)
    File.open(path, 'rb') {|f| f.read(24) }
  end

  def self.pixbuf_new_from_file(path)
    GdkPixbuf::Pixbuf.new(:file => path)
  end

  def self.surface_new_from_file(path)
    Cairo::ImageSurface.from_png(path)
  end

  def self.create_icon_pixbuf(path)
    begin
      pixbuf = pixbuf_new_from_file(path)
    rescue # compressed icons are not supported. :-(
      return nil
    end
    pixbuf.scale(16, 16, GdkPixbuf::InterpType::BILINEAR)
  end

  def self.create_blank_surface(width, height)
    Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32, width, height)
  end

  def self.create_pixbuf_from_DGP_file(path)
    head, tail = File.split(path) # XXX
    filename = tail
    m_half = Digest::MD5.hexdigest(filename[0..filename.length/2-1])
    m_full = Digest::MD5.hexdigest(filename)
    tmp = [m_full, filename].join('')
    key = ''
    j = 0
    for i in 0..tmp.length-1
      value = (tmp[i].ord ^ m_half[j].ord)
      break if value.zero?
      key << value.chr
      j += 1
      j = 0 if j >= m_half.length
    end
    key_length = key.length
    if key_length.zero? # not encrypted
      Logging::Logging.warning([filename, ' generates a null key.'].join(''))
      pixbuf = pixbuf_new_from_file(filename)
      return pixbuf
    end
    key = [key[1..-1], key[0]].join('')
    key_pos = 0
    loader = Gdk::PixbufLoader.new('png')
    f = File.open(path, 'rb')
    while true
      c = f.read(1)
      break if c.nil? # EOF
      loader.write((c[0].ord ^ key[key_pos].ord).chr)
      key_pos += 1
      key_pos = 0 if key_pos >= key_length
    end
    pixbuf = loader.pixbuf
    loader.close()
    return pixbuf
  end

  def self.create_pixbuf_from_DDP_file(path)
    f = File.open(path, 'rb')
    buf = f.read()
    key = buf.length << 2
    loader = Gdk::PixbufLoader.new('png')
    for i in 0..buf.length-1
      key = ((key * 0x08088405 + 1) & 0xffffffff)
      loader.write(((buf[i].ord ^ key >> 24) & 0xff).chr)
    end
    pixbuf = loader.pixbuf
    loader.close()
    return pixbuf
  end

  def self.create_surface_from_file(path, is_pnr: true, use_pna: false)
    pixbuf = create_pixbuf_from_file(path, :is_pnr => is_pnr, :use_pna => use_pna)
    surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32,
                                      pixbuf.width, pixbuf.height)
    Cairo::Context.new(surface) do |cr|
      cr.set_source_pixbuf(pixbuf, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint()
    end
    return surface
  end

  def self.create_pixbuf_from_file(path, is_pnr: false, use_pna: false)
    head = File.dirname(path)
    basename = File.basename(path, '.*')
    pixbuf =
      case File.extname(path)
      when '.dgp'
        create_pixbuf_from_DGP_file(path)
      when '.ddp'
        create_pixbuf_from_DDP_file(path)
      else
        pixbuf_new_from_file(path)
      end
    # Currently cannot get a pointer to the actual pixels with
    # the pixels method. Temporary use the read_pixel_bytes method and
    # create another Pixbuf.
    if is_pnr
      pixels = pixbuf.read_pixel_bytes.to_s
      unless pixbuf.has_alpha?
        r, g, b = pixels[0, 3].bytes
        pixbuf = pixbuf.add_alpha(true, r, g, b)
      else
        pix_na = NArray.to_na(pixels, NArray::INT)
        rgba = pix_na[0]
        pix_na[pix_na.eq rgba] = 0
        pixbuf = GdkPixbuf::Pixbuf.new(
          :bytes => pix_na.to_s,
          :has_alpha => true,
          :width => pixbuf.width,
          :height => pixbuf.height,
          :row_stride => pixbuf.rowstride)
      end
    end
    if use_pna
      path = File.join(head, basename + '.pna')
      if File.exist?(path)
        pna_pixbuf = pixbuf_new_from_file(path)
        pix_na = NArray.to_na(pixbuf.read_pixel_bytes.to_s, NArray::BYTE)
        pix_na.reshape!(4, pix_na.size / 4)
        unless pna_pixbuf.has_alpha?
          pna_pixbuf = pna_pixbuf.add_alpha(false, 0, 0, 0)
        end
        pna_na = NArray.to_na(pna_pixbuf.read_pixel_bytes.to_s, NArray::BYTE)
        pna_na.reshape!(4, pna_na.size / 4)
        pix_na[3, true] = pna_na[0, true]
        pixbuf = GdkPixbuf::Pixbuf.new(
          :bytes => pix_na.to_s,
          :has_alpha => true,
          :width => pixbuf.width,
          :height => pixbuf.height,
          :row_stride => pixbuf.rowstride)
      end
    end
    return pixbuf
  end
end
