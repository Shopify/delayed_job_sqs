module Delayed
  module Backend
    module Sqs
      class Job
        cattr_accessor :queue_url

        attr_accessor :id
        attr_accessor :request_id
        attr_accessor :queue_url
        attr_accessor :queue
        attr_accessor :attempts # Approximate
        attr_accessor :handler
        attr_accessor :sent_at
        attr_accessor :delay_seconds
        attr_accessor :message

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
          message = sqs_queue.receive_message(limit: 1, attributes: [:all])
          new(message) if message
        end

        def self.create(*args)
          new(*args).tap{|j|j.save}
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

            self.delay_seconds = data[:delay_seconds] || 0
            self.handler = data[:handler] || ''
            self.payload_object = data[:payload_object] if data[:payload_object]
            self.queue = data[:queue] || Delayed::Worker.default_queue_name
            self.queue_url = data[:queue_url]
            self.attempts = 0
          end
        end

        def save
          raise ArgumentError, 'Cannot update existing job' if id

          sent_message = sqs_queue.send_message(handler, delay_seconds: delay_seconds)
          self.id = sent_message.message_id
        end
        alias_method :save!, :save

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
          # SQS doesn't provide any API to delete all messages
          # Either work off a queue or delete the queue itself
          raise NotImplementedError
        end

        def reschedule_at
          # SQS doesn't support scheduling
          raise NotImplementedError
        end

        def update_attributes(attrs = {})
          attrs.each { |k, v| send(:"#{k}=", v) }
        end

        def queue
          queue_url || @queue
        end

        private

        def self.sqs
          @sqs ||= AWS::SQS::new
        end

        def self.sqs_queue_url
          @sqs_queue_url ||= queue_url
          @sqs_queue_url ||= self.sqs.queues.named(Delayed::Worker.queues.first.to_s).url
        end

        def self.sqs_queue
          sqs.queues[sqs_queue_url]
        end

        def sqs_queue_url
          @sqs_queue_url ||= queue_url
          @sqs_queue_url ||= self.class.sqs.queues.named(queue.to_s).url
        end

        def sqs_queue
          self.class.sqs.queues[sqs_queue_url]
        end
      end
    end
  end

  class Worker
    self.destroy_failed_jobs = false
  end
end
