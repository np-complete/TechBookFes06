require 'aws-sdk-s3'

desc 'publish book'
task :publish do
  if ENV['CIRCLE_PR_NUMBER']
  else
    client = Aws::S3::Client.new
    client.put_object body: File.open('TBF06.pdf'), bucket: 'np-complete-books', key: 'pdf/TechBookFes06.pdf',  acl: 'public-read'
  end
end
