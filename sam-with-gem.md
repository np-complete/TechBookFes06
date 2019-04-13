# SAMでGemを使ってみる

Rubyを書くなら当然便利なGemを使いたくなりますね。
SAMの `hello_world` ディレクトリには最初から `Gemfile` が入っているので、
やはりこれを使えということなんでしょう。
とりあえず適当な[Gemを使ったコード](https://github.com/np-complete/TechBookFes06/blob/master/samples/sam-with-gem)を書いてみましょう。
特に意味のあるコードにする必要はないので、ただ `require` して簡単なコードを実行するだけのコードでいいと思います。

```ruby

# hello_world/Gemfile

source 'https://rubygems.org'
gem 'faraday'

# hello_world/app.rb

require 'json'
require 'faraday'

def lambda_handler(event:, context:)
  Faraday.get('https://google.com')
  { statusCode: 200, body: '' }
end
```

この段階でおもむろにデプロイしてテストを実行すると、  `cannot load such file -- faraday` とエラーが出ます。
Gemがインストールされていないようですね。
`Gemfile` を用意していても自動的に `bundle install` をしてくれたりは無いようです。

とりあえずSAMのパッケージの中に全部入れれば良さそうなので、いつもどおりの `bundle install --path vendor/bundle` をしてみます。
デプロイしてコンソールを確認すると、ファイル一覧の中に `vendor` ディレクトリがあり、Gemが配置されていることがわかります。
テストを実行してみると、何もエラーなく終了しました。

## Gemを読み込むのはそんなに簡単ではないという話

Gemの場所を指定する超重要ファイルである `.bundle` が無いように見えますが、隠しファイルを表示するとちゃんと出てきます。
手元から `.bundle` を削除し、デプロイしてみましょう。実行してもエラーは起こりません。
更にもっと超重要ファイルである `Gemfile` と `Gemfile.lock` も消してみましょう。
なんと、**Gemfileがなくても成功します**。
これはかなり不思議な動作です。
とりあえず `bundler` を使っていないのは確実なようです。
なぜ `vendor/bundle` 以下をGemとして読めているのでしょか、探ってみましょう。

`require` のコードから辿っていくと、最終的にGemのリストは `Gem::Specification.stubs` に格納されるようです。
`Gem::Specification.stubs.map(&:name)` を実行してみると、明示的にはインストールしていない `aws-***` と並び、確かに `faraday` は存在します。`gems_dir` を見てみると `/var/tasks/vendor/bundle/ruby/2.5.0/gems` になっています。
`Gem::Specification.dirs` にもやはり該当パスが存在し、`Gem.paths` を辿って `Gem::PathSupport` というところで定義されていることがわかりました。

コードを読んでみると `ENV['GEM_PATH']` が重要らしいので出力してみると、まさにドンピシャ、`/var/task/vendor/bundle/ruby/2.5.0:/opt/ruby/gems/2.5.0` となっていました。
どうやらLambdaのデフォルトの環境変数でこう設定されているようです。

最後に、おもむろに `vendor/bundle` を削除します。それでも `ENV['GEM_PATH']` には `vendor/bundle` が存在し続けています。
つまり、`ENV['GEM_PATH']` に `vendor/bundle` が含まれているのは完全に固定の値であり、
**いつもどおりやったらGemが使えたのはただの偶然** だと言えます。
その証拠に、 `bundle install --path gems` のように `vendor/bundle` 以外を指定した場合、**Gemの読み込みは失敗します**。
このあたり暗黙のルールが完全に共通認識になっている感じ、**とてもRubyらしい** と思いました。
というわけで、Gemは `vendor/bundle` に置くか、`/opt/ruby/gems/2.5.0` に置けば良いことがわかりました。

## C拡張が入ったGemを使う

RubyにはC言語インターフェイスが用意されており、C言語拡張が入ったGemを作ることができます。
そのようなGemを `gem install` すると、自動でコンパイルが走り、所定の場所に `.so` ファイルが作られます。
今回はC拡張を含むGemを、

- 単純に高速化のためにC拡張を使う (例: `redcarpet`)
- 外部のCのライブラリをRubyから使うためにC拡張を使う (例: `mysql2`)

の2種類に分割して考えます。
ようは、外部ライブラリを使うか使わないかで難しさが変わるためです。

まず、先程見たようにLambda内で `bundle install` はしてくれないので、**.soファイルもパッケージに含める** 必要があります。
となると、アーキテクチャの問題が出てきますね。
まず一番雑に手元で `bundle install` してみましょう。
`vendor/bundle/ruby/2.5.0/gems/redcarpet-3.4.0/lib/redcarpet.so` が存在することを確認しておきましょう。

コードはこんな感じです。

```ruby
require 'json'
require 'redcarpet'

def lambda_handler(event:, context:)
  md = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  { statusCode: 200, body: JSON.generate(text: md.render('hello, **world**')) }
end
```

これをそのままデプロイすると、`require 'redcarpet'` が失敗しエラーになります。
非常に重要なヒントが書いてあり、

    Ignoring redcarpet-3.4.0 because its extensions are not built.

つまり、ビルドに失敗しているという判定がなされているようなのです。
もちろん.soファイルは存在するので、想定していたとおりアーキテクチャの違いなどで読み込めていないと予想できます。

`cat /etc/*-release` を実行すると、ディストリビューションは **Amazon Linux AMI** であることがわかります。
Amazon LinuxはRedHat系なので、Ubuntuでビルドしたバイナリが使えないのはそういうことなのでしょう。
なんとかしてAmazonLinuxでビルドをしないといけないのですが、なんとAmazon LinuxはDockerイメージが提供されています。
このイメージにRubyをインストールし、ビルド用イメージを作ってみましょう。
できあがったイメージが [masarakki/aws-lambda-ruby](https://github.com/masarakki/aws-lambda-ruby) です。

このイメージ内の `bundle` を使って、ホストマシンにgemをインストールします。

    $ rm -r vendor/bundle
    $ docker run -it -v `pwd`:`pwd` -u `id -u`:`id -g` -w `pwd` \
                 masarakki/aws-lambda-ruby \
                 bundle install --path vendor/bundle

これでAmazon Linuxベースのマシンでビルドした `redcarpet` が入手できたはずです。
`bundle exec irb` を実行してみると、

    Could not find redcarpet-3.4.0 in any of the sources

と言われ、先ほどと立場が逆転していることがわかります。これは期待できそうです。
早速デプロイしてテストを実行してみたところ、見事に成功しました。

なお、双方の.soファイルを `file` コマンドで見たところ、どちらも**64bit ELF**なので、アーキテクチャの問題ではなさそうです。
依存ライブラリの問題ではないかと疑い `ldd` してみたら、ライブラリの数まで違っていたので、おそらくこれが原因なのでしょう。
ライブラリの配置場所やファイル名は基本的に一致しているようでした。
関数のアドレスが違うのでは? と言う指摘をされましたが、正直Cの素養が全然ないのでよくわかりません。
こういうところで問題が出るということを知れたことは新鮮です。

ということは、**クロスコンパイル** では問題は解決しないと予想できます。
また、Lambda内部のAmazon Linuxがバージョンアップなどで変化した場合も動かなくなる可能性があります。
これはかなり茨の道なのではないかと感じました。
Lambdaが動いている実体コンピュータのバージョン指定的なオプションが欲しいと思いました[^1]。

[^1]: ちがうそうじゃない 頼むから `bundle install` させてくれ

## 外部ライブラリを使うGemを使う

次に、外部ライブラリを使うGemを試してみましょう。
ただでさえ難しかった.soファイルが、今度はシステムの別の場所にもあるので更に難しくなります。
とはいえ、こちらも難易度に2段階あり、まずは簡単な **既にシステムにインストールされている** ライブラリを使ったGemに挑戦します。
Amazon Linuxには最初から様々なライブラリがインストールされているので、`/usr/lib64` を眺めながらインストールできそうなGemを探します・・・・・・・`nokogiri` しか見つかんねえ。

どうせなら前回のコードを活かして `nokogiri` を使ってみましょう。

```ruby
require 'json'
require 'redcarpet'
require 'nokogiri'

def lambda_handler(event:, context:)
  md = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  html = Nokogiri::HTML(md.render('hello, **world**'))
  { statusCode: 200, body: JSON.generate(text: html.css('strong').text) }
end
```

デプロイしてみるとエラーなく終了し、

```json
{"statusCode": 200, "body": "{\"text\":\"world\"}"}
```

と出力されます。上手く動いているようです。
しかし、このあたりからバイナリを含むせいでパッケージサイズが大きくなり、
コンソール上でコードが確認できなくなるのがつらいところです。

## インストールされてない外部ライブラリを使う

さていよいよ、一番の難関になりそうな **インストールされてないライブラリ** を使うGemに挑戦しましょう。
とりあえず `postgres` のコネクタである `pg` をインストールしてみます。
もちろん `libpq` は入ってないのでそのままではインストールできません。

そこで、まずは `libpq` をインストールすることを考えます。

    docker run it -v `pwd`:`pwd` -w `pwd` masarakki/aws-lambda-ruby /bin/bash

でdockerイメージに入り、

    yum install postresql-devel

でライブラリをインストールします。
あとは、

    bundle install --path vendor/bundle

でGemをインストールします。
この方法は少し問題があり、Gemが `root` でインストールされてしまいますが、今のところどうしようもありません。

ホストコンピュータに戻り `ldd` で依存ライブラリを見てみます。
`libpq.so.5 => /usr/lib/x86_64-linux-gnu/libpq.so.5 (0x00007fdaa32d1000)` の一行が入っているのが見つかります。
おそらくこのまま持っていってもLambdaの環境には `libpq.so.5` が無いので動かないでしょう。
この時点でデプロイして試したところ、やはり `pg` が見つからないというエラーになります。
とはいえ、前回のようにビルドできてないからインストールしろというメッセージではなく、普通に無いと言われています。
ちょっと予想外の反応です。

さーこれどうしましょうか・・・
Lambdaは `/var/task` に単純にファイルが展開されるだけなので、 `/usr/lib` の下に `libpq.so` を置くことは難しそうです。
