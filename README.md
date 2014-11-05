This is an [Amazon SQS](http://aws.amazon.com/sqs/) backend for [delayed_job](http://github.com/collectiveidea/delayed_job)

# Getting Started

## Get credentials

Configure AWS with:
```ruby
aws.config(
  :access_key_id => 'XXXXXX',
  :secret_access_key => 'XXXXXX',
  :region => 'XXXXXX')
```

One and only one worker's queue must be defined:
```ruby
Delayed::Worker.queue = [:some_queue]
# or with URL to avoid SQS requests
Delayed::Backend::Sqs.queue_url = 'https://sqs.us-west-2.amazonaws.com/146382271533/some_queue'
Delayed::Backend::Sqs.queue_url = AWS::SQS.new.queue.named(:some_queue).url
```

If many queue are defined, only the first one will be used. When enqueuing a new job, a default queue name must be defined or the job must have a queue set.

Due to SQS limitation, SQS Backend only support a subset of DelayedJob feature. The following feature are **not supported**:

 * Scheduling a job in the future
 * Enqueuing a job without a queue defined
 * Delete all job from a worker queue
 * Worker set with multiple queues
 * Job's priority
 * `run_at`, `locked_at`, `locked_by` and `failed_at` job attribute are not used and persisted
 * `error` hook is never called. On error, a job always calls `failure`, but the jub will stay in the queue.
 * `max_attempts` is not used. Use SQS queue settings instead.
 * `destroy_failed_job` is `false` by default since SQS works by leaving failed job in a queue.

Jobs have the following additional attributes:

 * `request_id`: Message request id
 * `delay_seconds`: Delay before the jobs is avaiable in the SQS queue
 * `message`: SQS `ReceivedMessage` object

