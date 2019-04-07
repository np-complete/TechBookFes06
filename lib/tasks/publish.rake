require 'aws-sdk-s3'

desc 'publish book'
task :publish do
  if ENV['CIRCLE_PR_NUMBER']
  else
    client = Aws::S3::Client.new
    client.put_object acl: 'public-read', body: File.open('TBD06.pdf'), bucket: 'np-complete-books', key: 'release/TechBookFes06.pdf'
  end
end
