#!/bin/sh

# mkdir -p pot

rxgettext lib/ninix_main.rb -o pot/ninix_main.pot
rxgettext lib/ninix/alias.rb  -o pot/alias.pot
rxgettext lib/ninix/balloon.rb  -o pot/balloon.pot
rxgettext lib/ninix/communicate.rb  -o pot/communicate.pot
rxgettext lib/ninix/config.rb  -o pot/config.pot
rxgettext lib/ninix/dll.rb  -o pot/dll.pot
rxgettext lib/ninix/entry_db.rb  -o pot/entry_db.pot
rxgettext lib/ninix/home.rb  -o pot/home.pot
rxgettext lib/ninix/install.rb  -o pot/install.pot
rxgettext lib/ninix/keymap.rb  -o pot/keymap.pot
rxgettext lib/ninix/kinoko.rb  -o pot/kinoko.pot
rxgettext lib/ninix/lock.rb  -o pot/lock.pot
rxgettext lib/ninix/logging.rb  -o pot/logging.pot
rxgettext lib/ninix/makoto.rb  -o pot/makoto.pot
rxgettext lib/ninix/menu.rb  -o pot/menu.pot
rxgettext lib/ninix/metamagic.rb  -o pot/metamagic.pot
rxgettext lib/ninix/nekodorif.rb  -o pot/nekodorif.pot
rxgettext lib/ninix/ngm.rb  -o pot/ngm.pot
rxgettext lib/ninix/pix.rb  -o pot/pix.pot
rxgettext lib/ninix/prefs.rb  -o pot/prefs.pot
rxgettext lib/ninix/sakura.rb  -o pot/sakura.pot
rxgettext lib/ninix/script.rb  -o pot/script.pot
rxgettext lib/ninix/seriko.rb  -o pot/seriko.pot
rxgettext lib/ninix/sstp.rb  -o pot/sstp.pot
rxgettext lib/ninix/sstplib.rb  -o pot/sstplib.pot
rxgettext lib/ninix/surface.rb  -o pot/surface.pot
rxgettext lib/ninix/update.rb  -o pot/update.pot
rxgettext lib/ninix/version.rb  -o pot/version.pot

rmsgcat pot/*.pot -o ninix-aya.pot

# cp ninix-aya.pot po/ja/ninix-aya.po and edit ninix-aya.pot

# msgfmt po/ja/ninix-aya.po -o locale/ja/LC_MESSAGES/ninix-aya.mo

# msgunfmt -o po/ja/ninix-aya.po locale/ja/LC_MESSAGES/ninix-aya.mo
