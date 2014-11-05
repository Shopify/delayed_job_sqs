require 'rspec'
require 'delayed_job_sqs'
require 'sample_jobs'
require 'byebug'

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

AWS.config(
  :access_key_id => 'AKIAIZMKAWZTUZTXJKPQ',
  :secret_access_key => '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',
  :region => 'us-west-2')

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

