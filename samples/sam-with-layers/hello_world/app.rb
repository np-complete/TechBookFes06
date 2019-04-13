require 'json'
require 'hello'
require 'pg'

def lambda_handler(event:, context:)
  PG.connect(dbname: 'hello')
  {
    statusCode: 200,
    body: {
      message: Hello.new('world').say
    }.to_json
  }
end
