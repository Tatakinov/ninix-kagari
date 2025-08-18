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

- ruby-gtk4

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

### Windows

#### Releasesのninix-kagari.zipを利用する場合

zipを展開して`run.bat`を実行すればOKです。

Windows10より前のバージョンを使っている方は`run_lower_version_10.bat`を
実行してください。

#### 自分でruby環境を用意する場合

rubyinstallerのRuby+Devkitの**x64**をインストールしてください。

cmd/powershellでRequirementsに書かれているものをインストールします。
以下は最小構成の場合。

```
> gem install gettext gio2 gtk4 rubyzip rake rake-compiler
> gem install narray -- --with-cflags=-std=c99
> git clone https://github.com/Tatakinov/ninix-fmo
> cd ninix-fmo
> rake install
```

narrayはそのままだと最近のCコンパイラでは
コンパイルエラーになるため、
`--with-cflags=-std=c99`を指定してやる必要があります。
その前の`--`も必要なので省略しないでください。

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

### コマンドラインオプション

- --sstp\_port `sstp_port`: 追加で1つSSTPポートをlistenします
- --debug: デバッグ出力を有効にします
- --logfile `logfile`: ログをファイル`logfile`に出力します
- --ghost `ghost_name | ghost_dir`: 指定されたゴーストで起動します
- --exit-if-not-found: 上記で指定したゴーストが存在しない場合、終了します
- --show-console: ゴーストが起動する場合でも`Console`ウィンドウを表示します

## SHIORI

### Linux

ビルドの必要なSHIORIが存在します。

詳しくは
[Wiki](https://github.com/Tatakinov/ninix-kagari/wiki)
を参照してください。

### Windows

未検証

## SAORI

### Linux

ninix-kagariで使用できるSAORIは現状[ninix-saori](https://github.com/Tatakinov/ninix-saori)のみです。
詳しい説明は上記URLから。

### Windows

未検証

## Caution

エンバグ・デグレーション上等で作っているので、必ずしも最新版が
一番良いとは限りません。

Windowsは今のところv1.xの方が動きます。

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

Copyright (C) 2024, 2025 by Tatakinov

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License (version 2) as
published by the Free Software Foundation.  It is distributed in the
hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.  See the GNU General Public License for more details.

