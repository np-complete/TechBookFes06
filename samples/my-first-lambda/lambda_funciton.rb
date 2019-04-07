require 'json'
require 'uri'
require 'net/http'

def lambda_handler(event:, context:)
  event['Records'].each do |record|
    key = record['s3']['object']['key']
    uri = URI(ENV['WEBHOOK_URL'])
    payload = JSON.generate(text: "s3: #{key} created.")
    Net::HTTP.post_form(uri, payload: payload)
  end
  {statusCode: 200, body: ''}
end
