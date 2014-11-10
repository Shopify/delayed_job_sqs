module Delayed
  module Backend
    module Sqs
      module Worker
        attr_accessor :queue_url

        def clear_locks!(*args)
          true
        end

        def reserve(worker, max_run_time = Delayed::Worker.max_run_time)
          message = worker_queue.receive_message(limit: 1, attributes: [:all])
          new(message) if message
        end

        def create(*args)
          new(*args).tap{|j|j.save}
        end

        def count
          worker_queue.approximate_number_of_messages || 0
        end

        def db_time_now
          Time.now.utc
        end

        def delete_all
          # SQS doesn't provide any API to delete all messages
          # Either work off a queue or delete the queue itself
          raise NotImplementedError
        end

        def sqs
          @sqs ||= AWS::SQS::new
        end

        def worker_queue_url
          @worker_queue_url = queue_url || self.sqs.queues.named(Delayed::Worker.queues.first.to_s).url
        end

        def worker_queue
          sqs.queues[worker_queue_url]
        end
      end
    end
  end

  class Worker
    self.destroy_failed_jobs = false
  end
end
