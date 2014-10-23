module Delayed
  module Backend
    module Sqs
      class Job
        attr_accessor :id
        attr_accessor :request_id
        attr_accessor :queue
        attr_accessor :attempts # Approximate
        attr_accessor :handler
        attr_accessor :delay_seconds

        # Unsupported attributes
        attr_accessor :priority
        attr_accessor :run_at
        attr_accessor :locked_at
        attr_accessor :locked_by
        attr_accessor :failed_at

        include Delayed::Backend::Base

        def self.clear_locks!(*args)
          true
        end

        def self.reserve(worker, limit = 5, max_run_time = Worker.max_run_time)
          message = sqs_queue.receive_message(limit: 1)
          new(message) if message
        end

        def self.create(*args)
          new(*args).tap{|j|j.save}
        end

        def self.create!(*args)
          create(*args)
        end

        def self.count
          sqs_queue.approximate_number_of_messages || 0
        end

        def self.db_time_now
          Time.now.utc
        end

        def initialize(data = {})
          @message = nil

          if data.is_a?(AWS::SQS::ReceivedMessage)
            @message = data
            self.id = @message.id
            self.request_id = @message.request_id
            self.queue = @message.queue
            self.attempts = @message.approximate_receive_count || 0
            self.handler = @message.body
          else
            data.symbolize_keys!

            self.queue = data[:queue] || Delayed::Worker.default_queue_name
            self.delay_seconds = data[:delay_seconds] || 0
            self.payload_object = data[:payload_object]
            self.attempts = 0

            self.run_at = data[:run_at] || self.class.db_time_now
          end
        end

        def save
          raise ArgumentError, 'Cannot update existing job' if id

          sent_message = sqs_queue.send_message(handler, delay_seconds: delay_seconds)
          self.id = sent_message.message_id
        end

        def save!
          save
        end

        def destroy
          @message.delete if @message
        end

        def max_attempts
          1
        end

        def reload
          reset
          self
        end

        def self.delete_all
          raise NotImplementedError
        end

        def reschedule_at
          raise NotImplementedError
        end

        def update_attributes(attrs = {})
          attrs.each { |k, v| send(:"#{k}=", v) }
        end

        private

        def self.sqs
          @sqs ||= AWS::SQS::new
        end

        def self.sqs_queue
          @queue ||= sqs.queues.named(Delayed::Worker.queues.first.to_s)
        end

        def sqs_queue
          @sqs_queue ||= self.class.sqs.queues.named(queue.to_s || Delayed::Worker.queues.first.to_s)
        end
      end
    end
  end

  class Worker
    self.destroy_failed_jobs = false
  end
end
