# What is this

デスクトップマスコットの1つ、伺かの互換アプリケーションです。

[ninix-aya](https://ja.osdn.net/projects/ninix-aya/)
が長らく更新されていないので
私の環境(Debian stable)でいい感じに動作するようにしたものになります。

ついでにninix-aya自体もosdn.netの存続が怪しいのでその保存の意味もあります。
v0.0.0がninix-aya 5.0.9に対応しているので
必要であればそちらを参照してください。

# Requirements

- ruby

- ruby-gettext

- ruby-gio2

- ruby-gstreamer

- ruby-gtk3

- ruby-narray

- ruby-zip

が最低限必要なものになります。

- ruby-charlock-holmes

が一部SHIORIで使われているようなので必要であればinstallしてください。

なお、ninix-ayaと必要なものは一緒なので

```
apt install ninix-aya
```

みたいにすれば楽できます。

# Install

```
make install
```

で/opt/ninix-kagari以下に必要なファイルがインストールされます。
インストール先を変える場合はMakefileのprefixをいじってください。

インストール後はパスを通す必要があります。

```
PATH=/opt/ninix-kagari/bin:$PATH
```

実行ファイル名はninixです。

```
$ ninix
```

# Library

KAWARI(華和梨)は`/opt/ninix-kagari/lib/kawari8/libshiori.so`、
YAYAは`/opt/ninix-kagari/lib/yaya/libaya5.so`が必要です。

KAWARIは[kawari](https://github.com/kawari/kawari)に
[このパッチ](https://gist.github.com/Tatakinov/701bf6ec0487da3e127981c50921b835)を当てたものを、
YAYAは[yaya-shioriのfork](https://github.com/Tatakinov/yaya-shiori)の
feature-posix-supportブランチを
それぞれコンパイルしてください。

そして、出来上がったものを上記の場所にコピーしてから、
ninix-kagariを起動してください。

# Caution

エンバグ・デグレーション上等で作っているので、必ずしも最新版が
一番良いとは限りません。

# License

Copyright (C) 2001, 2002 by Tamito KAJIYAMA

Copyright (C) 2002-2007 by MATSUMURA Namihiko

Copyright (C) 2002-2019 by Shyouzou Sugitani

Copyright (C) 2002, 2003 by ABE Hideaki

Copyright (C) 2003-2005 by Shun-ichi TAHARA

Copyright (C) 2024 by Tatakinov

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License (version 2) as
published by the Free Software Foundation.  It is distributed in the
hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more details.

