# -*- coding: utf-8 -*-
#
#  Copyright (C) 2003-2014 by Shyouzou Sugitani <shy@users.sourceforge.jp>
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License (version 2) as
#  published by the Free Software Foundation.  It is distributed in the
#  hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
#  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#  PURPOSE.  See the GNU General Public License for more details.
#

require "gtk3"

module Pix

  class BaseTransparentWindow < Gtk::Window

    def initialize(type=Gtk::Window::Type::TOPLEVEL)
      super(type)
      set_decorated(false)
#      set_resizable(false)
      screen_changed()
    end

    def screen_changed(old_screen=nil)
      if composited?
        set_visual(screen.rgba_visual)
        @supports_alpha = true
      else
        set_visual(screen.system_visual)
        #logging.debug('screen does NOT support alpha.\n')
        @supports_alpha = false
      end
      #assert visual is not None
    end
  end


  class TransparentWindow < BaseTransparentWindow

    attr_accessor :darea

    def initialize
      super()
      set_app_paintable(true)
      set_focus_on_map(false)
      @__position = [0, 0]
      @__surface_position = [0, 0]
      @__redraw = nil
#      connect_after('size_allocate', size_allocate)
      # create drawing area
      @darea = Gtk::DrawingArea.new
      @darea.show()
#      @darea.connect = wrap_connect
      add(@darea)
      override_background_color(Gtk::StateFlags::NORMAL,
                                Gdk::RGBA.new(0, 0, 0, 0))
    end

#    def wrap_connect(self, signal, user_function, user_data=None):
#        if signal == 'draw':
#            self.__redraw = (user_function, user_data)
#            Gtk.DrawingArea.connect(self.darea, signal, self.wrap_draw)
#        else:
#            if user_data is not None:
#                Gtk.DrawingArea.connect(
#                    self.darea, signal, user_function, user_data)
#            else:
#                Gtk.DrawingArea.connect(
#                    self.darea, signal, user_function)

#    def wrap_draw(self, darea, cr):
#        if self.__redraw is None:
#            return
#        cr.translate(*self.get_draw_offset())
#        user_function, user_data = self.__redraw
#        if user_data is not None:
#            user_function(darea, cr, user_data)
#        else:
#            user_function(darea, cr)
#        ##region = Gdk.cairo_region_create_from_surface(cr.get_target())
#        ##self.input_shape_combine_region(region)
#        _gtkhack.gtkwindow_set_input_shape(self, cr.get_target())

    def update_size(w, h)
#        self.get_child().set_size_request(w, h) # XXX
#        self.queue_resize()
      @darea.set_size_request(w, h) # XXX
      queue_resize()
    end

#    def size_allocate(self, widget, event):
#        new_x, new_y = self.__position
#        Gtk.Window.move(self, new_x, new_y)

    def move(x, y)
#        left, top, scrn_w, scrn_h = get_workarea()
#        w, h = self.get_child().get_size_request() # XXX
#        new_x = min(max(left, x), scrn_w - w)
#        new_y = min(max(top, y), scrn_h - h)
#        Gtk.Window.move(self, new_x, new_y)
#        self.__position = (new_x, new_y)
#        self.__surface_position = (x, y)
#        self.darea.queue_draw()
    end

#    def get_draw_offset(self):
#        window_x, window_y = self.__position
#        surface_x, surface_y = self.__surface_position
#        return surface_x - window_x, surface_y - window_y

#    def winpos_to_surfacepos(self, x, y, scale):
#        window_x, window_y = self.__position
#        surface_x, surface_y = self.__surface_position
#        new_x = int((x - (surface_x - window_x)) * 100 / scale)
#        new_y = int((y - (surface_y - window_y)) * 100 / scale)
#        return new_x, new_y

  end


  def self.get_png_size(path)
    if not File.exists?(path)
      return 0, 0
    end
    fp = File.open(path)
    base = File.basename(path, '.*')
    ext = File.extname(path)
    if ext == '.dgp'
      buf = get_DGP_IHDR(path)
    elsif ext == '.ddp'
      buf = get_DDP_IHDR(path)
    else
      buf = get_png_IHDR(path)
    end
#    assert buf[0:8] == b'\x89PNG\r\n\x1a\n' # png format
#    assert buf[12:16] == b'IHDR' # name of the first chunk in a PNG datastream
    w = buf[16, 4]
    h = buf[20, 4]
    width = (w[0].ord << 24) + (w[1].ord << 16) + (w[2].ord << 8) + w[3].ord
    height = (h[0].ord << 24) + (h[1].ord << 16) + (h[2].ord << 8) + h[3].ord
    return width, height
  end

  def self.get_png_lastpix(path)
    if not File.exists?(path)
      return nil
    end
    pixbuf = pixbuf_new_from_file(path)
    #assert pixbuf.get_n_channels() in [3, 4]
    #assert pixbuf.get_bits_per_sample() == 8
    color = '#%02x%02x%02x' % [pixbuf.pixels[-3].ord,
                               pixbuf.pixels[-2].ord,
                               pixbuf.pixels[-1].ord]
    return color
  end

  def self.get_DGP_IHDR(path)
#    head, tail = os.path.split(os.fsdecode(path)) # XXX
#    filename = tail
#    m_half = hashlib.md5(filename[:len(filename) // 2]).hexdigest()
#    m_full = hashlib.md5(filename).hexdigest()
#    tmp = ''.join((m_full, filename))
#    key = ''
#    j = 0
#    for i in range(len(tmp)):
#        value = ord(tmp[i]) ^ ord(m_half[j])
#        if not value:
#            break
#        key = ''.join((key, chr(value)))
#        j += 1
#        if j >= len(m_half):
#            j = 0
#    key_length = len(key)
#    if key_length == 0: # not encrypted
#        logging.warning(''.join((filename, ' generates a null key.')))
#        return get_png_IHDR(path)
#    key = ''.join((key[1:], key[0]))
#    key_pos = 0
#    buf = b''
#    with open(path, 'rb') as f:
#        for i in range(24):
#            c = f.read(1)
#            buf = b''.join(
#                (buf, int.to_bytes(c[0] ^ ord(key[key_pos]), 1, 'little')))
#            key_pos += 1
#            if key_pos >= key_length:
#                key_pos = 0
#    return buf
  end

  def self.get_DDP_IHDR(path)
#    size = os.path.getsize(path)
#    key = size << 2    
#    buf = b''
#    with open(path, 'rb') as f:
#        for i in range(24):
#            c = f.read(1)
#            key = (key * 0x08088405 + 1) & 0xffffffff
#            buf = b''.join(
#                (buf, int.to_bytes((c[0] ^ key >> 24) & 0xff, 1, 'little')))
#    return buf
  end

  def self.get_png_IHDR(path)
    f = File.open(path, 'rb')
    buf = f.read(24)
    return buf
  end

  def self.pixbuf_new_from_file(path)
    return Gdk::Pixbuf.new(path)
  end

  def self.surface_new_from_file(path)
    return Cairo::ImageSurface.new(path)
 end

  def self.create_icon_pixbuf(path)
#    path = os.fsdecode(path) # XXX
#    try:
#        pixbuf = __pixbuf_new_from_file(path)
#    except: # compressed icons are not supported. :-(
#        pixbuf = None
#    else:
#        pixbuf = pixbuf.scale_simple(16, 16, GdkPixbuf.InterpType.BILINEAR)
#    return pixbuf
  end

  def self.create_blank_surface(width, height)
    surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32, width, height)
    return surface
  end

  def self.create_pixbuf_from_DGP_file(path)
    head = File.dirname(path)
#    head, tail = os.path.split(os.fsdeocde(path)) # XXX
#    filename = tail
#    m_half = hashlib.md5(filename[:len(filename) // 2]).hexdigest()
#    m_full = hashlib.md5(filename).hexdigest()
#    tmp = ''.join((m_full, filename))
#    key = ''
#    j = 0
#    for i in range(len(tmp)):
#        value = ord(tmp[i]) ^ ord(m_half[j])
#        if not value:
#            break
#        key = ''.join((key, chr(value)))
#        j += 1
#        if j >= len(m_half):
#            j = 0
#    key_length = len(key)
#    if key_length == 0: # not encrypted
#        logging.warning(''.join((filename, ' generates a null key.')))
#        pixbuf = __pixbuf_new_from_file(filename)
#        return pixbuf
#    key = ''.join((key[1:], key[0]))
#    key_pos = 0
#    loader = GdkPixbuf.PixbufLoader.new_with_type('png')
#    with open(path, 'rb') as f:
#        while 1:
#            c = f.read(1)
#            if c == b'':
#                break
#            loader.write(int.to_bytes(c[0] ^ ord(key[key_pos]), 1, 'little'))
#            key_pos += 1
#            if key_pos >= key_length:
#                key_pos = 0
#    pixbuf = loader.get_pixbuf()
#    loader.close()
#    return pixbuf
  end

  def self.create_pixbuf_from_DDP_file(path)
#    with open(path, 'rb') as f:
#        buf = f.read()
#    key = len(buf) << 2
#    loader = GdkPixbuf.PixbufLoader.new_with_type('png')
#    for i in range(len(buf)):
#        key = (key * 0x08088405 + 1) & 0xffffffff
#        loader.write(int.to_bytes((buf[i] ^ key >> 24) & 0xff, 1, 'little'))
#    pixbuf = loader.get_pixbuf()
#    loader.close()
#    return pixbuf
  end

  def self.create_surface_from_file(path, is_pnr=true, use_pna=false)
    head = File.dirname(path)
    basename = File.basename(path, '.*')
    ext = File.extname(path)
    pixbuf = create_pixbuf_from_file(path, is_pnr, use_pna)
    surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32,
                                      pixbuf.width, pixbuf.height)
    cr = Cairo::Context.new(surface)
    cr.set_source_pixbuf(pixbuf, 0, 0)
    cr.set_operator(Cairo::OPERATOR_SOURCE)
    cr.paint()
    return surface
  end

  def self.create_pixbuf_from_file(path, is_pnr=true, use_pna=false)
    head = File.dirname(path)
    basename = File.basename(path, '.*')
    ext = File.extname(path)
    if ext == '.dgp'
      pixbuf = create_pixbuf_from_DGP_file(path)
    elsif ext == '.ddp'
      pixbuf = create_pixbuf_from_DDP_file(path)
    else
      pixbuf = pixbuf_new_from_file(path)
    end
    if is_pnr
      pixels = pixbuf.pixels
      if not pixbuf.has_alpha?
        r = pixels[0].ord
        g = pixels[1].ord
        b = pixels[2].ord
        pixbuf = pixbuf.add_alpha(true, r, g, b)
      else
        rgba = pixels[0, 4]
        for x in 0..(pixels.size / 4 - 1)
          if pixels[x * 4, 4] == rgba
            pixels[x * 4, 4] = rgba
          end
        end
      end
    end
    if use_pna
      path = File.join(head, basename + '.pna')
      if File.exists?(path)
        pna_pixbuf = pixbuf_new_from_file(path)
        pixels = pixbuf.pixels
        if not pna_pixbuf.has_alpha?
          pna_pixbuf = pna_pixbuf.add_alpha(false, 0, 0, 0)
        end
        pna_pixels = pna_pixbuf.pixels
        for x in 0..(pixels.size / 4 - 1)
          pixels[x * 4 + 3] = pna_pixels[x * 4]
        end
        pixbuf.pixels = pixels
      end
    end
    return pixbuf
  end

  def self.get_workarea()
    scrn = Gdk::Screen.default
    root = scrn.root_window
    left, top, width, height = root.geometry
    return left, top, width, height
  end

  class TEST

    def initialize(path)
      @win = Pix::TransparentWindow.new
      @win.signal_connect('destroy') do
        Gtk.main_quit
      end
      @win.darea.signal_connect('draw') do |w, cr|
        expose_cb(w, cr)
      end
      @surface = Pix.create_surface_from_file(path, true, true)
      @win.set_default_size(@surface.width, @surface.height)
      @win.show_all
      Gtk.main
    end

    def expose_cb(widget, cr)
      cr.set_source(@surface, 0, 0)
      cr.set_operator(Cairo::OPERATOR_SOURCE)
      cr.paint
      region = Cairo::Region.new()
      data = @surface.data
      for i in 0..(data.size / 4 - 1)
        if (data[i * 4 + 3].ord) != 0
          x = i % @surface.width
          y = i / @surface.width
          region.union!(x, y, 1, 1)
        end
      end
      @win.input_shape_combine_region(region)
    end
  end
end


$:.unshift(File.dirname(__FILE__))

Pix::TEST.new(ARGV.shift)
