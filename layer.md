# Layerとカスタムランタイム

ライブラリを設置できない問題に対し、Lambdaの **Layer** という機能が使える可能性があるので調べます。
[ドキュメント](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html) によると、Layerは **ライブラリ、カスタムランタイム、その他の依存をまとめたZIPアーカイブ** という定義のようです。
もしかしたらこれで `libpq.so` が配置できるかもしれませんが、ドキュメントによるとどうやら主目的は毎回のデプロイサイズを小さく保つことのようです。

ドキュメントを探っていくと、それぞれのランタイム向けにどのようにファイルを配置するか書いてあります。
例えばRubyは、 `ruby/gems/2.5.0/` の中にGemの構造のファイル群を入れれば良いようです。
また、どのランタイムに対しても `lib/` がライブラリに対応すると書いてあります。
早速試してみましょう。

## シンプルなRubyのライブラリをLayer化する

まず単純に、 `ruby/lib` に単純なRubyのコードを置き、`app.rb` から読み込めるかどうか実験してみましょう。

    mkdir -p layers/simple-layer/ruby/lib
    cd layers/simple-layer
    # ruby/lib/hello.rb に Hello クラスを作る
    zip -r simple-layer.zip ruby

zipコマンドクソ難しいですね。

    unzip -l simple-layer.zip
    Archive:  simple-layer.zip
      Length      Date    Time    Name
    ---------  ---------- -----   ----
            0  2019-04-13 13:26   ruby/
            0  2019-04-13 13:27   ruby/lib/
          101  2019-04-13 13:27   ruby/lib/hello.rb
    ---------                     -------
          101                     3 files

確認すると正しいディレクトリ構造になっていそうです。
この `simple-layer.zip` をとりあえずS3にアップロードします。

    aws s3 cp simple-layer.zip s3://masarakki-sam-deploy/simple-layer-v1.zip

Cloud Formationで `AWS::Serverless::LayerVersion` のリソースを作ってみましょう。
なお、Layerのバージョンを上げるにはContentUriのs3ファイル名を変更するしかありませんでした。

```yaml
Resources:
  HelloWorldFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: hello_world/
      Handler: app.lambda_handler
      Runtime: ruby2.5
      Layers:
        - !Ref SimpleLayer
  SimpleLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      ContentUri: s3://masarakki-sam-deploy/simple-layer-v1.zip
      CompatibleRuntimes:
        - ruby2.5
```

`app.rb` はシンプルにこんな感じにしました。

```ruby
require 'json'
require 'hello'

def lambda_handler(event:, context:)
  {
    statusCode: 200,
    body: {
      message: Hello.new('world').say
    }.to_json
  }
end
```

実行すると正しく動作しました。

## 共有ライブラリをLayer化する

さて、次は `pg` のGemに必要なライブラリをLayerにしてみましょう。
ひとまず、 `layers/pg-layer/lib` を作り、その中でDockerイメージにログインします。

    mkdir -p layers/pg-layer/lib
    cd layers/pg-layer/lib
    docker run -it -v `pwd`:`pwd` -w `pwd` amazon-linux /bin/bash

Dockerイメージの中に入ったらpostgresのライブラリをインストールし、インストールされたファイルをコピーします。

    yum install postgresql-devel
    cp /usr/lib64/libpq* .

これでホストマシンにライブラリがコピーされています。
先ほどと同じようにZIPファイルを作りS3にアップロードし、リソースを作ります。

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: sam-with-layers

Resources:
  HelloWorldFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: hello_world/
      Handler: app.lambda_handler
      Runtime: ruby2.5
      Layers:
        - !Ref SimpleLayer
        - !Ref PgLayer
  SimpleLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      ContentUri: s3://masarakki-sam-deploy/simple-layer-v2.zip
      CompatibleRuntimes:
        - ruby2.5
  PgLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      ContentUri: s3://masarakki-sam-deploy/pg-layer-v1.zip
```

`app.rb` の方は適当なデータベースに繋ぎに行くコードにしてみましょう。
アプリケーションのGemは前回と同様の方法でインストールします。
デプロイし実行してみると、

    could not connect to server: No such file or directory

というエラーが出ます。これは、`pg` のGemが無事にロードでき、さらに **実際にconnectを試みて** 失敗している、つまり確実に `libpq.so` に到達していると言えるでしょう。
実験は大成功です!!
最終的なコードは[samples/sam-with-layer](https://github.com/np-complete/TechBookFes06/tree/master/samples/sam-with-layers)にあります。

AWS Lambdaのマシンが持っていないライブラリでも、Layerを使いライブラリを渡すことによって、Gemが使えることがわかりました。
ひとつひとつのLambda関数を小さく保つために、共有ライブラリだけではなく、C拡張をビルドするようなファイルサイズが大きなGemも、Layer側に寄せていく方が良いという思想のようです。
しかし、Layerはできたての機能らしく、作業ログを見てわかるようにまだ **泥臭い** 作業をしなくてはならず、今回はアプリケーション側に持たせることにしました。
おそらく時間が経てばこのあたりも改善されていくことでしょう。
個人的には

```
  PgLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      Yum:
        - postgresql-devel
      Gem:
        - pg
```

みたいに書いたら上手いこと配置してくれるようなDSLが欲しいですね。

・・・・あれ? カスタムランタイムの話無くない?
