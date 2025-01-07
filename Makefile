#
#  Makefile for ninix-kagari
#

prefix = /opt/ninix-kagari

exec_libdir = $(prefix)/lib

bindir = $(DESTDIR)$(prefix)/bin
docdir = $(DESTDIR)$(prefix)/doc
libdir = $(DESTDIR)$(exec_libdir)
localedir = /usr/local/share/locale

saori_so_dir = $(DESTDIR)$(prefix)/lib/saori
shiori_so_dir = $(DESTDIR)$(prefix)/lib/kawari8:$(DESTDIR)$(prefix)/lib/yaya:$(DESTDIR)$(prefix)/lib/kagari:$(DESTDIR)$(prefix)/lib/aosora

ruby = ruby

NINIX = ninix

all:

install: install-lib install-bin install-doc

install-lib:
	mkdir -p $(libdir)
	cp -r lib/* $(libdir)
	mkdir -p $(localedir)/ja/LC_MESSAGES
	(cd po/ja ; msgfmt ninix-kagari.po -o $(localedir)/ja/LC_MESSAGES/ninix-kagari.mo)

sed_dirs = sed -e "s,@ruby,$(ruby),g" -e "s,@libdir,$(libdir),g" -e "s,@so_path,$(shiori_so_dir),g" -e "s,@saori_path,$(saori_so_dir),g"

install-bin:
	mkdir -p $(bindir)
	$(sed_dirs) bin/ninix.in         > bin/ninix
	install -m 755 bin/ninix         $(bindir)/$(NINIX)

install-doc:
	mkdir -p $(docdir)
	cp README.md README.ninix README.ninix-aya README.ninix-aya.en SAORI COPYING ChangeLog.ninix-aya $(docdir)

clean:
	$(RM) bin/ninix *~
