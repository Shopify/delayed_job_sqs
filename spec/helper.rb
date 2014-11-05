require 'rspec'
require 'delayed_job_sqs'
require 'sample_jobs'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

AWS.config(
  :access_key_id => 'YOUR_ACCESS_KEY_ID',
  :secret_access_key => 'YOUR_SECRET_ACCESS_KEY')

def create_queue(name)
  sqs = AWS::SQS.new
  begin
    sqs.queues.named(name)
  rescue AWS::SQS::Errors::NonExistentQueue
    sqs.queues.create(name)
  end
end

create_queue('test')
create_queue('other_test')

