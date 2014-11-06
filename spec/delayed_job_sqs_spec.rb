require 'helper'
require 'active_support/core_ext'

describe Delayed::Backend::Sqs::Job do
  let(:worker) { Delayed::Worker.new }
  let(:queues) do
    sqs = AWS::SQS.new
    ['test', 'other_test'].map{|n|sqs.queues.named(n)}
  end

  def create_job(opts = {})
    described_class.create({:payload_object => SimpleJob.new, queue: 'test'}.merge(opts))
  end

  def delete_all
    queues.each do |queue|
      while (m = queue.receive_message(wait_time_seconds: 0, limit: 10)).any?
        m.each(&:delete)
      end
    end
  end

  before do
    Delayed::Backend::Sqs::Job.class_eval{@sqs_queue_url = nil}
    Delayed::Worker.delay_jobs = true
    Delayed::Worker.default_queue_name = 'test'
    Delayed::Worker.queues = ['test']
    SimpleJob.runs = 0
    delete_all
  end

  after do
    Delayed::Worker.reset
  end

  describe '#reload' do
    it 'reloads the payload' do
      job = described_class.enqueue :payload_object => SimpleJob.new
      expect(job.payload_object.object_id).not_to eq(job.reload.payload_object.object_id)
    end
  end

  describe 'enqueue' do
    context 'with a hash' do
      it "raises ArgumentError when handler doesn't respond_to :perform" do
        expect { described_class.enqueue(:payload_object => Object.new) }.to raise_error(ArgumentError)
      end

      it 'is able to set queue' do
        job = described_class.enqueue :payload_object => NamedQueueJob.new, :queue => 'other_test'
        expect(job.queue).to eq('other_test')
      end

      it 'uses default queue' do
        job = described_class.enqueue :payload_object => SimpleJob.new
        expect(job.queue).to eq(Delayed::Worker.default_queue_name)
      end

      it "uses the payload object's queue" do
        job = described_class.enqueue :payload_object => NamedQueueJob.new
        expect(job.queue).to eq(NamedQueueJob.new.queue_name)
      end

      it 'is able to set queue from url' do
        queue_url = AWS::SQS.new.queues.named('test').url
        described_class.enqueue :payload_object => NamedQueueJob.new, :queue_url => queue_url
        expect(described_class.count).to eq(1)
      end
    end

    context 'with multiple arguments' do
      it "raises ArgumentError when handler doesn't respond_to :perform" do
        expect { described_class.enqueue(Object.new) }.to raise_error(ArgumentError)
      end

      it 'increases count after enqueuing items' do
        described_class.enqueue SimpleJob.new
        expect(described_class.count).to eq(1)
      end

      it 'works with jobs in modules' do
        M::ModuleJob.runs = 0
        job = described_class.enqueue M::ModuleJob.new
        expect { job.invoke_job }.to change { M::ModuleJob.runs }.from(0).to(1)
      end
    end

    context 'with delay_jobs = false' do
      before(:each) do
        Delayed::Worker.delay_jobs = false
      end

      it 'invokes the enqueued job' do
        job = SimpleJob.new
        expect(job).to receive(:perform)
        described_class.enqueue job
      end

      it 'returns a job, not the result of invocation' do
        expect(described_class.enqueue(SimpleJob.new)).to be_instance_of(described_class)
      end
    end
  end

  describe 'callbacks' do
    before(:each) do
      CallbackJob.messages = []
    end

    %w[before success after].each do |callback|
      it "calls #{callback} with job" do
        job = described_class.enqueue(CallbackJob.new)
        expect(job.payload_object).to receive(callback).with(job)
        job.invoke_job
      end
    end

    it 'calls before and after callbacks' do
      job = described_class.enqueue(CallbackJob.new)
      expect(CallbackJob.messages).to eq(['enqueue'])
      job.invoke_job
      expect(CallbackJob.messages).to eq(%w[enqueue before perform success after])
    end

    it 'calls the after callback with an error' do
      job = described_class.enqueue(CallbackJob.new)
      expect(job.payload_object).to receive(:perform).and_raise(RuntimeError.new('fail'))

      expect { job.invoke_job }.to raise_error
      expect(CallbackJob.messages).to eq(['enqueue', 'before', 'error: RuntimeError', 'after'])
    end

    it 'calls error when before raises an error' do
      job = described_class.enqueue(CallbackJob.new)
      expect(job.payload_object).to receive(:before).and_raise(RuntimeError.new('fail'))
      expect { job.invoke_job }.to raise_error(RuntimeError)
      expect(CallbackJob.messages).to eq(['enqueue', 'error: RuntimeError', 'after'])
    end
  end

  describe 'payload_object' do
    it 'raises a DeserializationError when the job class is totally unknown' do
      job = described_class.new :handler => '--- !ruby/object:JobThatDoesNotExist {}'
      expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
    end

    it 'raises a DeserializationError when the job struct is totally unknown' do
      job = described_class.new :handler => '--- !ruby/struct:StructThatDoesNotExist {}'
      expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
    end

    it 'raises a DeserializationError when the YAML.load raises argument error' do
      job = described_class.new :handler => '--- !ruby/struct:GoingToRaiseArgError {}'
      expect(YAML).to receive(:load_dj).and_raise(ArgumentError)
      expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
    end

    it 'raises a DeserializationError when the YAML.load raises syntax error' do
      # only test with Psych since the other YAML parsers don't raise a SyntaxError
      if YAML.parser.class.name !~ /syck|yecht/i
        job = described_class.new :handler => 'message: "no ending quote'
        expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
      end
    end
  end

  describe 'reserve' do
    before do
      Delayed::Worker.max_run_time = 2.minutes
    end

    after do
      Time.zone = nil
    end

    it 'reserves open jobs' do
      job = create_job
      expect(described_class.reserve(worker).handler).to eq(job.handler)
    end

    it 'reserves from queue_url if defined' do
      Delayed::Backend::Sqs::Job.queue_url = AWS::SQS.new.queues.named('other_test').url
      Delayed::Worker.queues = ['test']
      job = create_job(queue: 'other_test')
      polled_job = described_class.reserve(worker)
      expect(polled_job.handler).to eq(job.handler)
    end
  end

  context '#name' do
    it 'is the class name of the job that was enqueued' do
      expect(described_class.new(:payload_object => ErrorJob.new).name).to eq('ErrorJob')
    end

    it 'is the method that will be called if its a performable method object' do
      job = described_class.new(:payload_object => NamedJob.new)
      expect(job.name).to eq('named_job')
    end
  end

  context 'large handler' do
    before do
      text = 'Lorem ipsum dolor sit amet. ' * 1000
      @job = described_class.enqueue Delayed::PerformableMethod.new(text, :length, {})
    end

    it 'has an id' do
      expect(@job.id).not_to be_nil
    end
  end

  context 'named queues' do
    context 'when worker has one queue set' do
      before(:each) do
        worker.queues = ['test']
      end

      it 'only works off jobs which are from its queue' do
        expect(SimpleJob.runs).to eq(0)

        create_job(:queue => 'test')
        create_job(:queue => 'other_test')
        worker.work_off

        expect(SimpleJob.runs).to eq(1)
      end
    end
  end

  context 'max_attempts' do
    before(:each) do
      @job = described_class.enqueue SimpleJob.new
    end

    it 'always set to 1' do
      expect(@job.max_attempts).to eq(1)
    end

    it 'do not use the max_attempts value on the payload when defined' do
      @job.payload_object.max_attempts = 99
      expect(@job.max_attempts).to eq(1)
    end
  end

  describe '#max_run_time' do
    before(:each) { @job = described_class.enqueue SimpleJob.new }

    it 'is not defined' do
      expect(@job.max_run_time).to be_nil
    end

    it 'results in a default run time when not defined' do
      expect(worker.max_run_time(@job)).to eq(Delayed::Worker::DEFAULT_MAX_RUN_TIME)
    end

    it 'uses the max_run_time value on the payload when defined' do
      expect(@job.payload_object).to receive(:max_run_time).and_return(30.minutes)
      expect(@job.max_run_time).to eq(30.minutes)
    end

    it 'results in an overridden run time when defined' do
      expect(@job.payload_object).to receive(:max_run_time).and_return(45.minutes)
      expect(worker.max_run_time(@job)).to eq(45.minutes)
    end

    it 'job set max_run_time can not exceed default max run time' do
      expect(@job.payload_object).to receive(:max_run_time).and_return(Delayed::Worker::DEFAULT_MAX_RUN_TIME + 60)
      expect(worker.max_run_time(@job)).to eq(Delayed::Worker::DEFAULT_MAX_RUN_TIME)
    end
  end

  describe 'worker integration' do
    before do
      delete_all
      SimpleJob.runs = 0
    end

    describe 'running a job' do
      it 'fails after Worker.max_run_time' do
        Delayed::Worker.max_run_time = 1.second
        job = Delayed::Job.create :payload_object => LongRunningJob.new
        worker.run(job)
        expect(job.reload.error.message).to match(/expired/)
        expect(job.reload.error.message).to match(/Delayed::Worker\.max_run_time is only 1 second/)
        expect(job.attempts).to eq(1)
      end

      context 'when the job raises a deserialization error' do
        after do
          Delayed::Worker.destroy_failed_jobs = true
        end

        it 'marks the job as failed' do
          Delayed::Worker.destroy_failed_jobs = false
          job = described_class.create :handler => '--- !ruby/object:JobThatDoesNotExist {}'
          worker.run(job)
          expect(job).to be_failed
        end
      end
    end

    describe 'failed jobs' do
      before do
        @job = Delayed::Job.enqueue(ErrorJob.new)
      end

      after do
        # reset default
        Delayed::Worker.destroy_failed_jobs = true
      end

      it 'records last_error when destroy_failed_jobs = false, max_attempts = 1' do
        Delayed::Worker.destroy_failed_jobs = false
        Delayed::Worker.max_attempts = 1
        worker.run(@job)
        @job.reload
        expect(@job.error.message).to match(/did not work/)
        expect(@job.attempts).to eq(1)
        expect(@job).to be_failed
      end

      it "does not fail when the triggered error doesn't have a message" do
        error_with_nil_message = StandardError.new
        expect(error_with_nil_message).to receive(:message).and_return(nil)
        expect(@job).to receive(:invoke_job).and_raise error_with_nil_message
        expect { worker.run(@job) }.not_to raise_error
      end
    end

    context 'reschedule' do
      before do
        @job = Delayed::Job.create :payload_object => SimpleJob.new
      end

      shared_examples_for 'any failure more than Worker.max_attempts times' do
        context "when the job's payload has a #failure hook" do
          before do
            @job = Delayed::Job.create :payload_object => OnPermanentFailureJob.new
            expect(@job.payload_object).to respond_to(:failure)
          end

          it 'runs that hook' do
            expect(@job.payload_object).to receive(:failure)
            worker.reschedule(@job)
          end

          it 'handles error in hook' do
            Delayed::Worker.destroy_failed_jobs = false
            @job.payload_object.raise_error = true
            expect { worker.reschedule(@job) }.not_to raise_error
            expect(@job.failed_at).to_not be_nil
          end
        end

        context "when the job's payload has no #failure hook" do
          # It's a little tricky to test this in a straightforward way,
          # because putting a not_to receive expectation on
          # @job.payload_object.failure makes that object incorrectly return
          # true to payload_object.respond_to? :failure, which is what
          # reschedule uses to decide whether to call failure. So instead, we
          # just make sure that the payload_object as it already stands doesn't
          # respond_to? failure, then shove it through the iterated reschedule
          # loop and make sure we don't get a NoMethodError (caused by calling
          # that nonexistent failure method).

          before do
            expect(@job.payload_object).not_to respond_to(:failure)
          end

          it 'does not try to run that hook' do
            expect do
              Delayed::Worker.max_attempts.times { worker.reschedule(@job) }
            end.not_to raise_exception
          end
        end
      end

      context "and we don't want to destroy jobs" do
        before do
          Delayed::Worker.destroy_failed_jobs = false
        end

        after do
          Delayed::Worker.destroy_failed_jobs = true
        end

        it_behaves_like 'any failure more than Worker.max_attempts times'

        it 'is failed if it failed more than Worker.max_attempts times' do
          expect(@job.reload).not_to be_failed
          Delayed::Worker.max_attempts.times { worker.reschedule(@job) }
          expect(@job.reload).to be_failed
        end
      end
    end
  end
end

