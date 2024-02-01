#
#  Makefile for ninix-aya
#

prefix = /opt/ninix-aya

exec_libdir = $(prefix)/lib

bindir = $(DESTDIR)$(prefix)/bin
docdir = $(DESTDIR)$(prefix)/doc
libdir = $(DESTDIR)$(exec_libdir)
localedir = /usr/local/share/locale

shiori_so_dir = $(DESTDIR)$(prefix)/lib/kawari8:$(DESTDIR)$(prefix)/lib/yaya

ruby = ruby

NINIX = ninix

all:

install: install-lib install-bin install-doc

install-lib:
	mkdir -p $(libdir)
	cp -r lib/* $(libdir)
	mkdir -p $(localedir)/ja/LC_MESSAGES
	(cd po/ja ; msgfmt ninix-aya.po -o $(localedir)/ja/LC_MESSAGES/ninix-aya.mo)

sed_dirs = sed -e "s,@ruby,$(ruby),g" -e "s,@libdir,$(libdir),g" -e "s,@so_path,$(shiori_so_dir),g"

install-bin:
	mkdir -p $(bindir)
	$(sed_dirs) bin/ninix.in         > bin/ninix
	install -m 755 bin/ninix         $(bindir)/$(NINIX)

install-doc:
	mkdir -p $(docdir)
	cp README.md README.ninix SAORI COPYING ChangeLog $(docdir)

clean:
	$(RM) bin/ninix *~
