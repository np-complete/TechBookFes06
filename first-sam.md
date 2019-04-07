# AWS SAM を使ってみる

AWSのコンソールで簡単なLamdaを動かすことができました。
コンソール上でも複数ファイルを作ってライブラリのように読み込むこともできるし、同様にgemも置けます[^1]。
何だってできそうな感じがしますが、いやどう考えてもコンソールはいずれ破綻しますよね。
我々はプログラマなので、**Git管理が可能** なテキストベースのファイルとCLIツールがないと死んでしまいます。
そこで、**AWS SAM**(Serverless Application Model)というものを使ってみます。

[^1]: `Gemfile` は読まないので `bundle exec` ではないらしい

## AWS SAMとは

AWS SAMはLambdaでサーバレスアプリケーションを作るためのフレームワークです。
似たようなものに、Javascript界隈で先行した [severless](https://serverless.com/) や、
Rubyだと最近出た [Ruby on Jets](http://rubyonjets.com/) がありますが、
AWS SAMはその名の通りAWS公式ツールなのが大きな強みです。

AWS SAMは、実際には **Cloud Formation** をベースにしたLambdaの構成管理とデプロイのツールです。
Cloud Formationなので **人類にはかなり難しい** んですが、Lambdaくらいの範囲だとそこそこシンプルなのでなんとかなりそうです。
むしろ破綻しないくらいのシンプルなプログラムを目指しましょう。

## 初めてのSAMプログラム

先程のLambdaをSAMに移植していきましょう。
まずSAMのCLIツールをインストールします。

    pip install aws-sam-cli

インストールが完了したらおもむろにプロジェクトを作ります。

    sam init -r ruby2.5 -n my-first-sam

`-r` でランタイムを指定できます。Rubyのランタイムを指定して実行するときちんとRubyのファイルが作られます。
`myｰfirst-sam` ディレクトリが作られ、中には `template.yaml` と `hello_word` ディレクトリが作られます。
`template.yaml` がCloud Formationの構成ファイルで、`hello_world` の中身が実際のLamda関数になっています。
`hello_world` ディレクトリの中には `Gemfile` も存在します。
ススっとtemplateをいじっていきます。

```yaml
AWSTemplateFormatVersion: '2010-09-09'
 Transform: AWS::Serverless-2016-10-31
 Resources:
   HelloWorldFunction:
     Type: AWS::Serverless::Function
     Properties:
       CodeUri: hello_world/
       Handler: app.lambda_handler
       Runtime: ruby2.5
       Environment:
           Variables:
               WEBHOOK_URL: https://example.com/webhook

```

`hello_world/app.rb` の中身も前回のもので置き換えます。
おもむろにデプロイします。

    sam package --output-template-file packaged.yaml \
                --s3-bucket lambda-packages
    sam deploy --template-file packaged.yaml \
               --stack-name my-first-sam \
               --capabilities CAPABILITY_IAM

`package` コマンドでは自動的に必要なファイルがパッケージ化され、 `--s3-bucket` で指定したバケットにアップロードされます。
`deploy` コマンドで実際にCloud Formationのスタックにデプロイされ、変更が反映されます。
現時点では、まだトリガーとなるS3PUTの設定がありませんが、他の部分は前回のと同じ状態になっているはずです。

## トリガーを設定する

まずResourcesに対象となるS3バケットを作る設定をします。
[AWS::S3::Bucketのドキュメント](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-s3-bucket.html) を見ながら埋めていきましょう。
実は、必要なプロパティは一つもないので `Resources` の下に

```yaml
Bucket:
    Type: AWS::S3::Bucket
```

を追加するだけで完成です。 これで `Bucket` と言う名前で参照できるようになります。
この時点でデプロイしてみてS3バケットが作成されるのを確かめましょう。
名前を指定していないので、 `my-first-sam-bucket-(ランダム文字列)` というバケットができました。

次にイベントの設定です。
`HelloWorldFunciton` のプロパティにイベントを追加します。
[S3のイベントドキュメント](https://github.com/awslabs/serverless-application-model/blob/master/versions/2016-10-31.md#s3) を見て設定しましょう。

```yaml
Events:
    Uploaded:
        Type: S3
        Properties:
            Bucket: !Ref Bucket
            Events: s3:ObjectCreated:*
```

デプロイ実行してみてもトリガーのところには何も表示されません。
しかし、実際に対象バケットにファイルを追加してみると、トリガーが発火しLamdaが実行されていることがわかります。
少し困ったことに、バケット名を直接指定することはできないようで、必ず同じテンプレート内で作ったものを参照しなければならないようです。

最終的には[このようなテンプレート](https://github.com/np-complete/TechBookFes06/blob/master/samples/my-first-sam) になりました。

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: my-first-sam

Resources:
  HelloWorldFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: hello_world/
      Handler: app.lambda_handler
      Runtime: ruby2.5
      Environment:
        Variables:
          WEBHOOK_URL: https://example.com/webhook
      Events:
        Uploaded:
          Type: S3
          Properties:
            Bucket: !Ref Bucket
            Events: s3:ObjectCreated:*
  Bucket:
    Type: AWS::S3::Bucket
```

次はSAMでgemを使ったり複雑なコードにしていきます。
