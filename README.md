# ninix-kagari

## What is this

ninix-kagariはデスクトップマスコットの1つ、伺かの互換アプリケーションです。

[ninix-aya](https://ja.osdn.net/projects/ninix-aya/)
が長らく更新されていないので
私の環境(Debian stable)でいい感じに動作するようにしたものになります。

ついでにninix-aya自体もosdn.netの存続が怪しいのでその保存の意味もあります。
v0.0.0がninix-aya 5.0.9に対応しているので
必要であればそちらを参照してください。

## Notice

Installの節を実行してninix-kagariを起動するだけではゴーストは現れません。

*GhostとBalloonを少なくとも1つずつ*インストールする必要があります。

## Supported OS

- Linux

- Windows[^1]

- BSD

[^1]: Windows10より前のバージョンでは[設定が必要](#UNIXソケットの使用)

## Requirements

- ruby

- ruby-gettext

- ruby-gio2

- ruby-gtk3

- ruby-narray

- ruby-zip (rubyzip)

- ninix-fmo

が最低限必要なものになります。
[ninix-fmo](https://github.com/Tatakinov/ninix-fmo)は
リンク先からインストールする必要があります。

- ruby-charlock-holmes

が一部SHIORIで使われているようなので必要であればinstallしてください。

- ruby-gstreamer

は音声を再生する場合に必要になります。ただし、現状Windowsでは動作しません。

## Install

### Linux

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

#### In Tiling Window Manager

タイル型WMではウィンドウをfloatingにするための設定が必要です。
例えばi3では`~/.config/i3/config`に次のような設定を記述します。
```
for_window [class="Ninix"] floating enable
```

### Windows

#### Releasesのninix-kagari.zipを利用する場合

zipを展開して`run.bat`を実行すればOKです。

Windows10より前のバージョンを使っている方は`run_lower_version_10.bat`を
実行してください。

#### 自分でruby環境を用意する場合

rubyinstallerのRuby+Devkitの*x86*をインストールしてください。
x64でも動くと思いますが、動作するゴーストが減ります。

Start Command Prompt with Rubyをメニューから実行して、
Requirementsに書かれているものをインストールします。
以下は最小構成の場合。

```
> gem install gettext gio2 gtk3 narray rubyzip rake rake-compiler
> git clone https://github.com/Tatakinov/ninix-fmo
> cd ninix-fmo
> rake install
> cd ..
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

## Option

### インストールフォルダの変更(v1.4.0以降)

環境変数`NINIX_HOME`を設定することで、
ゴーストやバルーン等をインストールするフォルダを変更することができます。

なお、Releaseのninix-kagari.zipではデフォルトで
`【run.batのあるフォルダ】/.ninix`に
それらを保存しています。

### UNIXソケットの使用

環境変数`NINIX_DISABLE_UNIX_SOCKET`を設定することで、
UNIXソケットを使わないようになり、
Windows版は10より前のバージョンでも動くようになります。

ただし、Direct SSTPは*使用出来なくなります*。

## Library

### Linux

KAWARI(華和梨)は`/opt/ninix-kagari/lib/kawari8/libshiori.so`、
YAYAは`/opt/ninix-kagari/lib/yaya/libaya5.so`が必要です。
(デフォルトのインストール先の場合)

KAWARIは[kawariのfork](https://github.com/Tatakinov/kawari)の
`develop`ブランチを、
YAYAは[yaya-shioriのfork](https://github.com/Tatakinov/yaya-shiori)の
`feature/improve_posix_support`ブランチを
それぞれコンパイルしてください。

そして、出来上がったものを上記の場所にコピーしてから、
ninix-kagariを起動してください。

なお、YAYAで`Shift_JIS`な辞書を読み込みたい場合は
`ja_JP.SJIS`ロケールをインストールする必要があります。

#### SAORI

ninix-kagariで使用できるSAORIは現状[ninix-saori](https://github.com/Tatakinov/ninix-saori)のみです。
詳しい説明は上記URLから。

### Windows

#### 32bit OS or ruby(32bit)

ゴースト内蔵のSHIORIを使うため、特に何もする必要はありません。

#### ruby(64bit)

現状ではKAWARIとYAYAを使ったゴーストは動作しないと思います。(未確認)

## Caution

エンバグ・デグレーション上等で作っているので、必ずしも最新版が
一番良いとは限りません。

## SSP

[SSP](https://ssp.shillest.net/)と比べてninix-kagariが優れている点は
今のところ*ありません*。
SSPを使える環境であればそちらを使うことを推奨します。

## License

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

