# What is this

デスクトップマスコットの1つ、伺かの互換アプリケーションです。

[ninix-aya](https://ja.osdn.net/projects/ninix-aya/)
が長らく更新されていないので
私の環境(Debian stable)でいい感じに動作するようにしたものになります。

ついでにninix-aya自体もosdn.netの存続が怪しいのでその保存の意味もあります。
v0.0.0がninix-aya 5.0.9に対応しているので
必要であればそちらを参照してください。

# Requirements

- Linux or Windows

- ruby

- ruby-gettext

- ruby-gio2

- ruby-gtk3

- ruby-narray

- ruby-zip

が最低限必要なものになります。

- ruby-charlock-holmes

が一部SHIORIで使われているようなので必要であればinstallしてください。

- ruby-gstreamer

は音声を再生する場合に必要になります。ただし、現状Windowsでは動作しません。

なお、ninix-ayaと必要なものは一緒なのでパッケージ管理システムが使える場合は

```
apt install ninix-aya
```

みたいにすれば楽できます。

# Install

## Linux

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

## Windows

### Releasesのninix-kagari.zipを利用する場合

zipを展開してrun.batを実行すればOKです。

### 自分でruby環境を用意する場合

rubyinstallerのRuby+Devkitの*x86*をインストールしてください。
x64でも動くと思いますが、動作するゴーストが減ります。

Start Command Prompt with Rubyをメニューから実行して、
Requirementsに書かれているものをインストールします。
以下は最小構成の場合。

```
> gem install gettext gio2 gtk3 narray zip
```

適当な場所にninix-kagariをgit cloneします。

```
> git clone https://github.com/Tatakinov/ninix-kagari
```

実行します。

```
> cd ninix-kagari
> ruby lib/ninix_main.rb
```

# BUG

最新版(v1.1.0)時点でnarのインストールが出来ないようなので、
`C:/Users/*UserName*/.ninix`フォルダ内に
`ghost`、`balloon`フォルダを作って、その中にそれぞれゴーストとバルーンを
入れてください。

```
.ninix
    |- balloon
        |- balloon1
        |- balloon2
        |- ...
    |- ghost
        |- ghost1
        |- ghost2
        |- ...
    |- ngm
```

# Library

## Linux

KAWARI(華和梨)は`/opt/ninix-kagari/lib/kawari8/libshiori.so`、
YAYAは`/opt/ninix-kagari/lib/yaya/libaya5.so`が必要です。

KAWARIは[kawari](https://github.com/kawari/kawari)に
[このパッチ](https://gist.github.com/Tatakinov/701bf6ec0487da3e127981c50921b835)を当てたものを、
YAYAは[yaya-shioriのfork](https://github.com/Tatakinov/yaya-shiori)の
feature/improve\_posix\_supportブランチを
それぞれコンパイルしてください。

そして、出来上がったものを上記の場所にコピーしてから、
ninix-kagariを起動してください。

## Windows

### 32bit OS or ruby(32bit)

ゴースト内蔵のSHIORIを使うため、特に何もする必要はありません。

### ruby(64bit)

現状ではKAWARIとYAYAを使ったゴーストは動作しないと思います。(未確認)

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

