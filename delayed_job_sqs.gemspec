# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |s|
  s.require_paths = ['lib']
  s.name          = 'delayed_job_sqs'
  s.version       = '0.0.2'
  s.authors       = ['Israël Hallé']
  s.email         = ['isra017@gmail.com']
  s.description   = 'Amazon SQS backend for delayed_job'
  s.summary       = 'Amazon SQS backend for delayed_job'
  s.homepage      = 'https://github.com/isra17/delayed_job_sqs'
  s.license       = 'MIT'

  s.files         = `git ls-files`.split($/)
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})

  s.add_runtime_dependency('aws-sdk', '~> 1.56.0')
  #s.add_runtime_dependency('delayed_job', '~> 4.0.4')

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rake'
end

