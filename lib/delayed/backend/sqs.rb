require_relative 'sqs_worker.rb'

module Delayed
  module Backend
    module Sqs
      class Job
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
        extend Delayed::Backend::Sqs::Worker

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

          sent_message = job_queue.send_message(handler, delay_seconds: delay_seconds)
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

        def job_queue_url
          @job_queue_url = queue_url || self.class.sqs.queues.named(queue.to_s).url
        end

        def job_queue
          self.class.sqs.queues[job_queue_url]
        end
      end
    end
  end
end
